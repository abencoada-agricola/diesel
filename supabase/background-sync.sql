begin;
create table private.diesel_devices(user_id uuid not null,device_id uuid not null,email text not null,token_hash bytea not null unique,expires_at timestamptz not null,primary key(user_id,device_id));
alter table private.diesel_devices enable row level security;
revoke all on private.diesel_devices from public,anon,authenticated;
create function public.diesel_device_register(device_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.members;token text;
begin
 m:=private.member();if m.email is null or device_id is null then return jsonb_build_object('error','Conta sem autorização.','status',403);end if;
 token:=gen_random_uuid()::text||gen_random_uuid()::text;
 insert into private.diesel_devices(user_id,device_id,email,token_hash,expires_at) values(auth.uid(),device_id,m.email,sha256(convert_to(token,'UTF8')),now()+interval '90 days') on conflict on constraint diesel_devices_pkey do update set email=excluded.email,token_hash=excluded.token_hash,expires_at=excluded.expires_at;
 return jsonb_build_object('token',token,'expiresAt',now()+interval '90 days');
end $$;
create function public.diesel_device_submit(device_token text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d private.diesel_devices;claims text;result jsonb;
begin
 select * into d from private.diesel_devices where token_hash=sha256(convert_to(device_token,'UTF8')) and expires_at>now();
 if not found or not exists(select 1 from public.members where email=d.email) then return jsonb_build_object('error','Entre novamente para renovar o envio automático.','status',403);end if;
 claims:=current_setting('request.jwt.claims',true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',d.user_id,'email',d.email,'role','authenticated')::text,true);
 if payload ? 'kind' then result:=public.diesel_operation_submit(payload);else result:=public.diesel_mobile_submit(payload);end if;
 perform set_config('request.jwt.claims',coalesce(claims,''),true);
 return result;
end $$;
revoke all on function public.diesel_device_register(uuid),public.diesel_device_submit(text,jsonb) from public,anon,authenticated;
grant execute on function public.diesel_device_register(uuid) to authenticated;
grant execute on function public.diesel_device_submit(text,jsonb) to anon,authenticated;
commit;
