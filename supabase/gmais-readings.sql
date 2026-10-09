begin;
alter table public.fleets add column gmais_readings jsonb;
create or replace function private.session_data_before_operations() returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.members;fs jsonb;
begin
 m:=private.member();if m.email is null then return jsonb_build_object('error','Conta sem autorização. Consulte o gestor.','status',403);end if;
 select coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]'::jsonb) into fs from (select f.*,count(r.id) record_count,max(r.created_at) last_record_at,greatest(coalesce(max(r.engine),0),coalesce((f.gmais_readings->>'engine')::numeric,0)) last_engine,greatest(coalesce(max(r.elevator),0),coalesce((f.gmais_readings->>'elevator')::numeric,0)) last_elevator,greatest(coalesce(max(r.km),0),coalesce((f.gmais_readings->>'km')::numeric,0)) last_km from public.fleets f left join public.records r on r.fleet=f.id group by f.id) f;
 return jsonb_build_object('user',jsonb_build_object('id',auth.uid(),'email',m.email,'name',m.name,'role',m.role),'fleets',fs,'rules',(select value from public.settings where id='rules'));
end $$;
create or replace function public.diesel_mobile_submit(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.members;r public.records;existing public.records;f public.fleets;limits jsonb;rules jsonb;k text;latest public.records;
begin
 m:=private.member();if m.email is null then return jsonb_build_object('error','Conta sem autorização. Consulte o gestor.','status',403);end if;
 r.id:=(payload->>'id')::uuid;r.fleet:=upper(payload->>'fleet');
 select * into existing from public.records where id=r.id;
 if found then if existing.user_id=auth.uid() and existing.capture_mode='quick' and existing.fleet=r.fleet then return jsonb_build_object('id',r.id,'duplicate',true);else return jsonb_build_object('error','Identificador já utilizado.','status',409);end if;end if;
 if jsonb_typeof(payload->'date') is distinct from 'string' or (payload->>'date') !~ '^\d{4}-\d{2}-\d{2}$' then return jsonb_build_object('error','Data inválida.','status',422);end if;
 r.date:=(payload->>'date')::date;r.created_at:=(payload->>'createdAt')::timestamptz;
 if r.created_at is null then return jsonb_build_object('error','Horário inválido.','status',422);end if;
 rules:=(select value from public.settings where id='rules');
 if not (rules->>'futureDate')::boolean and r.date>(now() at time zone 'America/Sao_Paulo')::date then return jsonb_build_object('error','A data não pode estar no futuro.','status',422);end if;
 if jsonb_typeof(payload->'liters') is distinct from 'number' or (payload->>'liters')::numeric<=0 or (payload->>'liters')::numeric>1e9 then return jsonb_build_object('error','Informe litros maiores que zero.','status',422);end if;
 r.liters:=(payload->>'liters')::numeric;
 select * into f from public.fleets where id=r.fleet and active for update;
 if not found then return jsonb_build_object('error','Frota indisponível. Consulte o gestor.','status',422);end if;
 select jsonb_build_object('engine',greatest(coalesce(max(engine),0),coalesce((f.gmais_readings->>'engine')::numeric,0)),'elevator',greatest(coalesce(max(elevator),0),coalesce((f.gmais_readings->>'elevator')::numeric,0)),'km',greatest(coalesce(max(km),0),coalesce((f.gmais_readings->>'km')::numeric,0))) into limits from public.records where fleet=r.fleet;
 if payload->'measuredFields' is distinct from f.meter_fields then return jsonb_build_object('error','As leituras exigidas para esta frota mudaram. Confira antes de reenviar.','status',422,'meterFields',f.meter_fields,'readings',limits);end if;
 foreach k in array array['engine','elevator','km'] loop
  if (f.meter_fields->>k)::boolean then
   if jsonb_typeof(payload->k) is distinct from 'number' or (payload->>k)::numeric<0 or (payload->>k)::numeric>1e9 then return jsonb_build_object('error','Preencha todas as leituras indicadas para a frota.','status',422);end if;
   if (payload->>k)::numeric<(limits->>k)::numeric then return jsonb_build_object('error','Confira: a leitura está abaixo do último registro da frota.','status',422,'readings',limits);end if;
  end if;
 end loop;
 r.engine:=case when (f.meter_fields->>'engine')::boolean then (payload->>'engine')::numeric else (limits->>'engine')::numeric end;
 r.elevator:=case when (f.meter_fields->>'elevator')::boolean then (payload->>'elevator')::numeric else (limits->>'elevator')::numeric end;
 r.km:=case when (f.meter_fields->>'km')::boolean then (payload->>'km')::numeric else (limits->>'km')::numeric end;
 select * into latest from public.records where fleet=r.fleet order by received_at desc,id desc limit 1;
 insert into public.records(id,fleet,date,operator,user_id,engine,elevator,km,start,"end",liters,signature,created_at,signature_source,capture_mode,measured_fields,previous_readings,previous_record_id)
 values(r.id,r.fleet,r.date,m.name,auth.uid(),r.engine,r.elevator,r.km,null,null,r.liters,m.name,r.created_at,'account','quick',f.meter_fields,limits||jsonb_build_object('recordedAt',latest.created_at),latest.id) on conflict(id) do nothing;
 select * into existing from public.records where id=r.id;
 if not coalesce(existing.user_id=auth.uid() and existing.capture_mode='quick' and existing.fleet=r.fleet,false) then return jsonb_build_object('error','Identificador já utilizado.','status',409);end if;
 return jsonb_build_object('id',r.id,'receivedAt',existing.received_at,'previous',existing.previous_readings);
exception when invalid_text_representation or datetime_field_overflow or not_null_violation or numeric_value_out_of_range then return jsonb_build_object('error','Registro inválido. Confira os campos.','status',422);
end $$;
create or replace function private.submit_record(payload jsonb,operator_name text,account_id uuid,source_name text,receipt_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
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
 select jsonb_build_object('engine',greatest(coalesce(max(engine),0),coalesce((f.gmais_readings->>'engine')::numeric,0)),'elevator',greatest(coalesce(max(elevator),0),coalesce((f.gmais_readings->>'elevator')::numeric,0)),'km',greatest(coalesce(max(km),0),coalesce((f.gmais_readings->>'km')::numeric,0))) into limits from public.records where fleet=r.fleet;
 if r.engine<(limits->>'engine')::numeric or r.elevator<(limits->>'elevator')::numeric or r.km<(limits->>'km')::numeric then return jsonb_build_object('error','Confira: KM ou horímetros estão abaixo das últimas leituras da frota.','status',422,'readings',limits);end if;
 insert into public.records(id,fleet,date,operator,user_id,engine,elevator,km,start,"end",liters,signature,notes,created_at,signature_source,submission_key) values(r.id,r.fleet,r.date,operator_name,account_id,r.engine,r.elevator,r.km,r.start,r."end",r.liters,operator_name,r.notes,r.created_at,source_name,receipt_key) on conflict(id) do nothing;
 select * into existing from public.records where id=r.id;
 if not coalesce(((source_name='account' and existing.user_id=account_id) or (source_name='declared' and existing.signature_source='declared' and existing.submission_key=receipt_key)),false) then return jsonb_build_object('error','Identificador já utilizado.','status',409);end if;
 return jsonb_build_object('id',r.id,'receivedAt',existing.received_at);
exception when invalid_text_representation or datetime_field_overflow or not_null_violation or numeric_value_out_of_range then return jsonb_build_object('error','Registro inválido. Confira todos os campos.','status',422);
end $$;
create or replace function public.diesel_field_session() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('fleets', (select coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]'::jsonb) from (select f.*,greatest(coalesce(max(r.engine),0),coalesce((f.gmais_readings->>'engine')::numeric,0)) last_engine,greatest(coalesce(max(r.elevator),0),coalesce((f.gmais_readings->>'elevator')::numeric,0)) last_elevator,greatest(coalesce(max(r.km),0),coalesce((f.gmais_readings->>'km')::numeric,0)) last_km from public.fleets f left join public.records r on r.fleet=f.id where f.active group by f.id) f), 'rules',(select value from public.settings where id='rules'));
$$;
commit;
