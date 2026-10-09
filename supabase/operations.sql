begin;
create table public.diesel_materials(material_code text primary key check(material_code ~ '^[0-9]{1,30}$'),material_name text not null);
alter table public.diesel_materials enable row level security;
revoke all on public.diesel_materials from anon,authenticated;
create table public.diesel_locations(local_code text not null check(local_code ~ '^[0-9]{1,30}$'),material_code text not null check(material_code ~ '^[0-9]{1,30}$'),name text not null default '',material_name text not null default '',last_meter numeric check(last_meter between 0 and 1e9),updated_at timestamptz not null default now(),primary key(local_code,material_code));
create table public.diesel_operations(id uuid primary key,user_id uuid not null,operator text not null,kind text not null check(kind in ('transfer','occurrence')),local_code text not null,material_code text not null,destination text,notes text,created_at timestamptz not null,received_at timestamptz not null default now());
alter table public.diesel_locations enable row level security;
alter table public.diesel_operations enable row level security;
revoke all on public.diesel_locations,public.diesel_operations from anon,authenticated;
alter table public.records add column local_code text;
alter table public.records add column material_code text;
alter table public.records add column recorder_start numeric;
alter table public.records add column recorder_end numeric;
alter function private.session_data() rename to session_data_before_operations;
create function private.session_data() returns jsonb language sql stable security definer set search_path='' as $$
 select case when private.member() is null then private.session_data_before_operations() else private.session_data_before_operations() || jsonb_build_object('materials',(select coalesce(jsonb_agg(to_jsonb(m)),'[]'::jsonb) from public.diesel_materials m),'locations',(select coalesce(jsonb_agg(to_jsonb(l)),'[]'::jsonb) from public.diesel_locations l)) end;
