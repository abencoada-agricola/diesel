-- Executar como proprietário do banco no SQL Editor.
create schema if not exists private;
create table public.members(email text primary key check(email=lower(email)), name text not null check(length(name) between 2 and 120), role text not null check(role in ('admin','operator')));
create table public.fleets(id text primary key, name text not null, type text not null, active boolean not null default true);
create table public.settings(id text primary key, value jsonb not null);
insert into public.settings values('rules','{"futureDate":false,"matchMeter":false}');
create table public.records(id uuid primary key,fleet text not null references public.fleets(id),date date not null,operator text not null,user_id uuid not null references auth.users(id),engine numeric not null check(engine between 0 and 1e9),elevator numeric not null check(elevator between 0 and 1e9),km numeric not null check(km between 0 and 1e9),start numeric not null check(start between 0 and 1e9),"end" numeric not null check("end">start and "end"<=1e9),liters numeric not null check(liters>0 and liters<=1e9),signature text not null,notes text not null default '' check(length(notes)<=1000),created_at timestamptz not null,received_at timestamptz not null default now());
create index records_fleet on public.records(fleet);
create index records_user on public.records(user_id);
alter table public.members enable row level security;
alter table public.fleets enable row level security;
alter table public.settings enable row level security;
alter table public.records enable row level security;
revoke all on public.members,public.fleets,public.settings,public.records from anon,authenticated;
-- A aplicação usa somente funções com identidade conferida, sem acesso direto às tabelas.
create function private.member() returns public.members language sql stable security definer set search_path='' as $$
 select m from public.members m where auth.uid() is not null and m.email=lower(auth.jwt()->>'email');
$$;
create function private.session_data() returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.members;fs jsonb;
begin
 m:=private.member();if m.email is null then return jsonb_build_object('error','Conta sem autorização. Consulte o gestor.','status',403);end if;
 select coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]'::jsonb) into fs from (select f.*,coalesce(max(r.engine),0) last_engine,coalesce(max(r.elevator),0) last_elevator,coalesce(max(r.km),0) last_km from public.fleets f left join public.records r on r.fleet=f.id group by f.id) f;
 return jsonb_build_object('user',jsonb_build_object('id',auth.uid(),'email',m.email,'name',m.name,'role',m.role),'fleets',fs,'rules',(select value from public.settings where id='rules'));
end $$;
create function private.read_records(record_id text) returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.members;rs jsonb;
begin
 m:=private.member();if m.email is null then return jsonb_build_object('error','Acesso não autorizado.','status',403);end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.received_at desc),'[]'::jsonb) into rs from public.records r where (m.role='admin' or r.user_id=auth.uid()) and (record_id is null or r.id::text=record_id);
 if record_id is not null then if jsonb_array_length(rs)=0 then return jsonb_build_object('error','Registro não encontrado.','status',404);end if;return rs->0;end if;
 return jsonb_build_object('records',rs);
