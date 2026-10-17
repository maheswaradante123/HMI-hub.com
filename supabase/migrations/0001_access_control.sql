-- HMI Internal System - Phase 3: Authentication & Authorization
-- Tabel akses (RBAC), fungsi has_permission, RLS, dan audit trail dasar.
-- Tidak ada kebijakan DELETE pada data akses utama: dinonaktifkan, bukan dihapus.

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.departments (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.roles (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique check (code = upper(code)),
  name          text not null,
  description   text,
  is_superuser  boolean not null default false,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table public.permissions (
  id      uuid primary key default gen_random_uuid(),
  module  text not null,
  action  text not null check (action in ('view','create','edit','delete','approve','export')),
  unique (module, action)
);

create table public.role_permissions (
  role_id        uuid not null references public.roles(id),
  permission_id  uuid not null references public.permissions(id),
  created_at     timestamptz not null default now(),
  primary key (role_id, permission_id)
);

create table public.user_profiles (
  id             uuid primary key references auth.users(id),
  full_name      text not null,
  department_id  uuid references public.departments(id),
  role_id        uuid not null references public.roles(id),
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index user_profiles_role_id_idx on public.user_profiles(role_id);
create index user_profiles_department_id_idx on public.user_profiles(department_id);

create table public.user_permission_overrides (
  user_id        uuid not null references public.user_profiles(id),
  permission_id  uuid not null references public.permissions(id),
  is_granted     boolean not null,
  created_at     timestamptz not null default now(),
  primary key (user_id, permission_id)
);

create table public.audit_logs (
  id          bigint generated always as identity primary key,
  table_name  text not null,
  record_id   text not null,
  action      text not null check (action in ('INSERT','UPDATE','DELETE')),
  old_values  jsonb,
  new_values  jsonb,
  user_id     uuid,
  created_at  timestamptz not null default now()
);
create index audit_logs_table_record_idx on public.audit_logs(table_name, record_id);
create index audit_logs_created_at_idx on public.audit_logs(created_at);

create trigger departments_updated_at before update on public.departments
  for each row execute function public.set_updated_at();
create trigger roles_updated_at before update on public.roles
  for each row execute function public.set_updated_at();
create trigger user_profiles_updated_at before update on public.user_profiles
  for each row execute function public.set_updated_at();

-- Urutan keputusan: user nonaktif/tanpa profil -> tolak; override user;
-- role superuser -> izinkan; izin dari role.
create or replace function public.has_permission(p_module text, p_action text)
returns boolean
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_role_id    uuid;
  v_superuser  boolean;
  v_role_on    boolean;
  v_user_on    boolean;
  v_perm_id    uuid;
  v_override   boolean;
begin
  if v_uid is null then
    return false;
  end if;

  select r.id, r.is_superuser, r.is_active, p.is_active
    into v_role_id, v_superuser, v_role_on, v_user_on
    from public.user_profiles p
    join public.roles r on r.id = p.role_id
   where p.id = v_uid;

  if not found or not v_user_on or not v_role_on then
    return false;
  end if;

  select id into v_perm_id
    from public.permissions
   where module = p_module and action = p_action;

  if v_perm_id is not null then
    select o.is_granted into v_override
      from public.user_permission_overrides o
     where o.user_id = v_uid and o.permission_id = v_perm_id;
    if found then
      return v_override;
    end if;
  end if;

  if v_superuser then
    return true;
  end if;

  if v_perm_id is null then
    return false;
  end if;

  return exists (
    select 1 from public.role_permissions rp
     where rp.role_id = v_role_id and rp.permission_id = v_perm_id
  );
end;
$$;

create or replace function public.my_permissions()
returns table (module text, action text)
language plpgsql stable security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return;
  end if;
  return query
    select p.module, p.action
      from public.permissions p
     where public.has_permission(p.module, p.action);
end;
$$;

revoke all on function public.has_permission(text, text) from public, anon;
revoke all on function public.my_permissions() from public, anon;
grant execute on function public.has_permission(text, text) to authenticated;
grant execute on function public.my_permissions() to authenticated;

create or replace function public.audit_row_change()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_record_id text;
begin
  if tg_op = 'DELETE' then
    v_record_id := coalesce(to_jsonb(old)->>'id', to_jsonb(old)::text);
    insert into public.audit_logs(table_name, record_id, action, old_values, user_id)
    values (tg_table_name, v_record_id, tg_op, to_jsonb(old), auth.uid());
    return old;
  elsif tg_op = 'UPDATE' then
    v_record_id := coalesce(to_jsonb(new)->>'id', to_jsonb(new)::text);
    insert into public.audit_logs(table_name, record_id, action, old_values, new_values, user_id)
    values (tg_table_name, v_record_id, tg_op, to_jsonb(old), to_jsonb(new), auth.uid());
    return new;
  else
    v_record_id := coalesce(to_jsonb(new)->>'id', to_jsonb(new)::text);
    insert into public.audit_logs(table_name, record_id, action, new_values, user_id)
    values (tg_table_name, v_record_id, tg_op, to_jsonb(new), auth.uid());
    return new;
  end if;
end;
$$;

create or replace function public.block_audit_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'audit_logs tidak boleh diubah atau dihapus';
end;
$$;

create trigger audit_logs_no_update before update or delete on public.audit_logs
  for each row execute function public.block_audit_mutation();

create trigger audit_roles after insert or update or delete on public.roles
  for each row execute function public.audit_row_change();
create trigger audit_role_permissions after insert or update or delete on public.role_permissions
  for each row execute function public.audit_row_change();
create trigger audit_user_profiles after insert or update or delete on public.user_profiles
  for each row execute function public.audit_row_change();
create trigger audit_user_permission_overrides after insert or update or delete on public.user_permission_overrides
  for each row execute function public.audit_row_change();

alter table public.departments               enable row level security;
alter table public.roles                     enable row level security;
alter table public.permissions               enable row level security;
alter table public.role_permissions          enable row level security;
alter table public.user_profiles             enable row level security;
alter table public.user_permission_overrides enable row level security;
alter table public.audit_logs                enable row level security;

create policy departments_select on public.departments
  for select to authenticated using (true);
create policy departments_insert on public.departments
  for insert to authenticated with check (public.has_permission('master_data','create'));
create policy departments_update on public.departments
  for update to authenticated
  using (public.has_permission('master_data','edit'))
  with check (public.has_permission('master_data','edit'));

create policy roles_select on public.roles
  for select to authenticated using (true);
create policy roles_insert on public.roles
  for insert to authenticated with check (public.has_permission('role','create'));
create policy roles_update on public.roles
  for update to authenticated
  using (public.has_permission('role','edit'))
  with check (public.has_permission('role','edit'));

create policy permissions_select on public.permissions
  for select to authenticated using (true);

create policy role_permissions_select on public.role_permissions
  for select to authenticated using (true);
create policy role_permissions_insert on public.role_permissions
  for insert to authenticated with check (public.has_permission('role','edit'));
create policy role_permissions_delete on public.role_permissions
  for delete to authenticated using (public.has_permission('role','edit'));

create policy user_profiles_select on public.user_profiles
  for select to authenticated
  using (id = auth.uid() or public.has_permission('user','view'));
create policy user_profiles_insert on public.user_profiles
  for insert to authenticated with check (public.has_permission('user','create'));
create policy user_profiles_update on public.user_profiles
  for update to authenticated
  using (public.has_permission('user','edit'))
  with check (public.has_permission('user','edit'));

create policy user_permission_overrides_select on public.user_permission_overrides
  for select to authenticated
  using (user_id = auth.uid() or public.has_permission('user','view'));
create policy user_permission_overrides_insert on public.user_permission_overrides
  for insert to authenticated with check (public.has_permission('user','edit'));
create policy user_permission_overrides_update on public.user_permission_overrides
  for update to authenticated
  using (public.has_permission('user','edit'))
  with check (public.has_permission('user','edit'));
create policy user_permission_overrides_delete on public.user_permission_overrides
  for delete to authenticated using (public.has_permission('user','edit'));

create policy audit_logs_select on public.audit_logs
  for select to authenticated using (public.has_permission('audit_log','view'));

revoke all on all tables in schema public from anon;
grant select, insert, update on public.departments, public.roles, public.user_profiles to authenticated;
grant select on public.permissions, public.audit_logs to authenticated;
grant select, insert, delete on public.role_permissions to authenticated;
grant select, insert, update, delete on public.user_permission_overrides to authenticated;
