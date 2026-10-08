-- Aplicar depois do schema.sql. Não modifica senhas nem identidades do Supabase.
begin;
alter table public.members add column username text;
with names as (
 select email, left(coalesce(nullif(regexp_replace(lower(split_part(email,'@',1)), '[^a-z0-9_.-]', '', 'g'),''),'usuario'),20) stem,
 row_number() over(order by email) n from public.members
)
update public.members m set username=case when length(names.stem)<3 then 'usuario'||names.n else names.stem end from names where m.email=names.email;
-- Resolve colisões de prefixo sem vincular duas contas ao mesmo usuário.
with duplicates as (select email,username,row_number() over(partition by username order by email) n from public.members)
update public.members m set username=left(d.username,20)||'_'||substr(md5(m.email),1,8) from duplicates d where m.email=d.email and d.n>1;
alter table public.members alter column username set not null;
alter table public.members add constraint members_username_valid check(username ~ '^[a-z0-9][a-z0-9_.-]{2,29}$');
alter table public.members add constraint members_username_unique unique(username);
create or replace function private.admin_save(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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

-- O tradutor de usuário fica restrito ao servidor: visitantes não recebem e-mails.
create table private.login_attempts(bucket text primary key,window_start timestamptz not null,attempts integer not null);
alter table private.login_attempts enable row level security;
revoke all on private.login_attempts from public,anon,authenticated;
create function public.diesel_login_target(login_name text,request_ip text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare bucket_name text; n integer;limit_count integer; target text;
begin
 if login_name is null or login_name !~ '^[a-z0-9][a-z0-9_.-]{2,29}$' then return jsonb_build_object('status',401);end if;
 -- Conta por IP e por usuário; transação torna o limite efetivo entre instâncias.
 foreach bucket_name in array array['ip:'||md5(coalesce(request_ip,'unknown')), 'user:'||md5(login_name)] loop
  limit_count:=case when bucket_name like 'ip:%' then 60 else 10 end;
  insert into private.login_attempts values(bucket_name,now(),1)
  on conflict(bucket) do update set window_start=case when private.login_attempts.window_start<now()-interval '5 minutes' then now() else private.login_attempts.window_start end,
  attempts=case when private.login_attempts.window_start<now()-interval '5 minutes' then 1 else private.login_attempts.attempts+1 end returning attempts into n;
  if n>limit_count then return jsonb_build_object('status',429);end if;
 end loop;
 delete from private.login_attempts where window_start<now()-interval '1 day';
 select email into target from public.members where username=login_name;
 return jsonb_build_object('email',target,'status',200);
end $$;
revoke all on function public.diesel_login_target(text,text) from public,anon,authenticated;
grant execute on function public.diesel_login_target(text,text) to service_role;
commit;
