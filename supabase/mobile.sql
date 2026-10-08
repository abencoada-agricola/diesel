-- Aplicar depois de field-access.sql. Registros antigos permanecem disponíveis.
begin;
create function private.default_meter_fields(fleet_type text) returns jsonb language sql immutable set search_path='' as $$
 select case fleet_type when 'Trator' then '{"km":false,"engine":true,"elevator":false}'::jsonb when 'Colhedora' then '{"km":false,"engine":true,"elevator":true}'::jsonb else '{"km":true,"engine":false,"elevator":false}'::jsonb end;
$$;
-- A validação abaixo aceita qualquer combinação não vazia das três leituras.
create function private.valid_meter_fields(fields jsonb) returns boolean language sql immutable set search_path='' as $$
 select coalesce(jsonb_typeof(fields)='object' and (fields - array['km','engine','elevator'])='{}'::jsonb and jsonb_typeof(fields->'km')='boolean' and jsonb_typeof(fields->'engine')='boolean' and jsonb_typeof(fields->'elevator')='boolean' and (fields->'km'='true'::jsonb or fields->'engine'='true'::jsonb or fields->'elevator'='true'::jsonb),false);
$$;
revoke all on function private.default_meter_fields(text),private.valid_meter_fields(jsonb) from public,anon,authenticated;
alter table public.fleets add column meter_fields jsonb;
update public.fleets set meter_fields=private.default_meter_fields(type);
alter table public.fleets alter column meter_fields set default '{"km":true,"engine":false,"elevator":false}';
alter table public.fleets alter column meter_fields set not null;
alter table public.fleets add constraint fleets_meter_fields check(private.valid_meter_fields(meter_fields));
alter table public.records alter column start drop not null;
alter table public.records alter column "end" drop not null;
alter table public.records add column capture_mode text not null default 'full' check(capture_mode in ('full','quick'));
alter table public.records add column measured_fields jsonb not null default '{"km":true,"engine":true,"elevator":true}';
alter table public.records add column previous_readings jsonb;
alter table public.records add column previous_record_id uuid references public.records(id);
alter table public.records add constraint records_capture_fields check((capture_mode='full' and start is not null and "end" is not null) or (capture_mode='quick' and start is null and "end" is null and signature_source='account'));
create or replace function private.admin_save(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.members;f jsonb;fs jsonb;count integer:=0;
begin
 m:=private.member();if m.role is distinct from 'admin' then return jsonb_build_object('error','Acesso restrito ao gestor.','status',403);end if;
 if payload->>'action' in ('fleet','import-fleets') then
  fs:=case when payload->>'action'='fleet' then jsonb_build_array(payload) else payload->'fleets' end;
  if jsonb_typeof(fs) is distinct from 'array' or jsonb_array_length(fs)>1000 then return jsonb_build_object('error','Catálogo inválido.','status',422);end if;
  for f in select * from jsonb_array_elements(fs) loop
   if coalesce(f->>'id','') !~ '^[A-Za-z0-9_.-]{1,30}$' or coalesce(length(f->>'name'),0) not between 2 and 80 or coalesce(f->>'type','') not in ('Trator','Colhedora','Caminhão','Outro') then raise exception 'Frota inválida' using errcode='22023';end if;
   insert into public.fleets(id,name,type,meter_fields) values(upper(f->>'id'),f->>'name',f->>'type',private.default_meter_fields(f->>'type')) on conflict(id) do update set name=excluded.name,type=excluded.type;count:=count+1;
  end loop;
 elsif payload->>'action'='fleet-meters' then
  if not private.valid_meter_fields(payload->'meterFields') then return jsonb_build_object('error','Escolha ao menos uma leitura para a frota.','status',422);end if;
  update public.fleets set meter_fields=payload->'meterFields' where id=upper(payload->>'id');
  if not found then return jsonb_build_object('error','Frota não encontrada.','status',404);end if;
 elsif payload->>'action'='member-username' then
  update public.members set username=lower(trim(payload->>'username')) where email=lower(payload->>'email');
  if not found then return jsonb_build_object('error','Pessoa não encontrada.','status',404);end if;
 elsif payload->>'action'='member' then
  if coalesce(payload->>'email','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or coalesce(length(payload->>'name'),0) not between 2 and 120 or coalesce(payload->>'role','') not in ('admin','operator') or lower(payload->>'email')=m.email then return jsonb_build_object('error','Nome, e-mail ou perfil inválido. Não altere seu próprio perfil.','status',422);end if;
  insert into public.members(email,name,role,username) values(lower(payload->>'email'),payload->>'name',payload->>'role',lower(trim(payload->>'username'))) on conflict(email) do update set name=excluded.name,role=excluded.role,username=excluded.username;
 elsif payload->>'action'='rules' then
  if jsonb_typeof(payload->'rules'->'matchMeter') is distinct from 'boolean' or jsonb_typeof(payload->'rules'->'futureDate') is distinct from 'boolean' then return jsonb_build_object('error','Regras inválidas.','status',422);end if;
  update public.settings set value=payload->'rules' where id='rules';
 else return jsonb_build_object('error','Ação inválida.','status',400);end if;
 return jsonb_build_object('ok',true,'count',count);
exception when unique_violation or check_violation or not_null_violation then return jsonb_build_object('error','Nome de usuário indisponível ou inválido. Use 3 a 30 letras, números, ponto, traço ou sublinhado.','status',422);
 when invalid_parameter_value then return jsonb_build_object('error','Catálogo inválido.','status',422);
end $$;


create or replace function private.session_data() returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.members;fs jsonb;
begin
 m:=private.member();if m.email is null then return jsonb_build_object('error','Conta sem autorização. Consulte o gestor.','status',403);end if;
 select coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]'::jsonb) into fs from (select f.*,count(r.id) record_count,max(r.created_at) last_record_at,coalesce(max(r.engine),0) last_engine,coalesce(max(r.elevator),0) last_elevator,coalesce(max(r.km),0) last_km from public.fleets f left join public.records r on r.fleet=f.id group by f.id) f;
 return jsonb_build_object('user',jsonb_build_object('id',auth.uid(),'email',m.email,'name',m.name,'role',m.role),'fleets',fs,'rules',(select value from public.settings where id='rules'));
end $$;

create function public.diesel_mobile_submit(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
 select jsonb_build_object('engine',coalesce(max(engine),0),'elevator',coalesce(max(elevator),0),'km',coalesce(max(km),0)) into limits from public.records where fleet=r.fleet;
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
revoke all on function public.diesel_mobile_submit(jsonb) from public,anon,authenticated;
grant execute on function public.diesel_mobile_submit(jsonb) to authenticated;
commit;
