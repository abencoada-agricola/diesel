-- Aplicar depois de schema.sql e usernames.sql. Preserva registros e contas existentes.
begin;
alter table public.records alter column user_id drop not null;
alter table public.records add column signature_source text not null default 'account' check(signature_source in ('account','declared'));
alter table public.records add column submission_key uuid;
alter table public.records add constraint records_identity check((signature_source='account' and user_id is not null and submission_key is null) or (signature_source='declared' and user_id is null and submission_key is not null));
create function private.submit_record(payload jsonb,operator_name text,account_id uuid,source_name text,receipt_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare existing public.records;r public.records;f public.fleets;limits jsonb;rules jsonb;k text;
begin
 r.id:=(payload->>'id')::uuid;
 select * into existing from public.records where id=r.id;
 if found then if (source_name='account' and existing.user_id=account_id) or (source_name='declared' and existing.signature_source='declared' and existing.submission_key=receipt_key) then return jsonb_build_object('id',r.id,'duplicate',true);else return jsonb_build_object('error','Identificador já utilizado.','status',409);end if;end if;
 if jsonb_typeof(payload->'date') is distinct from 'string' or (payload->>'date') !~ '^\d{4}-\d{2}-\d{2}$' then return jsonb_build_object('error','Data inválida.','status',422);end if;
 r.date:=(payload->>'date')::date;r.fleet:=payload->>'fleet';
 rules:=(select value from public.settings where id='rules');
 if not (rules->>'futureDate')::boolean and r.date>(now() at time zone 'America/Sao_Paulo')::date then return jsonb_build_object('error','A data não pode estar no futuro.','status',422);end if;
 foreach k in array array['engine','elevator','km','start','end','liters'] loop
  if jsonb_typeof(payload->k) is distinct from 'number' or (payload->>k)::numeric<0 or (payload->>k)::numeric>1e9 then return jsonb_build_object('error','Preencha todas as leituras com números válidos.','status',422);end if;
 end loop;
 r.engine:=(payload->>'engine')::numeric;r.elevator:=(payload->>'elevator')::numeric;r.km:=(payload->>'km')::numeric;r.start:=(payload->>'start')::numeric;r."end":=(payload->>'end')::numeric;r.liters:=(payload->>'liters')::numeric;
 if r.liters<=0 or r."end"<=r.start then return jsonb_build_object('error','Confira os litros e o registro final.','status',422);end if;
 if (rules->>'matchMeter')::boolean and abs(r."end"-r.start-r.liters)>.02 then return jsonb_build_object('error','Os litros devem corresponder à diferença do medidor.','status',422);end if;
 r.notes:=coalesce(payload->>'notes','');r.created_at:=(payload->>'createdAt')::timestamptz;
 if r.created_at is null or length(r.notes)>1000 then return jsonb_build_object('error','Horário ou observação inválida.','status',422);end if;
 -- Trava da frota serializa gravações simultâneas antes de conferir as leituras.
 select * into f from public.fleets where id=r.fleet and active for update;
 if not found then return jsonb_build_object('error','Frota indisponível. Consulte o gestor.','status',422);end if;
 select jsonb_build_object('engine',coalesce(max(engine),0),'elevator',coalesce(max(elevator),0),'km',coalesce(max(km),0)) into limits from public.records where fleet=r.fleet;
 if r.engine<(limits->>'engine')::numeric or r.elevator<(limits->>'elevator')::numeric or r.km<(limits->>'km')::numeric then return jsonb_build_object('error','Confira: KM ou horímetros estão abaixo das últimas leituras da frota.','status',422,'readings',limits);end if;
 insert into public.records(id,fleet,date,operator,user_id,engine,elevator,km,start,"end",liters,signature,notes,created_at,signature_source,submission_key) values(r.id,r.fleet,r.date,operator_name,account_id,r.engine,r.elevator,r.km,r.start,r."end",r.liters,operator_name,r.notes,r.created_at,source_name,receipt_key) on conflict(id) do nothing;
 select * into existing from public.records where id=r.id;
 if not coalesce(((source_name='account' and existing.user_id=account_id) or (source_name='declared' and existing.signature_source='declared' and existing.submission_key=receipt_key)),false) then return jsonb_build_object('error','Identificador já utilizado.','status',409);end if;
 return jsonb_build_object('id',r.id,'receivedAt',existing.received_at);
exception when invalid_text_representation or datetime_field_overflow or not_null_violation or numeric_value_out_of_range then return jsonb_build_object('error','Registro inválido. Confira todos os campos.','status',422);
end $$;

revoke all on function private.submit_record(jsonb,text,uuid,text,uuid) from public,anon,authenticated;
create or replace function private.submit(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.members;
begin
 m:=private.member();if m.email is null then return jsonb_build_object('error','Conta sem autorização. Consulte o gestor.','status',403);end if;
 return private.submit_record(payload,m.name,auth.uid(),'account',null);
end $$;
create function public.diesel_field_session() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('fleets', (select coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]'::jsonb) from (select f.*,coalesce(max(r.engine),0) last_engine,coalesce(max(r.elevator),0) last_elevator,coalesce(max(r.km),0) last_km from public.fleets f left join public.records r on r.fleet=f.id where f.active group by f.id) f), 'rules',(select value from public.settings where id='rules'));
$$;
create function public.diesel_field_submit(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare worker_name text; receipt_key uuid;
begin
 if jsonb_typeof(payload->'operator') is distinct from 'string' then return jsonb_build_object('error','Informe seu nome completo.','status',422);end if;
 worker_name:=trim(regexp_replace(payload->>'operator','[[:space:]]+',' ','g'));
 if length(worker_name) not between 2 and 120 or worker_name !~ '[[:alpha:]]' then return jsonb_build_object('error','Informe seu nome completo.','status',422);end if;
 receipt_key:=(payload->>'submissionKey')::uuid;
 if receipt_key is null then return jsonb_build_object('error','Identificação do envio inválida.','status',422);end if;
 -- Nome declarado: nunca aceita user_id ou perfil enviados pelo navegador.
 return private.submit_record(payload,worker_name,null,'declared',receipt_key);
exception when invalid_text_representation then return jsonb_build_object('error','Registro inválido. Confira os campos.','status',422);
end $$;
revoke all on function public.diesel_field_session(),public.diesel_field_submit(jsonb) from public,anon,authenticated;
grant execute on function public.diesel_field_session(),public.diesel_field_submit(jsonb) to anon,authenticated;
commit;