end $$;
create function private.submit(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.members;existing public.records;r public.records;f public.fleets;limits jsonb;rules jsonb;k text;
begin
 m:=private.member();if m.email is null then return jsonb_build_object('error','Conta sem autorização.','status',403);end if;
 r.id:=(payload->>'id')::uuid;
 select * into existing from public.records where id=r.id;
 if found then if existing.user_id=auth.uid() then return jsonb_build_object('id',r.id,'duplicate',true);else return jsonb_build_object('error','Identificador já utilizado.','status',409);end if;end if;
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
 insert into public.records(id,fleet,date,operator,user_id,engine,elevator,km,start,"end",liters,signature,notes,created_at) values(r.id,r.fleet,r.date,m.name,auth.uid(),r.engine,r.elevator,r.km,r.start,r."end",r.liters,m.name,r.notes,r.created_at) on conflict(id) do nothing;
 select * into existing from public.records where id=r.id;
 if existing.user_id<>auth.uid() then return jsonb_build_object('error','Identificador já utilizado.','status',409);end if;
 return jsonb_build_object('id',r.id,'receivedAt',existing.received_at);
exception when invalid_text_representation or datetime_field_overflow or not_null_violation or numeric_value_out_of_range then return jsonb_build_object('error','Registro inválido. Confira todos os campos.','status',422);
end $$;
create function private.admin_data() returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.members;
begin
 m:=private.member();if m.role is distinct from 'admin' then return jsonb_build_object('error','Acesso restrito ao gestor.','status',403);end if;
 return jsonb_build_object('members',(select coalesce(jsonb_agg(to_jsonb(v) order by v.name),'[]'::jsonb) from public.members v),'rules',(select value from public.settings where id='rules'));
end $$;
create function private.admin_save(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.members;f jsonb;fs jsonb;count integer:=0;
begin
 m:=private.member();if m.role is distinct from 'admin' then return jsonb_build_object('error','Acesso restrito ao gestor.','status',403);end if;
 if payload->>'action' in ('fleet','import-fleets') then
  fs:=case when payload->>'action'='fleet' then jsonb_build_array(payload) else payload->'fleets' end;
  if jsonb_typeof(fs) is distinct from 'array' or jsonb_array_length(fs)>1000 then return jsonb_build_object('error','Catálogo inválido.','status',422);end if;
  for f in select * from jsonb_array_elements(fs) loop
   if coalesce(f->>'id','') !~ '^[A-Za-z0-9_.-]{1,30}$' or coalesce(length(f->>'name'),0) not between 2 and 80 or coalesce(f->>'type','') not in ('Trator','Colhedora','Caminhão','Outro') then raise exception 'Frota inválida' using errcode='22023';end if;
   insert into public.fleets(id,name,type) values(upper(f->>'id'),f->>'name',f->>'type') on conflict(id) do update set name=excluded.name,type=excluded.type;count:=count+1;
  end loop;
 elsif payload->>'action'='member' then
  if coalesce(payload->>'email','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or coalesce(length(payload->>'name'),0) not between 2 and 120 or coalesce(payload->>'role','') not in ('admin','operator') or lower(payload->>'email')=m.email then return jsonb_build_object('error','Nome, e-mail ou perfil inválido. Não altere seu próprio perfil.','status',422);end if;
  insert into public.members(email,name,role) values(lower(payload->>'email'),payload->>'name',payload->>'role') on conflict(email) do update set name=excluded.name,role=excluded.role;
 elsif payload->>'action'='rules' then
  if jsonb_typeof(payload->'rules'->'matchMeter') is distinct from 'boolean' or jsonb_typeof(payload->'rules'->'futureDate') is distinct from 'boolean' then return jsonb_build_object('error','Regras inválidas.','status',422);end if;
  update public.settings set value=payload->'rules' where id='rules';
 else return jsonb_build_object('error','Ação inválida.','status',400);end if;
 return jsonb_build_object('ok',true,'count',count);
exception when invalid_parameter_value then return jsonb_build_object('error','Catálogo inválido.','status',422);
end $$;
create function public.diesel_session() returns jsonb language sql security invoker set search_path='' as $$select private.session_data()$$;
create function public.diesel_records(record_id text default null) returns jsonb language sql security invoker set search_path='' as $$select private.read_records(record_id)$$;
create function public.diesel_submit(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.submit(payload)$$;
create function public.diesel_admin() returns jsonb language sql security invoker set search_path='' as $$select private.admin_data()$$;
create function public.diesel_admin_save(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.admin_save(payload)$$;
revoke all on all functions in schema private from public,anon,authenticated;
grant usage on schema private to authenticated;
grant execute on all functions in schema private to authenticated;
revoke all on function public.diesel_session(),public.diesel_records(text),public.diesel_submit(jsonb),public.diesel_admin(),public.diesel_admin_save(jsonb) from public,anon,authenticated;
grant execute on function public.diesel_session(),public.diesel_records(text),public.diesel_submit(jsonb),public.diesel_admin(),public.diesel_admin_save(jsonb) to authenticated;