$$;
create function public.diesel_operation_submit(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.members;r jsonb;previous public.records;existing public.diesel_operations;loc public.diesel_locations;lid text;mat text;start_value numeric;end_value numeric;kind text;rid uuid;
begin
 m:=private.member();if m.email is null then return jsonb_build_object('error','Conta sem autorização.','status',403);end if;
 rid:=(payload->>'id')::uuid;kind:=payload->>'kind';lid:=payload->>'localCode';mat:=payload->>'materialCode';
 if lid is null or lid !~ '^[0-9]{1,30}$' or mat is null or mat !~ '^[0-9]{1,30}$' then return jsonb_build_object('error','Informe códigos numéricos de local e material.','status',422);end if;
 if (payload->>'createdAt')::timestamptz is null or (payload->>'createdAt')::timestamptz>now()+interval '5 minutes' then return jsonb_build_object('error','Confira a data e hora do aparelho.','status',422);end if;
 -- Serialize both local-meter and UUID writes, including retries from the background worker.
 perform pg_advisory_xact_lock(hashtextextended(rid::text,0));
 if kind='refuel' then
  select * into previous from public.records where id=rid;
  if found then if previous.user_id=auth.uid() and previous.fleet=upper(payload->>'fleet') then return jsonb_build_object('id',rid,'duplicate',true);else return jsonb_build_object('error','Identificador já utilizado.','status',409);end if;end if;
  if exists(select 1 from public.diesel_operations where id=rid) then return jsonb_build_object('error','Identificador já utilizado.','status',409);end if;
  insert into public.diesel_locations(local_code,material_code) values(lid,mat) on conflict do nothing;
  select * into loc from public.diesel_locations where local_code=lid and material_code=mat for update;
  if payload->>'mode'='recorder' then
   if jsonb_typeof(payload->'recorderStart') is distinct from 'number' or jsonb_typeof(payload->'recorderEnd') is distinct from 'number' then return jsonb_build_object('error','Informe a leitura da registradora.','status',422);end if;
   start_value:=(payload->>'recorderStart')::numeric;end_value:=(payload->>'recorderEnd')::numeric;
   if loc.last_meter is null or start_value<>loc.last_meter then return jsonb_build_object('error','A registradora foi atualizada ou precisa de leitura inicial. Confira com o gestor.','status',409,'recorder',loc.last_meter);end if;
   if end_value<=start_value or end_value>1e9 or abs(end_value-start_value-(payload->>'liters')::numeric)>0.02 then return jsonb_build_object('error','Confira o final da registradora e os litros calculados.','status',422);end if;
  elsif payload->>'mode' is distinct from 'manual' then return jsonb_build_object('error','Modo de abastecimento inválido.','status',422);end if;
  r:=public.diesel_mobile_submit(payload);if r ? 'error' then return r;end if;
  update public.records set local_code=lid,material_code=mat,recorder_start=start_value,recorder_end=end_value where id=rid;
  -- Manual liters do not establish a physical meter reading. Require a verified baseline again.
  update public.diesel_locations set last_meter=end_value,updated_at=now() where local_code=lid and material_code=mat;
  return r;
 elsif kind in ('transfer','occurrence') then
  if exists(select 1 from public.records where id=rid) then return jsonb_build_object('error','Identificador já utilizado.','status',409);end if;
  select * into existing from public.diesel_operations where id=rid;
  if found then if existing.user_id=auth.uid() and existing.kind=kind then return jsonb_build_object('id',rid,'duplicate',true);else return jsonb_build_object('error','Identificador já utilizado.','status',409);end if;end if;
  if kind='transfer' and (coalesce(payload->>'destination','') !~ '^[0-9]{1,30}$' or payload->>'destination'=lid) then return jsonb_build_object('error','Informe um novo local válido.','status',422);end if;
  if kind='occurrence' and coalesce(length(trim(payload->>'notes')),0) not between 3 and 2000 then return jsonb_build_object('error','Descreva a ocorrência com 3 a 2000 caracteres.','status',422);end if;
  insert into public.diesel_operations(id,user_id,operator,kind,local_code,material_code,destination,notes,created_at) values(rid,auth.uid(),m.name,kind,lid,mat,case when kind='transfer' then payload->>'destination' end,case when kind='occurrence' then trim(payload->>'notes') end,(payload->>'createdAt')::timestamptz);
  return jsonb_build_object('id',rid,'receivedAt',now());
 end if;
 return jsonb_build_object('error','Operação inválida.','status',422);
exception when invalid_text_representation or datetime_field_overflow or not_null_violation or numeric_value_out_of_range or check_violation then return jsonb_build_object('error','Dados inválidos. Confira o preenchimento.','status',422);
end $$;
create function public.diesel_operations_admin(payload jsonb default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.members;
begin
 m:=private.member();if m.role is distinct from 'admin' then return jsonb_build_object('error','Acesso restrito ao gestor.','status',403);end if;
 if payload is not null and payload<>'null'::jsonb then
  if payload->>'action'='location' then
   if jsonb_typeof(payload->'lastMeter') is distinct from 'number' then return jsonb_build_object('error','Informe a leitura verificada da registradora.','status',422);end if;
   insert into public.diesel_locations(local_code,material_code,name,material_name,last_meter) values(payload->>'localCode',payload->>'materialCode',left(coalesce(payload->>'name',''),120),left(coalesce(payload->>'materialName',''),120),(payload->>'lastMeter')::numeric) on conflict(local_code,material_code) do update set name=excluded.name,material_name=excluded.material_name,last_meter=excluded.last_meter,updated_at=now();
  else return jsonb_build_object('error','Operação inválida.','status',422);end if;
 end if;
 return jsonb_build_object('locations',(select coalesce(jsonb_agg(to_jsonb(l) order by local_code,material_code),'[]'::jsonb) from public.diesel_locations l),'operations',(select coalesce(jsonb_agg(to_jsonb(o) order by received_at desc),'[]'::jsonb) from (select * from public.diesel_operations order by received_at desc limit 1000)o));
exception when check_violation or invalid_text_representation or not_null_violation then return jsonb_build_object('error','Confira os códigos e a leitura.','status',422);
end $$;
revoke all on function private.session_data(),private.session_data_before_operations() from public,anon,authenticated;
grant execute on function private.session_data() to authenticated;
revoke all on function public.diesel_operation_submit(jsonb),public.diesel_operations_admin(jsonb) from public,anon,authenticated;
grant execute on function public.diesel_operation_submit(jsonb),public.diesel_operations_admin(jsonb) to authenticated;
commit;
