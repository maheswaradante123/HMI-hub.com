-- ===== 0001_access_control.sql =====
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


-- ===== 0002_master_data.sql =====
-- HMI Internal System - Phase 4: Master Data
-- Tidak ada DELETE: data master dinonaktifkan (is_active = false).
-- Perubahan tercatat di audit_logs lewat trigger dari 0001.

create or replace function public.set_actor_columns()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, auth.uid());
    new.updated_by := auth.uid();
  else
    new.created_by := old.created_by;
    new.created_at := old.created_at;
    new.updated_by := auth.uid();
    new.updated_at := now();
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------
-- Master sederhana (kode + nama)
-- ---------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'product_categories','units','cow_types','non_carcass_types',
    'cost_types','payment_methods','warehouses'
  ] loop
    execute format($f$
      create table public.%I (
        id         uuid primary key default gen_random_uuid(),
        code       text not null,
        name       text not null,
        is_active  boolean not null default true,
        created_at timestamptz not null default now(),
        created_by uuid references auth.users(id),
        updated_at timestamptz not null default now(),
        updated_by uuid references auth.users(id),
        constraint %I check (code = upper(code) and btrim(code) <> '' and btrim(name) <> '')
      )$f$, t, t || '_text_chk');
    execute format('create unique index %I on public.%I (code)', t || '_code_uq', t);
    execute format('create unique index %I on public.%I (lower(name))', t || '_name_uq', t);
  end loop;
end $$;

create table public.locations (
  id           uuid primary key default gen_random_uuid(),
  warehouse_id uuid references public.warehouses(id),
  code         text not null,
  name         text not null,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  created_by   uuid references auth.users(id),
  updated_at   timestamptz not null default now(),
  updated_by   uuid references auth.users(id),
  constraint locations_text_chk check (code = upper(code) and btrim(code) <> '' and btrim(name) <> '')
);
create unique index locations_code_uq on public.locations (code);
create index locations_warehouse_idx on public.locations (warehouse_id);

create table public.accounts (
  id          uuid primary key default gen_random_uuid(),
  code        text not null,
  name        text not null,
  type        text not null check (type in ('BANK','CASH')),
  account_ref text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  created_by  uuid references auth.users(id),
  updated_at  timestamptz not null default now(),
  updated_by  uuid references auth.users(id),
  constraint accounts_text_chk check (code = upper(code) and btrim(code) <> '' and btrim(name) <> '')
);
create unique index accounts_code_uq on public.accounts (code);
create unique index accounts_name_uq on public.accounts (lower(name));

-- ---------------------------------------------------------------
-- Customer, supplier, produk
-- ---------------------------------------------------------------
create table public.customers (
  id                uuid primary key default gen_random_uuid(),
  code              text not null,
  name              text not null,
  type              text not null check (type in ('HOREKA','NON_CARCASS_BUYER','OTHER')),
  address           text,
  contact_name      text,
  phone             text,
  payment_term_days integer not null default 0 check (payment_term_days >= 0),
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  created_by        uuid references auth.users(id),
  updated_at        timestamptz not null default now(),
  updated_by        uuid references auth.users(id),
  constraint customers_text_chk check (code = upper(code) and btrim(code) <> '' and btrim(name) <> '')
);
create unique index customers_code_uq on public.customers (code);
create unique index customers_name_uq on public.customers (lower(name));

create table public.suppliers (
  id           uuid primary key default gen_random_uuid(),
  code         text not null,
  name         text not null,
  type         text not null check (type in ('COW','RESELLER','SUPPORTING','OTHER')),
  address      text,
  contact_name text,
  phone        text,
  bank_info    text,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  created_by   uuid references auth.users(id),
  updated_at   timestamptz not null default now(),
  updated_by   uuid references auth.users(id),
  constraint suppliers_text_chk check (code = upper(code) and btrim(code) <> '' and btrim(name) <> '')
);
create unique index suppliers_code_uq on public.suppliers (code);
create unique index suppliers_name_uq on public.suppliers (lower(name));

create table public.products (
  id          uuid primary key default gen_random_uuid(),
  code        text not null,
  name        text not null,
  product_type text not null check (product_type in ('MANUFACTURE','RESELLER','SUPPORTING')),
  category_id uuid references public.product_categories(id),
  unit_id     uuid not null references public.units(id),
  min_stock   numeric(12,3) not null default 0 check (min_stock >= 0),
  notes       text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  created_by  uuid references auth.users(id),
  updated_at  timestamptz not null default now(),
  updated_by  uuid references auth.users(id),
  constraint products_text_chk check (code = upper(code) and btrim(code) <> '' and btrim(name) <> '')
);
create unique index products_code_uq on public.products (code);
create index products_type_idx on public.products (product_type);
create index products_category_idx on public.products (category_id);
create index products_unit_idx on public.products (unit_id);

-- ---------------------------------------------------------------
-- Trigger: pencatat pembuat/pengubah dan audit trail
-- ---------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'product_categories','units','cow_types','non_carcass_types','cost_types',
    'payment_methods','warehouses','locations','accounts','customers','suppliers','products'
  ] loop
    execute format('create trigger %I before insert or update on public.%I
                    for each row execute function public.set_actor_columns()', t || '_actor', t);
    execute format('create trigger %I after insert or update or delete on public.%I
                    for each row execute function public.audit_row_change()', t || '_audit', t);
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- ---------------------------------------------------------------
-- RLS
-- Master sederhana: dibaca semua user login (dipakai di form),
-- diubah hanya dengan izin master_data.
-- ---------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'product_categories','units','cow_types','non_carcass_types','cost_types',
    'payment_methods','warehouses','locations','accounts'
  ] loop
    execute format('create policy %I on public.%I for select to authenticated using (true)',
                   t || '_select', t);
    execute format('create policy %I on public.%I for insert to authenticated
                    with check (public.has_permission(''master_data'',''create''))', t || '_insert', t);
    execute format('create policy %I on public.%I for update to authenticated
                    using (public.has_permission(''master_data'',''edit''))
                    with check (public.has_permission(''master_data'',''edit''))', t || '_update', t);
    execute format('grant select, insert, update on public.%I to authenticated', t);
  end loop;
end $$;

-- Rekening/kas bersifat keuangan: hanya yang punya izin keuangan atau master_data yang boleh melihat.
drop policy accounts_select on public.accounts;
create policy accounts_select on public.accounts for select to authenticated
  using (public.has_permission('master_data','view') or public.has_permission('cpj','view')
         or public.has_permission('crj','view'));

create policy customers_select on public.customers for select to authenticated
  using (public.has_permission('customer','view'));
create policy customers_insert on public.customers for insert to authenticated
  with check (public.has_permission('customer','create'));
create policy customers_update on public.customers for update to authenticated
  using (public.has_permission('customer','edit'))
  with check (public.has_permission('customer','edit'));

create policy suppliers_select on public.suppliers for select to authenticated
  using (public.has_permission('supplier','view'));
create policy suppliers_insert on public.suppliers for insert to authenticated
  with check (public.has_permission('supplier','create'));
create policy suppliers_update on public.suppliers for update to authenticated
  using (public.has_permission('supplier','edit'))
  with check (public.has_permission('supplier','edit'));

create policy products_select on public.products for select to authenticated
  using (public.has_permission('product','view'));
create policy products_insert on public.products for insert to authenticated
  with check (public.has_permission('product','create'));
create policy products_update on public.products for update to authenticated
  using (public.has_permission('product','edit'))
  with check (public.has_permission('product','edit'));

grant select, insert, update on public.customers, public.suppliers, public.products to authenticated;


-- ===== 0003_purchase_request.sql =====
-- HMI Internal System - Phase 5: Purchase Request
-- Semua perubahan lewat fungsi (SECURITY DEFINER) yang memeriksa izin dan
-- urutan status. Tabel hanya bisa dibaca langsung oleh user.

-- ---------------------------------------------------------------
-- Penomoran dokumen (dipakai ulang oleh RO, INV, CPJ, dst)
-- ---------------------------------------------------------------
create table public.document_sequences (
  doc_type    text    not null,
  year        integer not null,
  last_number integer not null default 0,
  primary key (doc_type, year)
);
alter table public.document_sequences enable row level security;
-- Tanpa policy dan tanpa grant: hanya fungsi di bawah yang menyentuh tabel ini.

create or replace function public.next_doc_number(p_type text, p_prefix text)
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_year integer := extract(year from (now() at time zone 'Asia/Jakarta'))::integer;
  v_n    integer;
begin
  insert into public.document_sequences as d (doc_type, year, last_number)
  values (p_type, v_year, 1)
  on conflict (doc_type, year) do update set last_number = d.last_number + 1
  returning last_number into v_n;
  return format('%s-%s-%s', p_prefix, v_year, lpad(v_n::text, 4, '0'));
end;
$$;
revoke all on function public.next_doc_number(text, text) from public, anon, authenticated;

create or replace function public.assign_doc_number()
returns trigger
language plpgsql
as $$
begin
  if new.doc_number is null then
    new.doc_number := public.next_doc_number(tg_argv[0], tg_argv[1]);
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------
-- Tabel
-- ---------------------------------------------------------------
create table public.purchase_requests (
  id            uuid primary key default gen_random_uuid(),
  doc_number    text unique,
  request_date  date not null default (now() at time zone 'Asia/Jakarta')::date,
  requester_id  uuid not null references public.user_profiles(id),
  department_id uuid references public.departments(id),
  reason        text not null check (btrim(reason) <> ''),
  priority      text not null default 'NORMAL' check (priority in ('LOW','NORMAL','HIGH')),
  status        text not null default 'DRAFT' check (status in
                 ('DRAFT','SUBMITTED','UNDER_REVIEW','APPROVED','REJECTED','ORDERED','RECEIVED','PAID','CLOSED')),
  decided_by    uuid references public.user_profiles(id),
  decided_at    timestamptz,
  review_note   text,
  created_at    timestamptz not null default now(),
  created_by    uuid references auth.users(id),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references auth.users(id),
  deleted_at    timestamptz
);
create index purchase_requests_status_idx    on public.purchase_requests(status);
create index purchase_requests_requester_idx on public.purchase_requests(requester_id);
create index purchase_requests_date_idx      on public.purchase_requests(request_date);

create table public.pr_items (
  id              uuid primary key default gen_random_uuid(),
  pr_id           uuid not null references public.purchase_requests(id),
  line_no         integer not null,
  product_id      uuid references public.products(id),
  item_name       text not null check (btrim(item_name) <> ''),
  qty             numeric(12,3) not null check (qty > 0),
  unit_id         uuid not null references public.units(id),
  estimated_price numeric(18,2) check (estimated_price >= 0),
  supplier_id     uuid references public.suppliers(id),
  notes           text,
  unique (pr_id, line_no)
);
create index pr_items_pr_idx       on public.pr_items(pr_id);
create index pr_items_product_idx  on public.pr_items(product_id);
create index pr_items_supplier_idx on public.pr_items(supplier_id);

create table public.pr_status_history (
  id          bigint generated always as identity primary key,
  pr_id       uuid not null references public.purchase_requests(id),
  from_status text,
  to_status   text not null,
  note        text,
  changed_by  uuid,
  changed_at  timestamptz not null default now()
);
create index pr_status_history_pr_idx on public.pr_status_history(pr_id);

create trigger purchase_requests_docno before insert on public.purchase_requests
  for each row execute function public.assign_doc_number('PR', 'PR');
create trigger purchase_requests_actor before insert or update on public.purchase_requests
  for each row execute function public.set_actor_columns();

create trigger purchase_requests_audit after insert or update or delete on public.purchase_requests
  for each row execute function public.audit_row_change();
create trigger pr_items_audit after insert or update or delete on public.pr_items
  for each row execute function public.audit_row_change();

-- Riwayat status tidak boleh diubah atau dihapus.
create or replace function public.block_history_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'riwayat tidak boleh diubah atau dihapus';
end;
$$;
create trigger pr_status_history_immutable before update or delete on public.pr_status_history
  for each row execute function public.block_history_mutation();

-- ---------------------------------------------------------------
-- RLS (baca saja; tulis lewat fungsi)
-- ---------------------------------------------------------------
alter table public.purchase_requests  enable row level security;
alter table public.pr_items           enable row level security;
alter table public.pr_status_history  enable row level security;

-- Pemilik PR melihat PR sendiri; yang punya izin purchase_request_all melihat semua.
create policy purchase_requests_select on public.purchase_requests for select to authenticated
  using (
    public.has_permission('purchase_request','view')
    and (requester_id = auth.uid() or public.has_permission('purchase_request_all','view'))
  );

create policy pr_items_select on public.pr_items for select to authenticated
  using (exists (select 1 from public.purchase_requests p where p.id = pr_id));

create policy pr_status_history_select on public.pr_status_history for select to authenticated
  using (exists (select 1 from public.purchase_requests p where p.id = pr_id));

grant select on public.purchase_requests, public.pr_items, public.pr_status_history to authenticated;

-- ---------------------------------------------------------------
-- Fungsi: simpan PR (draft baru atau ubah draft)
-- ---------------------------------------------------------------
create or replace function public.save_purchase_request(
  p_id       uuid,
  p_reason   text,
  p_priority text,
  p_items    jsonb
) returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_id   uuid;
  v_row  public.purchase_requests%rowtype;
  v_item jsonb;
  v_line integer := 0;
begin
  if not public.has_permission('purchase_request','create') then
    raise exception 'Anda tidak memiliki izin membuat Purchase Request' using errcode = '42501';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Isi minimal satu barang' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.purchase_requests (requester_id, department_id, reason, priority)
    select v_uid, up.department_id, p_reason, p_priority
      from public.user_profiles up where up.id = v_uid
    returning id into v_id;
  else
    select * into v_row from public.purchase_requests where id = p_id for update;
    if not found or v_row.deleted_at is not null then
      raise exception 'Purchase Request tidak ditemukan' using errcode = 'P0002';
    end if;
    if v_row.requester_id <> v_uid then
      raise exception 'Hanya pembuat PR yang boleh mengubah drafnya' using errcode = '42501';
    end if;
    if v_row.status <> 'DRAFT' then
      raise exception 'PR yang sudah diajukan tidak bisa diubah' using errcode = '55000';
    end if;
    update public.purchase_requests set reason = p_reason, priority = p_priority where id = p_id;
    v_id := p_id;
    delete from public.pr_items where pr_id = v_id;
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_line := v_line + 1;
    insert into public.pr_items (pr_id, line_no, product_id, item_name, qty, unit_id, estimated_price, notes)
    values (
      v_id, v_line,
      nullif(v_item->>'product_id','')::uuid,
      v_item->>'item_name',
      (v_item->>'qty')::numeric,
      (v_item->>'unit_id')::uuid,
      nullif(v_item->>'estimated_price','')::numeric,
      nullif(v_item->>'notes','')
    );
  end loop;

  if p_id is null then
    insert into public.pr_status_history (pr_id, from_status, to_status, changed_by)
    values (v_id, null, 'DRAFT', v_uid);
  end if;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------
-- Fungsi: ubah status dengan aturan transisi
-- ---------------------------------------------------------------
create or replace function public.pr_change_status(p_id uuid, p_to text, p_note text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_pr  public.purchase_requests%rowtype;
  v_ok  boolean := false;
begin
  select * into v_pr from public.purchase_requests where id = p_id for update;
  if not found or v_pr.deleted_at is not null then
    raise exception 'Purchase Request tidak ditemukan' using errcode = 'P0002';
  end if;

  if v_pr.status = 'DRAFT' and p_to = 'SUBMITTED' then
    if v_pr.requester_id <> v_uid or not public.has_permission('purchase_request','create') then
      raise exception 'Hanya pembuat PR yang boleh mengajukan' using errcode = '42501';
    end if;
    if not exists (select 1 from public.pr_items where pr_id = p_id) then
      raise exception 'PR belum memiliki barang' using errcode = '22023';
    end if;
    v_ok := true;

  elsif v_pr.status in ('SUBMITTED','UNDER_REVIEW') and p_to in ('UNDER_REVIEW','APPROVED','REJECTED')
        and not (v_pr.status = 'UNDER_REVIEW' and p_to = 'UNDER_REVIEW') then
    if not public.has_permission('purchase_request','approve') then
      raise exception 'Anda tidak memiliki izin menyetujui atau menolak PR' using errcode = '42501';
    end if;
    if p_to = 'REJECTED' and btrim(coalesce(p_note,'')) = '' then
      raise exception 'Alasan penolakan wajib diisi' using errcode = '22023';
    end if;
    v_ok := true;

  elsif v_pr.status = 'APPROVED' and p_to = 'ORDERED' then
    if not public.has_permission('purchase_request','edit') then
      raise exception 'Anda tidak memiliki izin memproses pembelian' using errcode = '42501';
    end if;
    v_ok := true;

  elsif v_pr.status = 'ORDERED' and p_to = 'RECEIVED' then
    if not public.has_permission('purchase_request','edit') then
      raise exception 'Anda tidak memiliki izin memproses pembelian' using errcode = '42501';
    end if;
    v_ok := true;
  end if;

  if not v_ok then
    raise exception 'Perpindahan status dari % ke % tidak diizinkan', v_pr.status, p_to using errcode = '55000';
  end if;

  update public.purchase_requests
     set status      = p_to,
         decided_by  = case when p_to in ('APPROVED','REJECTED') then v_uid else decided_by end,
         decided_at  = case when p_to in ('APPROVED','REJECTED') then now() else decided_at end,
         review_note = case when p_to = 'REJECTED' then btrim(p_note) else review_note end
   where id = p_id;

  insert into public.pr_status_history (pr_id, from_status, to_status, note, changed_by)
  values (p_id, v_pr.status, p_to, nullif(btrim(coalesce(p_note,'')), ''), v_uid);
end;
$$;

-- ---------------------------------------------------------------
-- Fungsi: hapus draft (soft delete), hanya pembuat dan hanya DRAFT
-- ---------------------------------------------------------------
create or replace function public.pr_discard(p_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_pr public.purchase_requests%rowtype;
begin
  select * into v_pr from public.purchase_requests where id = p_id for update;
  if not found or v_pr.deleted_at is not null then
    raise exception 'Purchase Request tidak ditemukan' using errcode = 'P0002';
  end if;
  if v_pr.requester_id <> auth.uid() then
    raise exception 'Hanya pembuat PR yang boleh menghapus drafnya' using errcode = '42501';
  end if;
  if v_pr.status <> 'DRAFT' then
    raise exception 'Hanya draf yang bisa dihapus' using errcode = '55000';
  end if;
  update public.purchase_requests set deleted_at = now() where id = p_id;
  insert into public.pr_status_history (pr_id, from_status, to_status, note, changed_by)
  values (p_id, 'DRAFT', 'DRAFT', 'Draf dihapus', auth.uid());
end;
$$;

-- ---------------------------------------------------------------
-- Fungsi: Purchasing mengisi supplier per barang setelah PR disetujui
-- ---------------------------------------------------------------
create or replace function public.pr_set_item_supplier(p_item_id uuid, p_supplier_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_status text;
begin
  if not public.has_permission('purchase_request','edit') then
    raise exception 'Anda tidak memiliki izin memproses pembelian' using errcode = '42501';
  end if;
  select p.status into v_status
    from public.pr_items i join public.purchase_requests p on p.id = i.pr_id
   where i.id = p_item_id and p.deleted_at is null;
  if v_status is null then
    raise exception 'Barang tidak ditemukan' using errcode = 'P0002';
  end if;
  if v_status not in ('APPROVED','ORDERED') then
    raise exception 'Supplier hanya bisa diisi setelah PR disetujui' using errcode = '55000';
  end if;
  update public.pr_items set supplier_id = p_supplier_id where id = p_item_id;
end;
$$;

revoke all on function public.save_purchase_request(uuid,text,text,jsonb) from public, anon;
revoke all on function public.pr_change_status(uuid,text,text) from public, anon;
revoke all on function public.pr_discard(uuid) from public, anon;
revoke all on function public.pr_set_item_supplier(uuid,uuid) from public, anon;
grant execute on function public.save_purchase_request(uuid,text,text,jsonb) to authenticated;
grant execute on function public.pr_change_status(uuid,text,text) to authenticated;
grant execute on function public.pr_discard(uuid) to authenticated;
grant execute on function public.pr_set_item_supplier(uuid,uuid) to authenticated;

-- ---------------------------------------------------------------
-- Daftar nama staff (hanya id, nama, departemen) agar nama pemohon dan
-- penyetuju bisa tampil di dokumen. Tidak membuka data akun lainnya.
-- View berjalan dengan hak pemilik, sengaja melewati RLS user_profiles.
-- ---------------------------------------------------------------
create view public.user_directory as
  select id, full_name, department_id, is_active from public.user_profiles;
revoke all on public.user_directory from public, anon;
grant select on public.user_directory to authenticated;


-- ===== 0004_pricing.sql =====
-- HMI Internal System - Phase 6: Pricing Toko
-- Riwayat harga bersifat tambah-saja: harga lama tidak ditimpa, tidak dihapus.
-- Perubahan lewat fungsi yang memeriksa izin dan aturan tanggal berlaku.

create extension if not exists btree_gist;

create table public.product_prices (
  id             uuid primary key default gen_random_uuid(),
  product_id     uuid not null references public.products(id),
  supplier_id    uuid references public.suppliers(id),
  buy_price      numeric(18,2) check (buy_price >= 0),
  sell_price     numeric(18,2) check (sell_price >= 0),
  effective_from date not null,
  effective_to   date,
  note           text,
  voided_at      timestamptz,
  voided_by      uuid references auth.users(id),
  void_reason    text,
  created_at     timestamptz not null default now(),
  created_by     uuid references auth.users(id),
  updated_at     timestamptz not null default now(),
  updated_by     uuid references auth.users(id),
  constraint product_prices_has_price check (buy_price is not null or sell_price is not null),
  constraint product_prices_range check (effective_to is null or effective_to >= effective_from),
  constraint product_prices_void check ((voided_at is null) = (void_reason is null)),
  -- Tidak boleh ada dua harga aktif yang masa berlakunya tumpang tindih untuk produk yang sama.
  constraint product_prices_no_overlap exclude using gist (
    product_id with =,
    daterange(effective_from, effective_to, '[]') with &&
  ) where (voided_at is null)
);
create index product_prices_product_idx  on public.product_prices (product_id, effective_from desc);
create index product_prices_supplier_idx on public.product_prices (supplier_id);

create trigger product_prices_actor before insert or update on public.product_prices
  for each row execute function public.set_actor_columns();
create trigger product_prices_audit after insert or update or delete on public.product_prices
  for each row execute function public.audit_row_change();

create or replace function public.guard_product_prices()
returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'riwayat harga tidak boleh dihapus';
  end if;
  -- Update hanya lewat fungsi harga, dan hanya menutup masa berlaku atau membatalkan.
  if coalesce(current_setting('hmi.price_fn', true), '') <> 'on' then
    raise exception 'harga hanya boleh diubah lewat fungsi harga';
  end if;
  if new.product_id is distinct from old.product_id
     or new.supplier_id is distinct from old.supplier_id
     or new.buy_price is distinct from old.buy_price
     or new.sell_price is distinct from old.sell_price
     or new.effective_from is distinct from old.effective_from
     or new.note is distinct from old.note then
    raise exception 'nilai harga yang sudah tercatat tidak boleh diubah';
  end if;
  return new;
end;
$$;
create trigger product_prices_guard before update or delete on public.product_prices
  for each row execute function public.guard_product_prices();

alter table public.product_prices enable row level security;
-- Tanpa policy dan tanpa grant: dibaca lewat view di bawah, ditulis lewat fungsi.

-- ---------------------------------------------------------------
-- View baca: harga beli dan supplier hanya untuk pemegang izin pricing_cost.
-- View berjalan dengan hak pemilik; filter izin ada di dalam view.
-- ---------------------------------------------------------------
create view public.v_product_prices as
select
  p.id,
  p.product_id,
  case when public.has_permission('pricing_cost','view') then p.supplier_id end as supplier_id,
  case when public.has_permission('pricing_cost','view') then p.buy_price end as buy_price,
  p.sell_price,
  p.effective_from,
  p.effective_to,
  p.note,
  p.voided_at,
  p.void_reason,
  p.created_at,
  p.created_by
from public.product_prices p
where public.has_permission('pricing','view');

create view public.v_current_prices as
select *
from public.v_product_prices
where voided_at is null
  and effective_from <= (now() at time zone 'Asia/Jakarta')::date
  and (effective_to is null or effective_to >= (now() at time zone 'Asia/Jakarta')::date);

revoke all on public.v_product_prices, public.v_current_prices from public, anon;
grant select on public.v_product_prices, public.v_current_prices to authenticated;

-- ---------------------------------------------------------------
-- Fungsi: tetapkan harga baru
-- ---------------------------------------------------------------
create or replace function public.set_product_price(
  p_product_id  uuid,
  p_supplier_id uuid,
  p_buy_price   numeric,
  p_sell_price  numeric,
  p_from        date,
  p_note        text default null
) returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_latest public.product_prices%rowtype;
  v_id     uuid;
begin
  if not public.has_permission('pricing','create') then
    raise exception 'Anda tidak memiliki izin mengubah harga' using errcode = '42501';
  end if;
  if (p_buy_price is not null or p_supplier_id is not null) and not public.has_permission('pricing_cost','view') then
    raise exception 'Anda tidak memiliki izin mengisi harga beli' using errcode = '42501';
  end if;
  if p_buy_price is null and p_sell_price is null then
    raise exception 'Isi harga beli atau harga jual' using errcode = '22023';
  end if;
  if coalesce(p_buy_price, 0) < 0 or coalesce(p_sell_price, 0) < 0 then
    raise exception 'Harga tidak boleh kurang dari 0' using errcode = '22023';
  end if;
  if p_from is null then
    raise exception 'Tanggal berlaku wajib diisi' using errcode = '22023';
  end if;
  if not exists (select 1 from public.products where id = p_product_id and is_active) then
    raise exception 'Produk tidak ditemukan atau sudah nonaktif' using errcode = 'P0002';
  end if;
  if p_supplier_id is not null and not exists (select 1 from public.suppliers where id = p_supplier_id and is_active) then
    raise exception 'Supplier tidak ditemukan atau sudah nonaktif' using errcode = 'P0002';
  end if;

  -- Kunci per produk agar dua orang tidak menyimpan bersamaan.
  perform 1 from public.products where id = p_product_id for update;

  select * into v_latest
    from public.product_prices
   where product_id = p_product_id and voided_at is null
   order by effective_from desc limit 1;

  if found then
    if p_from <= v_latest.effective_from then
      raise exception 'Tanggal berlaku harus setelah % (tanggal berlaku harga terakhir). Jika harga terakhir salah, batalkan dulu harga tersebut.',
        to_char(v_latest.effective_from, 'DD-MM-YYYY') using errcode = '22023';
    end if;
    perform set_config('hmi.price_fn', 'on', true);
    update public.product_prices set effective_to = p_from - 1 where id = v_latest.id;
    perform set_config('hmi.price_fn', 'off', true);
  end if;

  insert into public.product_prices (product_id, supplier_id, buy_price, sell_price, effective_from, note)
  values (p_product_id, p_supplier_id, p_buy_price, p_sell_price, p_from, nullif(btrim(coalesce(p_note, '')), ''))
  returning id into v_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------
-- Fungsi: batalkan harga terakhir (koreksi salah input)
-- Baris tetap tersimpan di riwayat, hanya ditandai batal.
-- ---------------------------------------------------------------
create or replace function public.void_product_price(p_price_id uuid, p_reason text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_row  public.product_prices%rowtype;
  v_prev public.product_prices%rowtype;
begin
  if not public.has_permission('pricing','edit') then
    raise exception 'Anda tidak memiliki izin membatalkan harga' using errcode = '42501';
  end if;
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'Alasan pembatalan wajib diisi' using errcode = '22023';
  end if;

  select * into v_row from public.product_prices where id = p_price_id for update;
  if not found then
    raise exception 'Harga tidak ditemukan' using errcode = 'P0002';
  end if;
  if v_row.voided_at is not null then
    raise exception 'Harga ini sudah dibatalkan' using errcode = '55000';
  end if;
  if exists (select 1 from public.product_prices
              where product_id = v_row.product_id and voided_at is null and effective_from > v_row.effective_from) then
    raise exception 'Hanya harga terakhir yang bisa dibatalkan' using errcode = '55000';
  end if;

  perform set_config('hmi.price_fn', 'on', true);
  update public.product_prices
     set voided_at = now(), voided_by = auth.uid(), void_reason = btrim(p_reason)
   where id = p_price_id;

  -- Buka kembali harga sebelumnya yang tadinya ditutup oleh harga ini.
  select * into v_prev from public.product_prices
   where product_id = v_row.product_id and voided_at is null and id <> p_price_id
   order by effective_from desc limit 1;
  if found and v_prev.effective_to = v_row.effective_from - 1 then
    update public.product_prices set effective_to = null where id = v_prev.id;
  end if;
  perform set_config('hmi.price_fn', 'off', true);
end;
$$;

revoke all on function public.set_product_price(uuid,uuid,numeric,numeric,date,text) from public, anon;
revoke all on function public.void_product_price(uuid,text) from public, anon;
grant execute on function public.set_product_price(uuid,uuid,numeric,numeric,date,text) to authenticated;
grant execute on function public.void_product_price(uuid,text) to authenticated;


-- ===== 0005_documents_stock.sql =====
-- HMI Internal System - Phase 7: kerangka dokumen + Stok
-- Kerangka dokumen dipakai oleh RO, Production Order, Packing List, Penimbangan,
-- Analisa, Invoice, CRJ, CPJ, Opname: semua tulis lewat save_doc / doc_change_status
-- (SECURITY DEFINER) yang memeriksa izin dan urutan status di database.

-- ---------------------------------------------------------------
-- Riwayat status bersama (hanya tambah, tidak bisa diubah)
-- ---------------------------------------------------------------
create table public.doc_status_history (
  id          bigint generated always as identity primary key,
  doc_type    text not null,
  doc_id      uuid not null,
  from_status text,
  to_status   text not null,
  note        text,
  changed_by  uuid,
  changed_at  timestamptz not null default now()
);
create index doc_status_history_doc_idx on public.doc_status_history(doc_type, doc_id);
create trigger doc_status_history_immutable before update or delete on public.doc_status_history
  for each row execute function public.block_history_mutation();

-- ---------------------------------------------------------------
-- Registry jenis dokumen dan aturan perpindahan status
-- ---------------------------------------------------------------
create table public.doc_registry (
  doc_type          text primary key,
  table_name        text not null,
  module            text not null,
  header_cols       text[] not null,
  fixed             jsonb not null default '{}',
  editable_statuses text[] not null default '{DRAFT}',
  children          jsonb not null default '[]',   -- [{key, table, fk, cols[]}]
  after_save_fn     text
);

create table public.doc_rules (
  doc_type    text not null references public.doc_registry(doc_type),
  from_status text not null,
  to_status   text not null,
  module      text not null,
  action      text not null check (action in ('view','create','edit','delete','approve','export')),
  needs_note  boolean not null default false,
  label       text not null,
  primary key (doc_type, from_status, to_status)
);

alter table public.doc_status_history enable row level security;
alter table public.doc_registry       enable row level security;
alter table public.doc_rules          enable row level security;

create policy doc_registry_select on public.doc_registry for select to authenticated using (true);
create policy doc_rules_select    on public.doc_rules    for select to authenticated using (true);
create policy doc_status_history_select on public.doc_status_history for select to authenticated
  using (public.has_permission((select r.module from public.doc_registry r where r.doc_type = doc_status_history.doc_type), 'view'));
grant select on public.doc_status_history, public.doc_registry, public.doc_rules to authenticated;

-- ---------------------------------------------------------------
-- save_doc: buat atau ubah dokumen (hanya status yang boleh diedit)
-- ---------------------------------------------------------------
create or replace function public.save_doc(p_type text, p_id uuid, p_header jsonb, p_children jsonb default '{}'::jsonb)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  r       public.doc_registry%rowtype;
  v_id    uuid := p_id;
  v_hdr   jsonb;
  v_cols  text;
  v_status text;
  ch      jsonb;
  v_ccols text;
  v_n     integer;
begin
  select * into r from public.doc_registry where doc_type = p_type;
  if not found then
    raise exception 'Jenis dokumen tidak dikenal' using errcode = '22023';
  end if;
  if not public.has_permission(r.module, case when p_id is null then 'create' else 'edit' end) then
    raise exception 'Anda tidak memiliki izin untuk menyimpan dokumen ini' using errcode = '42501';
  end if;

  v_hdr := coalesce(p_header, '{}'::jsonb) || r.fixed;
  select string_agg(quote_ident(c), ',') into v_cols
    from unnest(r.header_cols || array(select jsonb_object_keys(r.fixed))) c where v_hdr ? c;
  if v_cols is null then
    raise exception 'Isian dokumen kosong' using errcode = '22023';
  end if;

  if v_id is null then
    execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1) returning id',
                   r.table_name, v_cols, v_cols, r.table_name)
      into v_id using v_hdr;
  else
    execute format('select status from public.%I where id = $1 and deleted_at is null for update', r.table_name)
      into v_status using v_id;
    if v_status is null then
      raise exception 'Dokumen tidak ditemukan' using errcode = 'P0002';
    end if;
    if not (v_status = any (r.editable_statuses)) then
      raise exception 'Dokumen berstatus % tidak bisa diubah lagi', v_status using errcode = '55000';
    end if;
    execute format('update public.%I set (%s) = (select %s from jsonb_populate_record(null::public.%I, $2)) where id = $1',
                   r.table_name, v_cols, v_cols, r.table_name)
      using v_id, v_hdr;
  end if;

  for ch in select * from jsonb_array_elements(r.children) loop
    if p_children ? (ch->>'key') then
      select string_agg(quote_ident(c), ',') into v_ccols from jsonb_array_elements_text(ch->'cols') c;
      execute format('delete from public.%I where %I = $1', ch->>'table', ch->>'fk') using v_id;
      execute format(
        'insert into public.%I (%I, line_no, %s) select $1, e.ord, %s from jsonb_array_elements($2) with ordinality e(j, ord), lateral jsonb_populate_record(null::public.%I, e.j) p',
        ch->>'table', ch->>'fk', v_ccols,
        (select string_agg('p.' || quote_ident(c), ',') from jsonb_array_elements_text(ch->'cols') c),
        ch->>'table')
        using v_id, p_children->(ch->>'key');
    end if;
  end loop;

  if r.after_save_fn is not null then
    execute format('select public.%I($1)', r.after_save_fn) using v_id;
  end if;

  if p_id is null then
    insert into public.doc_status_history (doc_type, doc_id, from_status, to_status, changed_by)
    values (p_type, v_id, null, 'DRAFT', auth.uid());
  end if;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------
-- doc_change_status: pindah status sesuai doc_rules
-- ---------------------------------------------------------------
create or replace function public.doc_change_status(p_type text, p_id uuid, p_to text, p_note text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  r      public.doc_registry%rowtype;
  v_from text;
  v_rule public.doc_rules%rowtype;
begin
  select * into r from public.doc_registry where doc_type = p_type;
  if not found then
    raise exception 'Jenis dokumen tidak dikenal' using errcode = '22023';
  end if;
  execute format('select status from public.%I where id = $1 and deleted_at is null for update', r.table_name)
    into v_from using p_id;
  if v_from is null then
    raise exception 'Dokumen tidak ditemukan' using errcode = 'P0002';
  end if;

  select * into v_rule from public.doc_rules where doc_type = p_type and from_status = v_from and to_status = p_to;
  if not found then
    raise exception 'Perpindahan status dari % ke % tidak diizinkan', v_from, p_to using errcode = '55000';
  end if;
  if not public.has_permission(v_rule.module, v_rule.action) then
    raise exception 'Anda tidak memiliki izin untuk aksi "%"', v_rule.label using errcode = '42501';
  end if;
  if v_rule.needs_note and btrim(coalesce(p_note, '')) = '' then
    raise exception 'Alasan atau catatan wajib diisi' using errcode = '22023';
  end if;

  perform set_config('hmi.doc_note', coalesce(btrim(p_note), ''), true);
  execute format('update public.%I set status = $2 where id = $1', r.table_name) using p_id, p_to;
  perform set_config('hmi.doc_note', '', true);

  insert into public.doc_status_history (doc_type, doc_id, from_status, to_status, note, changed_by)
  values (p_type, p_id, v_from, p_to, nullif(btrim(coalesce(p_note, '')), ''), auth.uid());
end;
$$;

revoke all on function public.save_doc(text,uuid,jsonb,jsonb) from public, anon;
revoke all on function public.doc_change_status(text,uuid,text,text) from public, anon;
grant execute on function public.save_doc(text,uuid,jsonb,jsonb) to authenticated;
grant execute on function public.doc_change_status(text,uuid,text,text) to authenticated;

-- ---------------------------------------------------------------
-- Stok: buku mutasi (hanya tambah). Saldo = jumlah mutasi.
-- ---------------------------------------------------------------
create table public.stock_movements (
  id            uuid primary key default gen_random_uuid(),
  product_id    uuid not null references public.products(id),
  warehouse_id  uuid not null references public.warehouses(id),
  movement_date date not null default (now() at time zone 'Asia/Jakarta')::date,
  movement_type text not null check (movement_type in
    ('OPENING','IN_PURCHASE','IN_PRODUCTION','OUT_SALE','ADJUST_IN','ADJUST_OUT',
     'OPNAME_IN','OPNAME_OUT','REVERSAL_IN','REVERSAL_OUT')),
  qty           numeric(14,3) not null check (qty <> 0),   -- bertanda: masuk +, keluar -
  unit_cost     numeric(18,2) check (unit_cost >= 0),
  ref_type      text,
  ref_id        uuid,
  note          text,
  created_at    timestamptz not null default now(),
  created_by    uuid references auth.users(id) default auth.uid()
);
create index stock_movements_product_idx on public.stock_movements(product_id, warehouse_id);
create index stock_movements_ref_idx     on public.stock_movements(ref_type, ref_id);
create trigger stock_movements_immutable before update or delete on public.stock_movements
  for each row execute function public.block_history_mutation();

alter table public.stock_movements enable row level security;
create policy stock_movements_select on public.stock_movements for select to authenticated
  using (public.has_permission('stock','view'));
grant select on public.stock_movements to authenticated;

-- Fungsi internal: tidak bisa dipanggil langsung oleh user.
create or replace function public.post_stock(
  p_product uuid, p_wh uuid, p_type text, p_qty numeric, p_cost numeric,
  p_ref_type text, p_ref_id uuid, p_note text, p_date date default null)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_bal  numeric;
  v_name text;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_product::text || p_wh::text, 0));
  if p_qty < 0 then
    select coalesce(sum(qty), 0) into v_bal from public.stock_movements where product_id = p_product and warehouse_id = p_wh;
    if v_bal + p_qty < 0 then
      select name into v_name from public.products where id = p_product;
      raise exception 'Stok % tidak cukup (tersedia %, diminta %)', v_name, v_bal, -p_qty using errcode = '22023';
    end if;
  end if;
  insert into public.stock_movements (product_id, warehouse_id, movement_date, movement_type, qty, unit_cost, ref_type, ref_id, note)
  values (p_product, p_wh, coalesce(p_date, (now() at time zone 'Asia/Jakarta')::date), p_type, p_qty, p_cost, p_ref_type, p_ref_id, p_note);
end;
$$;
revoke all on function public.post_stock(uuid,uuid,text,numeric,numeric,text,uuid,text,date) from public, anon, authenticated;

-- Pencatatan manual oleh user: stok awal, pembelian masuk, penyesuaian.
create or replace function public.record_stock_movement(
  p_product uuid, p_wh uuid, p_type text, p_qty numeric, p_cost numeric, p_note text, p_date date default null)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.has_permission('stock','create') then
    raise exception 'Anda tidak memiliki izin mencatat stok' using errcode = '42501';
  end if;
  if p_type not in ('OPENING','IN_PURCHASE','ADJUST_IN','ADJUST_OUT') then
    raise exception 'Jenis mutasi tidak diizinkan' using errcode = '22023';
  end if;
  if p_qty is null or p_qty <= 0 then
    raise exception 'Jumlah harus lebih dari 0' using errcode = '22023';
  end if;
  if p_type in ('ADJUST_IN','ADJUST_OUT') and btrim(coalesce(p_note,'')) = '' then
    raise exception 'Penyesuaian stok wajib disertai alasan' using errcode = '22023';
  end if;
  if p_type = 'IN_PURCHASE' and p_cost is null then
    raise exception 'Harga beli per satuan wajib diisi untuk pembelian masuk' using errcode = '22023';
  end if;
  if p_date is not null and p_date > (now() at time zone 'Asia/Jakarta')::date then
    raise exception 'Tanggal mutasi tidak boleh di masa depan' using errcode = '22023';
  end if;
  if not exists (select 1 from public.products where id = p_product and is_active) then
    raise exception 'Produk tidak ditemukan atau nonaktif' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.warehouses where id = p_wh and is_active) then
    raise exception 'Gudang tidak ditemukan atau nonaktif' using errcode = 'P0002';
  end if;
  if p_cost is not null and not public.has_permission('pricing_cost','view') then
    raise exception 'Anda tidak memiliki izin mengisi harga beli' using errcode = '42501';
  end if;
  perform public.post_stock(p_product, p_wh, p_type,
    case when p_type = 'ADJUST_OUT' then -p_qty else p_qty end,
    p_cost, 'MANUAL', null, nullif(btrim(coalesce(p_note,'')), ''), p_date);
end;
$$;
revoke all on function public.record_stock_movement(uuid,uuid,text,numeric,numeric,text,date) from public, anon;
grant execute on function public.record_stock_movement(uuid,uuid,text,numeric,numeric,text,date) to authenticated;

-- Saldo per produk per gudang dan ringkasan per produk (stok per item).
create view public.v_stock_balance with (security_invoker = true) as
  select product_id, warehouse_id, sum(qty)::numeric(14,3) as qty
    from public.stock_movements group by product_id, warehouse_id;

create view public.v_stock_summary with (security_invoker = true) as
  select p.id as product_id, p.code, p.name, p.product_type, p.unit_id, p.min_stock,
         coalesce(b.qty, 0)::numeric(14,3) as qty,
         (coalesce(b.qty, 0) < p.min_stock) as is_low
    from public.products p
    left join (select product_id, sum(qty) as qty from public.stock_movements group by product_id) b on b.product_id = p.id
   where p.is_active;
grant select on public.v_stock_balance, public.v_stock_summary to authenticated;

-- Nilai stok memakai harga beli terakhir (pembelian masuk terbaru). Hanya untuk pricing_cost.
create view public.v_stock_value as
  select s.product_id, s.code, s.name, s.qty, l.unit_cost as last_cost,
         case when l.unit_cost is null then null else (s.qty * l.unit_cost)::numeric(18,2) end as value
    from public.v_stock_summary s
    left join lateral (
      select unit_cost from public.stock_movements m
       where m.product_id = s.product_id and m.movement_type = 'IN_PURCHASE' and m.unit_cost is not null
       order by m.movement_date desc, m.created_at desc limit 1) l on true
   where public.has_permission('pricing_cost','view') and public.has_permission('stock','view');
grant select on public.v_stock_value to authenticated;

-- ---------------------------------------------------------------
-- Stock Opname
-- ---------------------------------------------------------------
create table public.stock_opnames (
  id           uuid primary key default gen_random_uuid(),
  doc_number   text unique,
  opname_date  date not null default (now() at time zone 'Asia/Jakarta')::date,
  warehouse_id uuid not null references public.warehouses(id),
  notes        text,
  status       text not null default 'DRAFT' check (status in ('DRAFT','APPROVED','CANCELLED')),
  created_at   timestamptz not null default now(),
  created_by   uuid references auth.users(id),
  updated_at   timestamptz not null default now(),
  updated_by   uuid references auth.users(id),
  deleted_at   timestamptz
);
create table public.so_items (
  id          uuid primary key default gen_random_uuid(),
  opname_id   uuid not null references public.stock_opnames(id),
  line_no     integer not null,
  product_id  uuid not null references public.products(id),
  system_qty  numeric(14,3) not null default 0,
  counted_qty numeric(14,3) not null check (counted_qty >= 0),
  unique (opname_id, line_no),
  unique (opname_id, product_id)
);
create index so_items_opname_idx on public.so_items(opname_id);

create trigger stock_opnames_docno before insert on public.stock_opnames
  for each row execute function public.assign_doc_number('SO', 'SO');
create trigger stock_opnames_actor before insert or update on public.stock_opnames
  for each row execute function public.set_actor_columns();
create trigger stock_opnames_audit after insert or update or delete on public.stock_opnames
  for each row execute function public.audit_row_change();
create trigger so_items_audit after insert or update or delete on public.so_items
  for each row execute function public.audit_row_change();

alter table public.stock_opnames enable row level security;
alter table public.so_items      enable row level security;
create policy stock_opnames_select on public.stock_opnames for select to authenticated
  using (public.has_permission('stock_opname','view'));
create policy so_items_select on public.so_items for select to authenticated
  using (public.has_permission('stock_opname','view'));
grant select on public.stock_opnames, public.so_items to authenticated;

create or replace function public.so_fill_system_qty(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.so_items i
     set system_qty = coalesce((select sum(m.qty) from public.stock_movements m
                                 where m.product_id = i.product_id and m.warehouse_id = o.warehouse_id), 0)
    from public.stock_opnames o
   where o.id = p_id and i.opname_id = o.id;
end;
$$;
revoke all on function public.so_fill_system_qty(uuid) from public, anon, authenticated;

create or replace function public.so_on_status()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  i    record;
  v_bal numeric;
  v_diff numeric;
begin
  if new.status = 'APPROVED' and old.status = 'DRAFT' then
    for i in select * from public.so_items where opname_id = new.id loop
      select coalesce(sum(qty), 0) into v_bal from public.stock_movements
       where product_id = i.product_id and warehouse_id = new.warehouse_id;
      v_diff := i.counted_qty - v_bal;
      update public.so_items set system_qty = v_bal where id = i.id;
      if v_diff <> 0 then
        perform public.post_stock(i.product_id, new.warehouse_id,
          case when v_diff > 0 then 'OPNAME_IN' else 'OPNAME_OUT' end,
          v_diff, null, 'SO', new.id, 'Stock opname ' || new.doc_number, new.opname_date);
      end if;
    end loop;
  end if;
  return new;
end;
$$;
create trigger stock_opnames_status after update of status on public.stock_opnames
  for each row execute function public.so_on_status();

insert into public.doc_registry (doc_type, table_name, module, header_cols, children, after_save_fn) values
 ('SO', 'stock_opnames', 'stock_opname', '{opname_date,warehouse_id,notes}',
  '[{"key":"items","table":"so_items","fk":"opname_id","cols":["product_id","counted_qty"]}]', 'so_fill_system_qty');
insert into public.doc_rules (doc_type, from_status, to_status, module, action, needs_note, label) values
 ('SO','DRAFT','APPROVED','stock_opname','approve',false,'Setujui dan koreksi stok'),
 ('SO','DRAFT','CANCELLED','stock_opname','edit',true,'Batalkan');


-- ===== 0006_sales_flow.sql =====
-- HMI Internal System - Phase 8 sampai 10: RO & harga Horeka, Production Order, Packing List
-- Memakai kerangka dokumen dari 0005 (save_doc, doc_change_status).

-- ---------------------------------------------------------------
-- Pembantu: pasang trigger, RLS, dan grant standar
-- ---------------------------------------------------------------
create or replace function public.attach_doc_standard(p_table text, p_type text, p_prefix text, p_module text)
returns void language plpgsql as $$
begin
  execute format('create trigger %I before insert on public.%I for each row execute function public.assign_doc_number(%L, %L)',
                 p_table || '_docno', p_table, p_type, p_prefix);
  execute format('create trigger %I before insert or update on public.%I for each row execute function public.set_actor_columns()',
                 p_table || '_actor', p_table);
  execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.audit_row_change()',
                 p_table || '_audit', p_table);
  execute format('alter table public.%I enable row level security', p_table);
  execute format('create policy %I on public.%I for select to authenticated using (public.has_permission(%L,''view'') and deleted_at is null)',
                 p_table || '_select', p_table, p_module);
  execute format('grant select on public.%I to authenticated', p_table);
end $$;

create or replace function public.attach_child_standard(p_table text, p_module text)
returns void language plpgsql as $$
begin
  execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.audit_row_change()',
                 p_table || '_audit', p_table);
  execute format('alter table public.%I enable row level security', p_table);
  execute format('create policy %I on public.%I for select to authenticated using (public.has_permission(%L,''view''))',
                 p_table || '_select', p_table, p_module);
  execute format('grant select on public.%I to authenticated', p_table);
end $$;
revoke all on function public.attach_doc_standard(text,text,text,text) from public, anon, authenticated;
revoke all on function public.attach_child_standard(text,text) from public, anon, authenticated;

-- ---------------------------------------------------------------
-- Harga Horeka per customer (riwayat tambah-saja)
-- ---------------------------------------------------------------
create table public.customer_prices (
  id             uuid primary key default gen_random_uuid(),
  customer_id    uuid not null references public.customers(id),
  product_id     uuid not null references public.products(id),
  price          numeric(18,2) not null check (price >= 0),
  effective_from date not null,
  effective_to   date,
  note           text,
  voided_at      timestamptz,
  voided_by      uuid references auth.users(id),
  void_reason    text,
  created_at     timestamptz not null default now(),
  created_by     uuid references auth.users(id),
  updated_at     timestamptz not null default now(),
  updated_by     uuid references auth.users(id),
  constraint customer_prices_range check (effective_to is null or effective_to >= effective_from),
  constraint customer_prices_void check ((voided_at is null) = (void_reason is null)),
  constraint customer_prices_no_overlap exclude using gist (
    customer_id with =, product_id with =,
    daterange(effective_from, effective_to, '[]') with &&
  ) where (voided_at is null)
);
create index customer_prices_idx on public.customer_prices (customer_id, product_id, effective_from desc);
create trigger customer_prices_actor before insert or update on public.customer_prices
  for each row execute function public.set_actor_columns();
create trigger customer_prices_audit after insert or update or delete on public.customer_prices
  for each row execute function public.audit_row_change();

create or replace function public.guard_customer_prices()
returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'riwayat harga tidak boleh dihapus'; end if;
  if coalesce(current_setting('hmi.cprice_fn', true), '') <> 'on' then
    raise exception 'harga hanya boleh diubah lewat fungsi harga';
  end if;
  if new.customer_id is distinct from old.customer_id or new.product_id is distinct from old.product_id
     or new.price is distinct from old.price or new.effective_from is distinct from old.effective_from then
    raise exception 'nilai harga yang sudah tercatat tidak boleh diubah';
  end if;
  return new;
end $$;
create trigger customer_prices_guard before update or delete on public.customer_prices
  for each row execute function public.guard_customer_prices();
alter table public.customer_prices enable row level security;

create view public.v_customer_prices as
  select id, customer_id, product_id, price, effective_from, effective_to, note, voided_at, void_reason, created_at
    from public.customer_prices
   where public.has_permission('ro','view') or public.has_permission('invoice','view');
revoke all on public.v_customer_prices from public, anon;
grant select on public.v_customer_prices to authenticated;

create or replace function public.set_customer_price(p_customer uuid, p_product uuid, p_price numeric, p_from date, p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_latest public.customer_prices%rowtype; v_id uuid; v_type text;
begin
  if not public.has_permission('customer','edit') then
    raise exception 'Anda tidak memiliki izin mengubah harga customer' using errcode = '42501';
  end if;
  if p_price is null or p_price < 0 then raise exception 'Harga harus berupa angka, tidak boleh negatif' using errcode = '22023'; end if;
  select type into v_type from public.customers where id = p_customer and is_active;
  if v_type is null then raise exception 'Customer tidak ditemukan atau nonaktif' using errcode = 'P0002'; end if;
  if v_type <> 'HOREKA' then raise exception 'Harga khusus hanya untuk customer Horeka' using errcode = '22023'; end if;
  if not exists (select 1 from public.products where id = p_product and is_active) then
    raise exception 'Produk tidak ditemukan atau nonaktif' using errcode = 'P0002';
  end if;
  select * into v_latest from public.customer_prices
   where customer_id = p_customer and product_id = p_product and voided_at is null
   order by effective_from desc limit 1 for update;
  if found and p_from <= v_latest.effective_from then
    raise exception 'Tanggal berlaku harus setelah harga sebelumnya (%)', v_latest.effective_from using errcode = '22023';
  end if;
  perform set_config('hmi.cprice_fn', 'on', true);
  if found and (v_latest.effective_to is null or v_latest.effective_to >= p_from) then
    update public.customer_prices set effective_to = p_from - 1 where id = v_latest.id;
  end if;
  perform set_config('hmi.cprice_fn', 'off', true);
  insert into public.customer_prices (customer_id, product_id, price, effective_from, note)
  values (p_customer, p_product, p_price, p_from, nullif(btrim(coalesce(p_note,'')), '')) returning id into v_id;
  return v_id;
end $$;

create or replace function public.void_customer_price(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_row public.customer_prices%rowtype; v_prev public.customer_prices%rowtype;
begin
  if not public.has_permission('customer','edit') then
    raise exception 'Anda tidak memiliki izin membatalkan harga' using errcode = '42501';
  end if;
  if btrim(coalesce(p_reason,'')) = '' then raise exception 'Alasan pembatalan wajib diisi' using errcode = '22023'; end if;
  select * into v_row from public.customer_prices where id = p_id for update;
  if not found then raise exception 'Harga tidak ditemukan' using errcode = 'P0002'; end if;
  if v_row.voided_at is not null then raise exception 'Harga ini sudah dibatalkan' using errcode = '55000'; end if;
  if exists (select 1 from public.customer_prices where customer_id = v_row.customer_id and product_id = v_row.product_id
              and voided_at is null and effective_from > v_row.effective_from) then
    raise exception 'Hanya harga terakhir yang bisa dibatalkan' using errcode = '55000';
  end if;
  perform set_config('hmi.cprice_fn', 'on', true);
  update public.customer_prices set voided_at = now(), voided_by = auth.uid(), void_reason = btrim(p_reason) where id = p_id;
  select * into v_prev from public.customer_prices
   where customer_id = v_row.customer_id and product_id = v_row.product_id and voided_at is null and id <> p_id
   order by effective_from desc limit 1;
  if found and v_prev.effective_to = v_row.effective_from - 1 then
    update public.customer_prices set effective_to = null where id = v_prev.id;
  end if;
  perform set_config('hmi.cprice_fn', 'off', true);
end $$;

-- Harga untuk customer pada tanggal tertentu: harga Horeka jika ada, kalau tidak harga toko.
create or replace function public.price_for(p_customer uuid, p_product uuid, p_date date default null)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare v_d date := coalesce(p_date, (now() at time zone 'Asia/Jakarta')::date); v_p numeric;
begin
  if not (public.has_permission('ro','view') or public.has_permission('invoice','view')) then return null; end if;
  select price into v_p from public.customer_prices
   where customer_id = p_customer and product_id = p_product and voided_at is null
     and effective_from <= v_d and (effective_to is null or effective_to >= v_d) limit 1;
  if v_p is null then
    select sell_price into v_p from public.product_prices
     where product_id = p_product and voided_at is null and sell_price is not null
       and effective_from <= v_d and (effective_to is null or effective_to >= v_d) limit 1;
  end if;
  return v_p;
end $$;

revoke all on function public.set_customer_price(uuid,uuid,numeric,date,text) from public, anon;
revoke all on function public.void_customer_price(uuid,text) from public, anon;
revoke all on function public.price_for(uuid,uuid,date) from public, anon;
grant execute on function public.set_customer_price(uuid,uuid,numeric,date,text) to authenticated;
grant execute on function public.void_customer_price(uuid,text) to authenticated;
grant execute on function public.price_for(uuid,uuid,date) to authenticated;

-- ---------------------------------------------------------------
-- RO (Request Order)
-- ---------------------------------------------------------------
create table public.request_orders (
  id            uuid primary key default gen_random_uuid(),
  doc_number    text unique,
  customer_id   uuid not null references public.customers(id),
  order_date    date not null default (now() at time zone 'Asia/Jakarta')::date,
  delivery_date date,
  notes         text,
  total_amount  numeric(18,2) not null default 0,
  status        text not null default 'DRAFT' check (status in ('DRAFT','CONFIRMED','COMPLETED','CANCELLED')),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id),
  deleted_at timestamptz,
  constraint ro_dates check (delivery_date is null or delivery_date >= order_date)
);
create table public.ro_items (
  id         uuid primary key default gen_random_uuid(),
  ro_id      uuid not null references public.request_orders(id),
  line_no    integer not null,
  product_id uuid not null references public.products(id),
  qty        numeric(14,3) not null check (qty > 0),
  unit_price numeric(18,2) not null default 0 check (unit_price >= 0),
  notes      text,
  unique (ro_id, line_no), unique (ro_id, product_id)
);
create index request_orders_customer_idx on public.request_orders(customer_id);
create index ro_items_ro_idx on public.ro_items(ro_id);
select public.attach_doc_standard('request_orders', 'RO', 'RO', 'ro');
select public.attach_child_standard('ro_items', 'ro');

create or replace function public.ro_before_item() returns trigger language plpgsql security definer set search_path = public as $$
declare v_cust uuid; v_date date; v_default numeric;
begin
  if new.unit_price = 0 then
    select customer_id, order_date into v_cust, v_date from public.request_orders where id = new.ro_id;
    select public.price_for(v_cust, new.product_id, v_date) into v_default;
    new.unit_price := coalesce(v_default, 0);
  end if;
  return new;
end $$;
create trigger ro_items_default_price before insert on public.ro_items for each row execute function public.ro_before_item();

create or replace function public.ro_recalc(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  update public.request_orders set total_amount = coalesce((select sum(qty * unit_price) from public.ro_items where ro_id = p_id), 0) where id = p_id;
end $$;
revoke all on function public.ro_recalc(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------
-- Production Order (dibuat Marketing, disetujui Owner/PPIC)
-- ---------------------------------------------------------------
create table public.production_orders (
  id          uuid primary key default gen_random_uuid(),
  doc_number  text unique,
  ro_id       uuid references public.request_orders(id),
  order_date  date not null default (now() at time zone 'Asia/Jakarta')::date,
  needed_date date,
  notes       text,
  review_note text,
  status      text not null default 'DRAFT' check (status in ('DRAFT','SUBMITTED','APPROVED','REJECTED','DONE','CANCELLED')),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id),
  deleted_at timestamptz,
  constraint prod_dates check (needed_date is null or needed_date >= order_date)
);
create table public.po_items (
  id         uuid primary key default gen_random_uuid(),
  po_id      uuid not null references public.production_orders(id),
  line_no    integer not null,
  product_id uuid not null references public.products(id),
  qty        numeric(14,3) not null check (qty > 0),
  notes      text,
  unique (po_id, line_no), unique (po_id, product_id)
);
create index production_orders_ro_idx on public.production_orders(ro_id);
create index po_items_po_idx on public.po_items(po_id);
select public.attach_doc_standard('production_orders', 'PROD', 'PROD', 'production_order');
select public.attach_child_standard('po_items', 'production_order');

create or replace function public.prod_before() returns trigger language plpgsql security definer set search_path = public as $$
declare v_st text;
begin
  if new.ro_id is not null and (tg_op = 'INSERT' or new.ro_id is distinct from old.ro_id) then
    select status into v_st from public.request_orders where id = new.ro_id;
    if v_st is distinct from 'CONFIRMED' then
      raise exception 'Production Order hanya bisa dibuat dari RO yang sudah dikonfirmasi' using errcode = '22023';
    end if;
  end if;
  return new;
end $$;
create trigger production_orders_check before insert or update on public.production_orders
  for each row execute function public.prod_before();

create or replace function public.prod_on_status() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'REJECTED' then
    new.review_note := nullif(current_setting('hmi.doc_note', true), '');
  end if;
  return new;
end $$;
create trigger production_orders_status before update of status on public.production_orders
  for each row execute function public.prod_on_status();

-- ---------------------------------------------------------------
-- Packing List (dibuat Produksi; stok keluar saat PACKED)
-- ---------------------------------------------------------------
create table public.packing_lists (
  id            uuid primary key default gen_random_uuid(),
  doc_number    text unique,
  po_id         uuid references public.production_orders(id),
  ro_id         uuid references public.request_orders(id),
  customer_id   uuid not null references public.customers(id),
  warehouse_id  uuid not null references public.warehouses(id),
  pack_date     date not null default (now() at time zone 'Asia/Jakarta')::date,
  driver_name   text,
  vehicle_plate text,
  notes         text,
  delivered_at  timestamptz,
  status        text not null default 'DRAFT' check (status in ('DRAFT','PACKED','DELIVERED','CANCELLED')),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id),
  deleted_at timestamptz
);
create table public.pl_items (
  id         uuid primary key default gen_random_uuid(),
  pl_id      uuid not null references public.packing_lists(id),
  line_no    integer not null,
  product_id uuid not null references public.products(id),
  qty        numeric(14,3) not null check (qty > 0),
  notes      text,
  unique (pl_id, line_no), unique (pl_id, product_id)
);
create index packing_lists_customer_idx on public.packing_lists(customer_id);
create index packing_lists_po_idx on public.packing_lists(po_id);
create index pl_items_pl_idx on public.pl_items(pl_id);
select public.attach_doc_standard('packing_lists', 'PL', 'PL', 'packing_list');
select public.attach_child_standard('pl_items', 'packing_list');

create or replace function public.pl_before() returns trigger language plpgsql security definer set search_path = public as $$
declare v_st text;
begin
  if new.po_id is not null and (tg_op = 'INSERT' or new.po_id is distinct from old.po_id) then
    select status into v_st from public.production_orders where id = new.po_id;
    if v_st is distinct from 'APPROVED' then
      raise exception 'Packing List hanya bisa dibuat dari Production Order yang sudah disetujui' using errcode = '22023';
    end if;
  end if;
  return new;
end $$;
create trigger packing_lists_check before insert or update on public.packing_lists
  for each row execute function public.pl_before();

create or replace function public.pl_on_status() returns trigger language plpgsql security definer set search_path = public as $$
declare i record;
begin
  if new.status = 'PACKED' and old.status = 'DRAFT' then
    if not exists (select 1 from public.pl_items where pl_id = new.id) then
      raise exception 'Packing List belum memiliki barang' using errcode = '22023';
    end if;
    for i in select * from public.pl_items where pl_id = new.id loop
      perform public.post_stock(i.product_id, new.warehouse_id, 'OUT_SALE', -i.qty, null, 'PL', new.id, 'Packing list ' || new.doc_number, new.pack_date);
    end loop;
  elsif new.status = 'DELIVERED' and old.status = 'PACKED' then
    update public.packing_lists set delivered_at = now() where id = new.id;
  elsif new.status = 'CANCELLED' and old.status = 'PACKED' then
    for i in select * from public.pl_items where pl_id = new.id loop
      perform public.post_stock(i.product_id, new.warehouse_id, 'REVERSAL_IN', i.qty, null, 'PL', new.id, 'Batal packing list ' || new.doc_number);
    end loop;
  end if;
  return null;
end $$;
create trigger packing_lists_status after update of status on public.packing_lists
  for each row execute function public.pl_on_status();

-- ---------------------------------------------------------------
-- Registry dan aturan status
-- ---------------------------------------------------------------
insert into public.doc_registry (doc_type, table_name, module, header_cols, children, after_save_fn) values
 ('RO','request_orders','ro','{customer_id,order_date,delivery_date,notes}',
  '[{"key":"items","table":"ro_items","fk":"ro_id","cols":["product_id","qty","unit_price","notes"]}]','ro_recalc'),
 ('PROD','production_orders','production_order','{ro_id,order_date,needed_date,notes}',
  '[{"key":"items","table":"po_items","fk":"po_id","cols":["product_id","qty","notes"]}]',null),
 ('PL','packing_lists','packing_list','{po_id,ro_id,customer_id,warehouse_id,pack_date,driver_name,vehicle_plate,notes}',
  '[{"key":"items","table":"pl_items","fk":"pl_id","cols":["product_id","qty","notes"]}]',null);

insert into public.doc_rules (doc_type, from_status, to_status, module, action, needs_note, label) values
 ('RO','DRAFT','CONFIRMED','ro','edit',false,'Konfirmasi RO'),
 ('RO','DRAFT','CANCELLED','ro','edit',true,'Batalkan'),
 ('RO','CONFIRMED','COMPLETED','ro','edit',false,'Tandai selesai'),
 ('RO','CONFIRMED','CANCELLED','ro','edit',true,'Batalkan'),
 ('PROD','DRAFT','SUBMITTED','production_order','edit',false,'Ajukan ke Owner'),
 ('PROD','DRAFT','CANCELLED','production_order','edit',true,'Batalkan'),
 ('PROD','SUBMITTED','APPROVED','production_order','approve',false,'Setujui'),
 ('PROD','SUBMITTED','REJECTED','production_order','approve',true,'Tolak'),
 ('PROD','SUBMITTED','CANCELLED','production_order','edit',true,'Batalkan'),
 ('PROD','APPROVED','DONE','production_order','approve',false,'Tandai selesai'),
 ('PROD','APPROVED','CANCELLED','production_order','approve',true,'Batalkan'),
 ('PL','DRAFT','PACKED','packing_list','edit',false,'Selesai dikemas (stok keluar)'),
 ('PL','DRAFT','CANCELLED','packing_list','edit',true,'Batalkan'),
 ('PL','PACKED','DELIVERED','packing_list','edit',false,'Tandai terkirim'),
 ('PL','PACKED','CANCELLED','packing_list','delete',true,'Batalkan dan kembalikan stok');


-- ===== 0007_carcass_analysis.sql =====
-- HMI Internal System - Phase 11 sampai 12: Penimbangan Karkas, Penjualan Non-Karkas, Analisa Pembelian
-- Penimbangan tidak pernah membuat CPJ otomatis.

-- ---------------------------------------------------------------
-- Penimbangan karkas
-- ---------------------------------------------------------------
create table public.carcass_weighings (
  id            uuid primary key default gen_random_uuid(),
  doc_number    text unique,
  weigh_date    date not null default (now() at time zone 'Asia/Jakarta')::date,
  cow_type_id   uuid not null references public.cow_types(id),
  cow_number    text not null check (btrim(cow_number) <> ''),
  supplier_id   uuid references public.suppliers(id),
  warehouse_id  uuid not null references public.warehouses(id),
  live_weight   numeric(12,3) not null check (live_weight > 0),
  carcass_weight numeric(12,3) not null check (carcass_weight > 0),
  notes         text,
  status        text not null default 'DRAFT' check (status in ('DRAFT','FINAL','VOID')),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id),
  deleted_at timestamptz,
  constraint cw_weights check (carcass_weight <= live_weight)
);
-- Nomor sapi (format lama dipertahankan) tidak boleh dipakai dua penimbangan aktif.
create unique index carcass_weighings_cow_uq on public.carcass_weighings (upper(btrim(cow_number)))
  where status <> 'VOID' and deleted_at is null;
create table public.cw_items (
  id                  uuid primary key default gen_random_uuid(),
  cw_id               uuid not null references public.carcass_weighings(id),
  line_no             integer not null,
  product_id          uuid references public.products(id),
  non_carcass_type_id uuid references public.non_carcass_types(id),
  weight              numeric(12,3) not null check (weight > 0),
  notes               text,
  unique (cw_id, line_no), unique (cw_id, product_id), unique (cw_id, non_carcass_type_id),
  constraint cw_items_one check ((product_id is not null) <> (non_carcass_type_id is not null))
);
create index cw_items_cw_idx on public.cw_items(cw_id);
select public.attach_doc_standard('carcass_weighings', 'CW', 'CW', 'carcass_weighing');
select public.attach_child_standard('cw_items', 'carcass_weighing');

create or replace function public.cw_on_status() returns trigger language plpgsql security definer set search_path = public as $$
declare i record; v_meat numeric;
begin
  if new.status = 'FINAL' and old.status = 'DRAFT' then
    select coalesce(sum(weight), 0) into v_meat from public.cw_items where cw_id = new.id and product_id is not null;
    if not exists (select 1 from public.cw_items where cw_id = new.id) then
      raise exception 'Penimbangan belum memiliki hasil potongan' using errcode = '22023';
    end if;
    if v_meat > new.carcass_weight then
      raise exception 'Total berat daging (% kg) melebihi berat karkas (% kg)', v_meat, new.carcass_weight using errcode = '22023';
    end if;
    for i in select * from public.cw_items where cw_id = new.id and product_id is not null loop
      perform public.post_stock(i.product_id, new.warehouse_id, 'IN_PRODUCTION', i.weight, null, 'CW', new.id,
                                'Penimbangan karkas ' || new.doc_number, new.weigh_date);
    end loop;
  elsif new.status = 'VOID' and old.status = 'FINAL' then
    if exists (select 1 from public.purchase_analyses a where a.cw_id = new.id and a.status <> 'VOID' and a.deleted_at is null) then
      raise exception 'Batalkan Analisa Pembelian terkait terlebih dahulu' using errcode = '55000';
    end if;
    for i in select * from public.cw_items where cw_id = new.id and product_id is not null loop
      perform public.post_stock(i.product_id, new.warehouse_id, 'REVERSAL_OUT', -i.weight, null, 'CW', new.id,
                                'Batal penimbangan ' || new.doc_number);
    end loop;
  end if;
  return null;
end $$;

create trigger carcass_weighings_status after update of status on public.carcass_weighings
  for each row execute function public.cw_on_status();

-- ---------------------------------------------------------------
-- Penjualan non-karkas (jeroan, kepala, kulit, dst)
-- ---------------------------------------------------------------
create table public.noncarcass_sales (
  id           uuid primary key default gen_random_uuid(),
  doc_number   text unique,
  sale_date    date not null default (now() at time zone 'Asia/Jakarta')::date,
  customer_id  uuid not null references public.customers(id),
  cw_id        uuid references public.carcass_weighings(id),
  notes        text,
  total_amount numeric(18,2) not null default 0,
  paid_amount  numeric(18,2) not null default 0 check (paid_amount >= 0),
  status       text not null default 'DRAFT' check (status in ('DRAFT','CONFIRMED','PAID','VOID')),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id),
  deleted_at timestamptz
);
create table public.ncs_items (
  id                  uuid primary key default gen_random_uuid(),
  ncs_id              uuid not null references public.noncarcass_sales(id),
  line_no             integer not null,
  non_carcass_type_id uuid not null references public.non_carcass_types(id),
  weight              numeric(12,3) not null check (weight > 0),
  unit_price          numeric(18,2) not null check (unit_price >= 0),
  unique (ncs_id, line_no)
);
create index noncarcass_sales_cw_idx on public.noncarcass_sales(cw_id);
create index ncs_items_ncs_idx on public.ncs_items(ncs_id);
select public.attach_doc_standard('noncarcass_sales', 'NCS', 'NCS', 'noncarcass_sale');
select public.attach_child_standard('ncs_items', 'noncarcass_sale');

create or replace function public.ncs_before() returns trigger language plpgsql security definer set search_path = public as $$
declare v_type text;
begin
  if tg_op = 'INSERT' or new.customer_id is distinct from old.customer_id then
    select type into v_type from public.customers where id = new.customer_id;
    if v_type is distinct from 'NON_CARCASS_BUYER' then
      raise exception 'Pembeli harus customer bertipe pembeli non-karkas' using errcode = '22023';
    end if;
  end if;
  if new.status = 'VOID' and tg_op = 'UPDATE' and old.paid_amount > 0 then
    raise exception 'Penjualan sudah ada pembayaran. Batalkan CRJ terkait lebih dulu' using errcode = '55000';
  end if;
  return new;
end $$;
create trigger noncarcass_sales_check before insert or update on public.noncarcass_sales
  for each row execute function public.ncs_before();

create or replace function public.ncs_recalc(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  update public.noncarcass_sales set total_amount = coalesce((select sum(weight * unit_price) from public.ncs_items where ncs_id = p_id), 0) where id = p_id;
end $$;
revoke all on function public.ncs_recalc(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------
-- Analisa Pembelian (dibuat setelah pemotongan; harga item disimpan saat itu)
-- ---------------------------------------------------------------
create table public.purchase_analyses (
  id             uuid primary key default gen_random_uuid(),
  doc_number     text unique,
  cw_id          uuid not null references public.carcass_weighings(id),
  analysis_date  date not null default (now() at time zone 'Asia/Jakarta')::date,
  total_purchase numeric(18,2) not null check (total_purchase >= 0),
  notes          text,
  status         text not null default 'DRAFT' check (status in ('DRAFT','FINAL','VOID')),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id),
  deleted_at timestamptz
);
create unique index purchase_analyses_cw_uq on public.purchase_analyses (cw_id) where status <> 'VOID' and deleted_at is null;
create table public.ap_items (
  id           uuid primary key default gen_random_uuid(),
  ap_id        uuid not null references public.purchase_analyses(id),
  line_no      integer not null,
  product_id   uuid not null references public.products(id),
  weight       numeric(12,3) not null check (weight > 0),
  unit_price   numeric(18,2) not null check (unit_price >= 0),
  price_source text not null default 'TYPED' check (price_source in ('TYPED','PRICING')),
  unique (ap_id, line_no), unique (ap_id, product_id)
);
create table public.ap_costs (
  id           uuid primary key default gen_random_uuid(),
  ap_id        uuid not null references public.purchase_analyses(id),
  line_no      integer not null,
  cost_type_id uuid not null references public.cost_types(id),
  amount       numeric(18,2) not null check (amount >= 0),
  note         text,
  unique (ap_id, line_no)
);
create index ap_items_ap_idx on public.ap_items(ap_id);
create index ap_costs_ap_idx on public.ap_costs(ap_id);
select public.attach_doc_standard('purchase_analyses', 'AP', 'AP', 'purchase_analysis');
select public.attach_child_standard('ap_items', 'purchase_analysis');
select public.attach_child_standard('ap_costs', 'purchase_analysis');

create or replace function public.ap_before() returns trigger language plpgsql security definer set search_path = public as $$
declare v_st text;
begin
  if tg_op = 'INSERT' or new.cw_id is distinct from old.cw_id then
    select status into v_st from public.carcass_weighings where id = new.cw_id;
    if v_st is distinct from 'FINAL' then
      raise exception 'Analisa hanya bisa dibuat setelah penimbangan karkas selesai (final)' using errcode = '22023';
    end if;
  end if;
  return new;
end $$;
create trigger purchase_analyses_check before insert or update on public.purchase_analyses
  for each row execute function public.ap_before();

create or replace function public.ap_on_final() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'FINAL' and old.status = 'DRAFT' and not exists (select 1 from public.ap_items where ap_id = new.id) then
    raise exception 'Analisa belum memiliki item produk' using errcode = '22023';
  end if;
  return new;
end $$;
create trigger purchase_analyses_final before update of status on public.purchase_analyses
  for each row execute function public.ap_on_final();

-- Hasil analisa. Berjalan dengan hak pemilik; filter izin ada di dalam view.
-- karkas % = karkas / hidup; daging % = daging / karkas; harga karkas = total pembelian / karkas.
create view public.v_purchase_analysis as
select a.id, a.doc_number, a.status, a.analysis_date, a.cw_id, a.notes, a.total_purchase,
       w.doc_number as cw_number, w.cow_number, w.live_weight, w.carcass_weight, w.supplier_id,
       round(w.carcass_weight / w.live_weight * 100, 2)                  as carcass_pct,
       coalesce(i.meat_weight, 0)                                          as meat_weight,
       round(coalesce(i.meat_weight, 0) / w.carcass_weight * 100, 2)       as meat_pct,
       round(a.total_purchase / w.carcass_weight, 2)                       as carcass_price_per_kg,
       coalesce(i.revenue, 0)                                              as revenue,
       coalesce(c.cost_total, 0)                                           as cost_total,
       coalesce(n.amount, 0)                                               as noncarcass_amount,
       coalesce(i.revenue, 0) + coalesce(n.amount, 0) - a.total_purchase - coalesce(c.cost_total, 0) as profit
  from public.purchase_analyses a
  join public.carcass_weighings w on w.id = a.cw_id
  left join (select ap_id, sum(weight) meat_weight, sum(weight * unit_price) revenue from public.ap_items group by ap_id) i on i.ap_id = a.id
  left join (select ap_id, sum(amount) cost_total from public.ap_costs group by ap_id) c on c.ap_id = a.id
  left join (select cw_id, sum(total_amount) amount from public.noncarcass_sales where status in ('CONFIRMED','PAID') and deleted_at is null group by cw_id) n on n.cw_id = a.cw_id
 where a.deleted_at is null and public.has_permission('purchase_analysis','view');
revoke all on public.v_purchase_analysis from public, anon;
grant select on public.v_purchase_analysis to authenticated;

-- ---------------------------------------------------------------
-- Registry dan aturan
-- ---------------------------------------------------------------
insert into public.doc_registry (doc_type, table_name, module, header_cols, children, after_save_fn) values
 ('CW','carcass_weighings','carcass_weighing','{weigh_date,cow_type_id,cow_number,supplier_id,warehouse_id,live_weight,carcass_weight,notes}',
  '[{"key":"items","table":"cw_items","fk":"cw_id","cols":["product_id","non_carcass_type_id","weight","notes"]}]',null),
 ('NCS','noncarcass_sales','noncarcass_sale','{sale_date,customer_id,cw_id,notes}',
  '[{"key":"items","table":"ncs_items","fk":"ncs_id","cols":["non_carcass_type_id","weight","unit_price"]}]','ncs_recalc'),
 ('AP','purchase_analyses','purchase_analysis','{cw_id,analysis_date,total_purchase,notes}',
  '[{"key":"items","table":"ap_items","fk":"ap_id","cols":["product_id","weight","unit_price","price_source"]},{"key":"costs","table":"ap_costs","fk":"ap_id","cols":["cost_type_id","amount","note"]}]',null);

insert into public.doc_rules (doc_type, from_status, to_status, module, action, needs_note, label) values
 ('CW','DRAFT','FINAL','carcass_weighing','edit',false,'Finalkan (stok daging masuk)'),
 ('CW','DRAFT','VOID','carcass_weighing','edit',true,'Batalkan'),
 ('CW','FINAL','VOID','carcass_weighing','delete',true,'Batalkan dan kembalikan stok'),
 ('NCS','DRAFT','CONFIRMED','noncarcass_sale','edit',false,'Konfirmasi penjualan'),
 ('NCS','DRAFT','VOID','noncarcass_sale','edit',true,'Batalkan'),
 ('NCS','CONFIRMED','VOID','noncarcass_sale','delete',true,'Batalkan'),
 ('AP','DRAFT','FINAL','purchase_analysis','edit',false,'Finalkan analisa'),
 ('AP','DRAFT','VOID','purchase_analysis','edit',true,'Batalkan'),
 ('AP','FINAL','VOID','purchase_analysis','delete',true,'Batalkan');


-- ===== 0008_finance.sql =====
-- HMI Internal System - Phase 13 sampai 15: Invoice, CRJ (penerimaan), CPJ (pengeluaran), Gaji
-- KOPRA hanyalah label metode bayar. Saldo piutang hanya berubah lewat posting CRJ.

-- ---------------------------------------------------------------
-- Pengaturan pajak (satu baris)
-- ---------------------------------------------------------------
create table public.tax_settings (
  id         boolean primary key default true check (id),
  label      text not null default 'PPN',
  rate       numeric(5,2) not null default 0 check (rate >= 0 and rate <= 100),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);
insert into public.tax_settings default values;
alter table public.tax_settings enable row level security;
create policy tax_settings_select on public.tax_settings for select to authenticated using (true);
grant select on public.tax_settings to authenticated;
create trigger tax_settings_audit after insert or update on public.tax_settings
  for each row execute function public.audit_row_change();

create or replace function public.set_tax_rate(p_label text, p_rate numeric)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.has_permission('master_data','edit') then
    raise exception 'Anda tidak memiliki izin mengubah pengaturan pajak' using errcode = '42501';
  end if;
  if p_rate is null or p_rate < 0 or p_rate > 100 then
    raise exception 'Tarif pajak harus antara 0 dan 100' using errcode = '22023';
  end if;
  if btrim(coalesce(p_label,'')) = '' then raise exception 'Nama pajak wajib diisi' using errcode = '22023'; end if;
  update public.tax_settings set label = btrim(p_label), rate = p_rate, updated_at = now(), updated_by = auth.uid();
end $$;
revoke all on function public.set_tax_rate(text,numeric) from public, anon;
grant execute on function public.set_tax_rate(text,numeric) to authenticated;

-- ---------------------------------------------------------------
-- Invoice
-- ---------------------------------------------------------------
create table public.invoices (
  id           uuid primary key default gen_random_uuid(),
  doc_number   text unique,
  customer_id  uuid not null references public.customers(id),
  pl_id        uuid references public.packing_lists(id),
  ro_id        uuid references public.request_orders(id),
  invoice_date date not null default (now() at time zone 'Asia/Jakarta')::date,
  due_date     date,
  tax_rate     numeric(5,2) not null default 0,
  subtotal     numeric(18,2) not null default 0,
  tax_amount   numeric(18,2) not null default 0,
  total        numeric(18,2) not null default 0,
  paid_amount  numeric(18,2) not null default 0 check (paid_amount >= 0),
  notes        text,
  status       text not null default 'DRAFT' check (status in ('DRAFT','ISSUED','PARTIAL','PAID','VOID')),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id),
  deleted_at timestamptz,
  constraint invoices_due check (due_date is null or due_date >= invoice_date),
  constraint invoices_paid check (paid_amount <= total or status = 'DRAFT')
);
create unique index invoices_pl_uq on public.invoices (pl_id) where pl_id is not null and status <> 'VOID' and deleted_at is null;
create table public.inv_items (
  id         uuid primary key default gen_random_uuid(),
  inv_id     uuid not null references public.invoices(id),
  line_no    integer not null,
  product_id uuid not null references public.products(id),
  qty        numeric(14,3) not null check (qty > 0),
  unit_price numeric(18,2) not null check (unit_price >= 0),
  unique (inv_id, line_no), unique (inv_id, product_id)
);
create index invoices_customer_idx on public.invoices(customer_id, status);
create index inv_items_inv_idx on public.inv_items(inv_id);
select public.attach_doc_standard('invoices', 'INV', 'INV', 'invoice');
select public.attach_child_standard('inv_items', 'invoice');

create or replace function public.inv_before() returns trigger language plpgsql security definer set search_path = public as $$
declare v_term int; v_pl text;
begin
  if tg_op = 'INSERT' or new.pl_id is distinct from old.pl_id then
    if new.pl_id is not null then
      select status into v_pl from public.packing_lists where id = new.pl_id;
      if v_pl is null or v_pl not in ('PACKED','DELIVERED') then
        raise exception 'Invoice hanya bisa dibuat dari Packing List yang sudah dikemas' using errcode = '22023';
      end if;
    end if;
  end if;
  if new.due_date is null then
    select payment_term_days into v_term from public.customers where id = new.customer_id;
    new.due_date := new.invoice_date + coalesce(v_term, 0);
  end if;
  if tg_op = 'UPDATE' and new.status = 'VOID' and old.paid_amount > 0 then
    raise exception 'Invoice sudah ada pembayaran. Batalkan CRJ terkait lebih dulu' using errcode = '55000';
  end if;
  if tg_op = 'UPDATE' and new.status = 'ISSUED' and old.status = 'DRAFT' then
    if not exists (select 1 from public.inv_items where inv_id = new.id) or new.total <= 0 then
      raise exception 'Invoice harus memiliki barang dan total lebih dari 0' using errcode = '22023';
    end if;
  end if;
  return new;
end $$;
create trigger invoices_check before insert or update on public.invoices
  for each row execute function public.inv_before();

create or replace function public.inv_item_default() returns trigger language plpgsql security definer set search_path = public as $$
declare v_cust uuid; v_date date; v_p numeric;
begin
  if new.unit_price = 0 then
    select customer_id, invoice_date into v_cust, v_date from public.invoices where id = new.inv_id;
    select public.price_for(v_cust, new.product_id, v_date) into v_p;
    new.unit_price := coalesce(v_p, 0);
  end if;
  return new;
end $$;
create trigger inv_items_default_price before insert on public.inv_items
  for each row execute function public.inv_item_default();

create or replace function public.inv_recalc(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare v_sub numeric; v_rate numeric; v_st text;
begin
  select status into v_st from public.invoices where id = p_id;
  if v_st = 'DRAFT' then
    select rate into v_rate from public.tax_settings;
    update public.invoices set tax_rate = v_rate where id = p_id;
  end if;
  select coalesce(sum(qty * unit_price), 0) into v_sub from public.inv_items where inv_id = p_id;
  update public.invoices
     set subtotal = v_sub, tax_amount = round(v_sub * tax_rate / 100, 2), total = v_sub + round(v_sub * tax_rate / 100, 2)
   where id = p_id;
end $$;
revoke all on function public.inv_recalc(uuid) from public, anon, authenticated;

create view public.v_receivables with (security_invoker = true) as
  select i.id, i.doc_number, i.customer_id, i.invoice_date, i.due_date, i.total, i.paid_amount,
         (i.total - i.paid_amount) as outstanding,
         greatest(0, (now() at time zone 'Asia/Jakarta')::date - i.due_date) as days_overdue,
         i.status
    from public.invoices i
   where i.status in ('ISSUED','PARTIAL') and i.deleted_at is null;
grant select on public.v_receivables to authenticated;

-- ---------------------------------------------------------------
-- CRJ: penerimaan kas
-- ---------------------------------------------------------------
create table public.cash_receipts (
  id                uuid primary key default gen_random_uuid(),
  doc_number        text unique,
  receipt_date      date not null default (now() at time zone 'Asia/Jakarta')::date,
  customer_id       uuid references public.customers(id),
  account_id        uuid not null references public.accounts(id),
  payment_method_id uuid not null references public.payment_methods(id),
  amount            numeric(18,2) not null check (amount > 0),
  reference         text,
  notes             text,
  status            text not null default 'DRAFT' check (status in ('DRAFT','POSTED','VOID')),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id),
  deleted_at timestamptz
);
create table public.crj_allocations (
  id         uuid primary key default gen_random_uuid(),
  crj_id     uuid not null references public.cash_receipts(id),
  line_no    integer not null,
  invoice_id uuid references public.invoices(id),
  ncs_id     uuid references public.noncarcass_sales(id),
  amount     numeric(18,2) not null check (amount > 0),
  unique (crj_id, line_no),
  constraint crj_alloc_one check ((invoice_id is not null) <> (ncs_id is not null))
);
create index crj_alloc_crj_idx on public.crj_allocations(crj_id);
create index crj_alloc_invoice_idx on public.crj_allocations(invoice_id);
create index crj_alloc_ncs_idx on public.crj_allocations(ncs_id);
select public.attach_doc_standard('cash_receipts', 'CRJ', 'CRJ', 'crj');
select public.attach_child_standard('crj_allocations', 'crj');

create or replace function public.crj_apply(p_id uuid, p_sign integer) returns void language plpgsql security definer set search_path = public as $$
declare a record; v_inv public.invoices%rowtype; v_ncs public.noncarcass_sales%rowtype; v_hdr public.cash_receipts%rowtype; v_new numeric;
begin
  select * into v_hdr from public.cash_receipts where id = p_id;
  for a in select * from public.crj_allocations where crj_id = p_id loop
    if a.invoice_id is not null then
      select * into v_inv from public.invoices where id = a.invoice_id for update;
      v_new := v_inv.paid_amount + p_sign * a.amount;
      if p_sign > 0 then
        if v_inv.status not in ('ISSUED','PARTIAL') then
          raise exception 'Invoice % tidak dalam status yang bisa dibayar', v_inv.doc_number using errcode = '22023';
        end if;
        if v_hdr.customer_id is not null and v_hdr.customer_id <> v_inv.customer_id then
          raise exception 'Invoice % milik customer lain', v_inv.doc_number using errcode = '22023';
        end if;
        if v_new > v_inv.total then
          raise exception 'Pembayaran melebihi sisa tagihan invoice % (sisa %)', v_inv.doc_number, v_inv.total - v_inv.paid_amount using errcode = '22023';
        end if;
      elsif v_new < 0 then
        raise exception 'Saldo invoice % tidak konsisten' , v_inv.doc_number using errcode = '55000';
      end if;
      update public.invoices
         set paid_amount = v_new,
             status = case when v_new >= total then 'PAID' when v_new > 0 then 'PARTIAL' else 'ISSUED' end
       where id = v_inv.id;
    else
      select * into v_ncs from public.noncarcass_sales where id = a.ncs_id for update;
      v_new := v_ncs.paid_amount + p_sign * a.amount;
      if p_sign > 0 then
        if v_ncs.status <> 'CONFIRMED' then
          raise exception 'Penjualan non-karkas % tidak dalam status yang bisa dibayar', v_ncs.doc_number using errcode = '22023';
        end if;
        if v_hdr.customer_id is not null and v_hdr.customer_id <> v_ncs.customer_id then
          raise exception 'Penjualan non-karkas % milik pembeli lain', v_ncs.doc_number using errcode = '22023';
        end if;
        if v_new > v_ncs.total_amount then
          raise exception 'Pembayaran melebihi tagihan penjualan non-karkas %', v_ncs.doc_number using errcode = '22023';
        end if;
      elsif v_new < 0 then
        raise exception 'Saldo penjualan non-karkas % tidak konsisten', v_ncs.doc_number using errcode = '55000';
      end if;
      update public.noncarcass_sales
         set paid_amount = v_new,
             status = case when v_new >= total_amount then 'PAID' else 'CONFIRMED' end
       where id = v_ncs.id;
    end if;
  end loop;
end $$;
revoke all on function public.crj_apply(uuid,integer) from public, anon, authenticated;

create or replace function public.crj_on_status() returns trigger language plpgsql security definer set search_path = public as $$
declare v_alloc numeric;
begin
  if new.status = 'POSTED' and old.status = 'DRAFT' then
    if not exists (select 1 from public.accounts where id = new.account_id and is_active) then
      raise exception 'Rekening/kas nonaktif' using errcode = '22023';
    end if;
    select coalesce(sum(amount), 0) into v_alloc from public.crj_allocations where crj_id = new.id;
    if v_alloc > new.amount then
      raise exception 'Total alokasi (%) melebihi jumlah penerimaan (%)', v_alloc, new.amount using errcode = '22023';
    end if;
    perform public.crj_apply(new.id, 1);
  elsif new.status = 'VOID' and old.status = 'POSTED' then
    perform public.crj_apply(new.id, -1);
  end if;
  return null;
end $$;
create trigger cash_receipts_status after update of status on public.cash_receipts
  for each row execute function public.crj_on_status();

-- ---------------------------------------------------------------
-- CPJ: pengeluaran kas (umum, pembayaran PR) dan Gaji (modul salary)
-- ---------------------------------------------------------------
create table public.cash_payments (
  id                uuid primary key default gen_random_uuid(),
  doc_number        text unique,
  pay_date          date not null default (now() at time zone 'Asia/Jakarta')::date,
  kind              text not null default 'GENERAL' check (kind in ('GENERAL','PR','SALARY')),
  supplier_id       uuid references public.suppliers(id),
  cost_type_id      uuid not null references public.cost_types(id),
  account_id        uuid not null references public.accounts(id),
  payment_method_id uuid not null references public.payment_methods(id),
  pr_id             uuid references public.purchase_requests(id),
  cw_id             uuid references public.carcass_weighings(id),
  payee_name        text,
  amount            numeric(18,2) not null check (amount > 0),
  reference         text,
  notes             text,
  status            text not null default 'DRAFT' check (status in ('DRAFT','POSTED','VOID')),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id),
  deleted_at timestamptz,
  constraint cpj_pr_kind check ((kind = 'PR') = (pr_id is not null)),
  constraint cpj_salary_payee check (kind <> 'SALARY' or btrim(coalesce(payee_name, '')) <> '')
);
create index cash_payments_pr_idx on public.cash_payments(pr_id);
create index cash_payments_date_idx on public.cash_payments(pay_date);
select public.attach_doc_standard('cash_payments', 'CPJ', 'CPJ', 'cpj');
-- Gaji hanya terlihat oleh pemegang izin salary; CPJ lain oleh pemegang izin cpj.
drop policy cash_payments_select on public.cash_payments;
create policy cash_payments_select on public.cash_payments for select to authenticated
  using (deleted_at is null and (
    (kind = 'SALARY' and public.has_permission('salary','view'))
    or (kind <> 'SALARY' and public.has_permission('cpj','view'))));

create or replace function public.cpj_before() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'GENERAL' and new.pr_id is not null then new.kind := 'PR'; end if;
  if tg_op = 'UPDATE' and new.kind is distinct from old.kind then
    raise exception 'Jenis pengeluaran tidak boleh diubah' using errcode = '55000';
  end if;
  return new;
end $$;
create trigger cash_payments_check before insert or update on public.cash_payments
  for each row execute function public.cpj_before();

create or replace function public.cpj_on_status() returns trigger language plpgsql security definer set search_path = public as $$
declare v_pr_st text;
begin
  if new.status = 'POSTED' and old.status = 'DRAFT' then
    if not exists (select 1 from public.accounts where id = new.account_id and is_active) then
      raise exception 'Rekening/kas nonaktif' using errcode = '22023';
    end if;
    if new.pr_id is not null then
      select status into v_pr_st from public.purchase_requests where id = new.pr_id for update;
      if v_pr_st not in ('RECEIVED','PAID') then
        raise exception 'PR belum berstatus barang diterima (status sekarang %)', v_pr_st using errcode = '22023';
      end if;
      if v_pr_st = 'RECEIVED' then
        update public.purchase_requests set status = 'PAID' where id = new.pr_id;
        insert into public.pr_status_history (pr_id, from_status, to_status, note, changed_by)
        values (new.pr_id, 'RECEIVED', 'PAID', 'Dibayar lewat ' || new.doc_number, auth.uid());
      end if;
    end if;
  elsif new.status = 'VOID' and old.status = 'POSTED' and new.pr_id is not null then
    select status into v_pr_st from public.purchase_requests where id = new.pr_id for update;
    if v_pr_st = 'CLOSED' then
      raise exception 'PR sudah ditutup, pembayaran tidak bisa dibatalkan' using errcode = '55000';
    end if;
    if v_pr_st = 'PAID' and not exists (
         select 1 from public.cash_payments where pr_id = new.pr_id and status = 'POSTED' and id <> new.id) then
      update public.purchase_requests set status = 'RECEIVED' where id = new.pr_id;
      insert into public.pr_status_history (pr_id, from_status, to_status, note, changed_by)
      values (new.pr_id, 'PAID', 'RECEIVED', 'Pembayaran ' || new.doc_number || ' dibatalkan', auth.uid());
    end if;
  end if;
  return null;
end $$;
create trigger cash_payments_status after update of status on public.cash_payments
  for each row execute function public.cpj_on_status();

create or replace function public.pr_close(p_id uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_st text;
begin
  if not public.has_permission('cpj','edit') then
    raise exception 'Anda tidak memiliki izin menutup PR' using errcode = '42501';
  end if;
  select status into v_st from public.purchase_requests where id = p_id and deleted_at is null for update;
  if v_st is null then raise exception 'Purchase Request tidak ditemukan' using errcode = 'P0002'; end if;
  if v_st <> 'PAID' then raise exception 'Hanya PR yang sudah dibayar yang bisa ditutup' using errcode = '55000'; end if;
  update public.purchase_requests set status = 'CLOSED' where id = p_id;
  insert into public.pr_status_history (pr_id, from_status, to_status, note, changed_by)
  values (p_id, 'PAID', 'CLOSED', nullif(btrim(coalesce(p_note,'')), ''), auth.uid());
end $$;
revoke all on function public.pr_close(uuid,text) from public, anon;
grant execute on function public.pr_close(uuid,text) to authenticated;

-- ---------------------------------------------------------------
-- Registry dan aturan
-- ---------------------------------------------------------------
insert into public.doc_registry (doc_type, table_name, module, header_cols, fixed, children, after_save_fn) values
 ('INV','invoices','invoice','{customer_id,pl_id,ro_id,invoice_date,due_date,notes}','{}',
  '[{"key":"items","table":"inv_items","fk":"inv_id","cols":["product_id","qty","unit_price"]}]','inv_recalc'),
 ('CRJ','cash_receipts','crj','{receipt_date,customer_id,account_id,payment_method_id,amount,reference,notes}','{}',
  '[{"key":"items","table":"crj_allocations","fk":"crj_id","cols":["invoice_id","ncs_id","amount"]}]',null),
 ('CPJ','cash_payments','cpj','{pay_date,supplier_id,cost_type_id,account_id,payment_method_id,pr_id,cw_id,amount,reference,notes}','{}','[]',null),
 ('SAL','cash_payments','salary','{pay_date,cost_type_id,account_id,payment_method_id,payee_name,amount,reference,notes}','{"kind":"SALARY"}','[]',null);

insert into public.doc_rules (doc_type, from_status, to_status, module, action, needs_note, label) values
 ('INV','DRAFT','ISSUED','invoice','edit',false,'Terbitkan invoice'),
 ('INV','DRAFT','VOID','invoice','edit',true,'Batalkan'),
 ('INV','ISSUED','VOID','invoice','delete',true,'Batalkan invoice'),
 ('CRJ','DRAFT','POSTED','crj','edit',false,'Posting penerimaan'),
 ('CRJ','DRAFT','VOID','crj','edit',true,'Batalkan'),
 ('CRJ','POSTED','VOID','crj','delete',true,'Batalkan posting'),
 ('CPJ','DRAFT','POSTED','cpj','edit',false,'Posting pengeluaran'),
 ('CPJ','DRAFT','VOID','cpj','edit',true,'Batalkan'),
 ('CPJ','POSTED','VOID','cpj','delete',true,'Batalkan posting'),
 ('SAL','DRAFT','POSTED','salary','edit',false,'Posting gaji'),
 ('SAL','DRAFT','VOID','salary','edit',true,'Batalkan'),
 ('SAL','POSTED','VOID','salary','delete',true,'Batalkan posting');

insert into public.cost_types (code, name) values ('GAJI','Gaji') on conflict do nothing;


-- ===== 0009_dashboard.sql =====
-- HMI Internal System - Phase 16: ringkasan dashboard.
-- Fungsi berjalan dengan hak pemanggil (RLS tetap berlaku). Angka yang tidak boleh
-- dilihat user dikembalikan null, bukan 0, supaya tidak menyesatkan.
create or replace function public.dashboard_summary()
returns jsonb
language plpgsql stable
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_month date := date_trunc('month', now() at time zone 'Asia/Jakarta')::date;
  out jsonb := '{}'::jsonb;
  v_n numeric; v_m numeric;
begin
  if public.has_permission('stock','view') then
    select count(*) into v_n from public.v_stock_summary where is_low;
    out := out || jsonb_build_object('low_stock', v_n);
  end if;
  if public.has_permission('purchase_request','approve') then
    select count(*) into v_n from public.purchase_requests where status in ('SUBMITTED','UNDER_REVIEW') and deleted_at is null;
    out := out || jsonb_build_object('pr_waiting', v_n);
  end if;
  if public.has_permission('production_order','approve') then
    select count(*) into v_n from public.production_orders where status = 'SUBMITTED' and deleted_at is null;
    out := out || jsonb_build_object('prod_waiting', v_n);
  end if;
  if public.has_permission('ro','view') then
    select count(*) into v_n from public.request_orders where status = 'CONFIRMED' and deleted_at is null;
    out := out || jsonb_build_object('ro_open', v_n);
  end if;
  if public.has_permission('packing_list','view') then
    select count(*) into v_n from public.packing_lists where status = 'PACKED' and deleted_at is null;
    out := out || jsonb_build_object('pl_on_the_way', v_n);
  end if;
  if public.has_permission('invoice','view') then
    select coalesce(sum(outstanding),0), coalesce(sum(outstanding) filter (where days_overdue > 0),0)
      into v_n, v_m from public.v_receivables;
    out := out || jsonb_build_object('receivable_total', v_n, 'receivable_overdue', v_m);
  end if;
  if public.has_permission('crj','view') then
    select coalesce(sum(amount),0) into v_n from public.cash_receipts
     where status = 'POSTED' and deleted_at is null and receipt_date >= v_month and receipt_date <= v_today;
    out := out || jsonb_build_object('cash_in_month', v_n);
  end if;
  if public.has_permission('cpj','view') then
    select coalesce(sum(amount),0) into v_n from public.cash_payments
     where status = 'POSTED' and deleted_at is null and pay_date >= v_month and pay_date <= v_today;
    out := out || jsonb_build_object('cash_out_month', v_n);
  end if;
  return out;
end;
$$;
revoke all on function public.dashboard_summary() from public, anon;
grant execute on function public.dashboard_summary() to authenticated;


-- ===== 0010_rbac_matrix.sql =====
-- Fase revisi: matriks RBAC sesuai gambar Owner, Owner boleh mengubah dokumen final.
-- Menggantikan izin seed lama untuk peran non-Owner. Owner (superuser) tidak memakai baris role_permissions.

create or replace function public.is_owner() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select r.is_superuser from public.user_profiles p join public.roles r on r.id = p.role_id
                    where p.id = auth.uid() and p.is_active and r.is_active), false)
$$;
revoke all on function public.is_owner() from public, anon;
grant execute on function public.is_owner() to authenticated;

-- Hapus izin lama non-Owner pada modul yang diatur matriks
delete from public.role_permissions rp using public.roles r, public.permissions p
 where rp.role_id = r.id and rp.permission_id = p.id and r.code <> 'OWNER'
   and p.module in ('customer','ro','production_order','packing_list','carcass_weighing','purchase_request','supplier','pricing','purchase_analysis','stock','stock_opname','noncarcass_sale','invoice','report');

create or replace function pg_temp.g(p_role text, p_module text, p_actions text[]) returns void language sql as $f$
  insert into public.role_permissions (role_id, permission_id) select r.id, p.id from public.roles r, public.permissions p
   where r.code = p_role and p.module = p_module and p.action = any(p_actions) on conflict do nothing;
$f$;

select pg_temp.g('MARKETING','customer','{view,create,edit}');
select pg_temp.g('ACCOUNTING','customer','{view}');
select pg_temp.g('MARKETING','ro','{view,create,edit}');
select pg_temp.g('ACCOUNTING','ro','{view}');
select pg_temp.g('PRODUKSI','ro','{view}');
select pg_temp.g('MARKETING','production_order','{view,create,edit}');
select pg_temp.g('ACCOUNTING','production_order','{view}');
select pg_temp.g('PRODUKSI','production_order','{view,edit}');
select pg_temp.g('KASIR','production_order','{view}');
select pg_temp.g('MARKETING','packing_list','{view}');
select pg_temp.g('ACCOUNTING','packing_list','{view}');
select pg_temp.g('PRODUKSI','packing_list','{view,create,edit}');
select pg_temp.g('KASIR','packing_list','{view}');
select pg_temp.g('PURCHASING','carcass_weighing','{view}');
select pg_temp.g('ACCOUNTING','carcass_weighing','{view}');
select pg_temp.g('PRODUKSI','carcass_weighing','{view,create,edit}');
select pg_temp.g('KASIR','carcass_weighing','{view}');
select pg_temp.g('MARKETING','purchase_request','{view,create}');
select pg_temp.g('PURCHASING','purchase_request','{view,create,edit}');
select pg_temp.g('ACCOUNTING','purchase_request','{view}');
select pg_temp.g('PRODUKSI','purchase_request','{view,create}');
select pg_temp.g('KASIR','purchase_request','{view,create}');
select pg_temp.g('PURCHASING','supplier','{view,create,edit}');
select pg_temp.g('ACCOUNTING','supplier','{view}');
select pg_temp.g('MARKETING','pricing','{view}');
select pg_temp.g('PURCHASING','pricing','{view,create,edit}');
select pg_temp.g('ACCOUNTING','pricing','{view}');
select pg_temp.g('PRODUKSI','pricing','{view}');
select pg_temp.g('KASIR','pricing','{view}');
select pg_temp.g('PURCHASING','purchase_analysis','{view,create,edit,export}');
select pg_temp.g('ACCOUNTING','purchase_analysis','{view}');
select pg_temp.g('MARKETING','stock','{view}');
select pg_temp.g('MARKETING','stock_opname','{view}');
select pg_temp.g('PURCHASING','stock','{view}');
select pg_temp.g('PURCHASING','stock_opname','{view}');
select pg_temp.g('ACCOUNTING','stock','{view}');
select pg_temp.g('ACCOUNTING','stock_opname','{view}');
select pg_temp.g('PRODUKSI','stock','{view,create,edit}');
select pg_temp.g('PRODUKSI','stock_opname','{view,create,edit}');
select pg_temp.g('KASIR','stock','{view,create,edit}');
select pg_temp.g('KASIR','stock_opname','{view,create,edit}');
select pg_temp.g('MARKETING','noncarcass_sale','{view}');
select pg_temp.g('ACCOUNTING','noncarcass_sale','{view}');
select pg_temp.g('PRODUKSI','noncarcass_sale','{view}');
select pg_temp.g('KASIR','noncarcass_sale','{view,create,edit}');
select pg_temp.g('PURCHASING','invoice','{view}');
select pg_temp.g('ACCOUNTING','invoice','{view,create,edit,delete,approve,export}');
select pg_temp.g('MARKETING','report','{view}');
select pg_temp.g('PURCHASING','report','{view}');
select pg_temp.g('ACCOUNTING','report','{view,export}');

-- Persetujuan PR hanya Owner (kolom Approve di matriks)
delete from public.role_permissions rp using public.roles r, public.permissions p
 where rp.role_id=r.id and rp.permission_id=p.id and r.code<>'OWNER' and p.action='approve' and p.module='purchase_request';

-- Owner boleh mengubah dokumen berstatus final (kecuali dibatalkan)
create or replace function public.save_doc(p_type text, p_id uuid, p_header jsonb, p_children jsonb default '{}'::jsonb)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  r       public.doc_registry%rowtype;
  v_id    uuid := p_id;
  v_hdr   jsonb;
  v_cols  text;
  v_status text;
  ch      jsonb;
  v_ccols text;
  v_n     integer;
begin
  select * into r from public.doc_registry where doc_type = p_type;
  if not found then
    raise exception 'Jenis dokumen tidak dikenal' using errcode = '22023';
  end if;
  if not public.has_permission(r.module, case when p_id is null then 'create' else 'edit' end) then
    raise exception 'Anda tidak memiliki izin untuk menyimpan dokumen ini' using errcode = '42501';
  end if;

  v_hdr := coalesce(p_header, '{}'::jsonb) || r.fixed;
  select string_agg(quote_ident(c), ',') into v_cols
    from unnest(r.header_cols || array(select jsonb_object_keys(r.fixed))) c where v_hdr ? c;
  if v_cols is null then
    raise exception 'Isian dokumen kosong' using errcode = '22023';
  end if;

  if v_id is null then
    execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1) returning id',
                   r.table_name, v_cols, v_cols, r.table_name)
      into v_id using v_hdr;
  else
    execute format('select status from public.%I where id = $1 and deleted_at is null for update', r.table_name)
      into v_status using v_id;
    if v_status is null then
      raise exception 'Dokumen tidak ditemukan' using errcode = 'P0002';
    end if;
    if not (v_status = any (r.editable_statuses) or (public.is_owner() and p_type = 'PROD' and v_status <> 'CANCELLED')) then
      raise exception 'Dokumen berstatus % tidak bisa diubah lagi', v_status using errcode = '55000';
    end if;
    execute format('update public.%I set (%s) = (select %s from jsonb_populate_record(null::public.%I, $2)) where id = $1',
                   r.table_name, v_cols, v_cols, r.table_name)
      using v_id, v_hdr;
  end if;

  for ch in select * from jsonb_array_elements(r.children) loop
    if p_children ? (ch->>'key') then
      select string_agg(quote_ident(c), ',') into v_ccols from jsonb_array_elements_text(ch->'cols') c;
      execute format('delete from public.%I where %I = $1', ch->>'table', ch->>'fk') using v_id;
      execute format(
        'insert into public.%I (%I, line_no, %s) select $1, e.ord, %s from jsonb_array_elements($2) with ordinality e(j, ord), lateral jsonb_populate_record(null::public.%I, e.j) p',
        ch->>'table', ch->>'fk', v_ccols,
        (select string_agg('p.' || quote_ident(c), ',') from jsonb_array_elements_text(ch->'cols') c),
        ch->>'table')
        using v_id, p_children->(ch->>'key');
    end if;
  end loop;

  if r.after_save_fn is not null then
    execute format('select public.%I($1)', r.after_save_fn) using v_id;
  end if;

  if p_id is null then
    insert into public.doc_status_history (doc_type, doc_id, from_status, to_status, changed_by)
    values (p_type, v_id, null, 'DRAFT', auth.uid());
  end if;
  return v_id;
end;
$$;


-- ===== 0011_fast_permissions.sql =====
-- Percepat my_permissions(): sebelumnya memanggil has_permission() untuk setiap
-- baris izin (sekitar 150 kali, tiap panggilan beberapa query) di setiap halaman.
-- Versi ini satu query set-based dengan aturan yang sama persis:
--   1) override per user menang, 2) superuser lolos, 3) selain itu cek role_permissions.
-- User atau role nonaktif tidak mendapat izin apa pun.
create or replace function public.my_permissions()
returns table (module text, action text)
language sql stable security definer
set search_path = public
as $$
  with me as (
    select r.id as role_id, r.is_superuser
      from public.user_profiles p
      join public.roles r on r.id = p.role_id
     where p.id = auth.uid() and p.is_active and r.is_active
  )
  select p.module, p.action
    from me
   cross join public.permissions p
    left join public.user_permission_overrides o
           on o.user_id = auth.uid() and o.permission_id = p.id
   where case
           when o.permission_id is not null then o.is_granted
           when me.is_superuser then true
           else exists (
             select 1 from public.role_permissions rp
              where rp.role_id = me.role_id and rp.permission_id = p.id
           )
         end;
$$;

revoke all on function public.my_permissions() from public, anon;
grant execute on function public.my_permissions() to authenticated;


-- ===== 0012_qurban.sql =====
-- HMI Hub - Qurban Cerdas.
-- Alur: timbang sapi -> proforma -> (diskon Owner) -> invoice -> lunas -> surat perjanjian (SP-JB, SP-PL).
-- Perawatan dibayar lunas di awal (tarif flat kelas saat beli) atau dicicil per bulan (tarif mengikuti
-- kelas bobot timbang terakhir). QC Report bulanan per pelanggan.
-- Semua perubahan lewat fungsi SECURITY DEFINER yang memeriksa izin dan urutan status.
-- Harga tidak pernah ditimpa: tabel tarif memakai tanggal berlaku, dan setiap pesanan/tagihan menyimpan salinan harganya.

-- ---------------------------------------------------------------
-- Izin baru
-- ---------------------------------------------------------------
insert into public.permissions (module, action)
select m.module, a.action
from unnest(array['qurban','qc_report']) as m(module)
cross join unnest(array['view','create','edit','delete','approve','export']) as a(action)
on conflict (module, action) do nothing;

create or replace function pg_temp.g(p_role text, p_module text, p_actions text[]) returns void language sql as $f$
  insert into public.role_permissions (role_id, permission_id) select r.id, p.id from public.roles r, public.permissions p
   where r.code = p_role and p.module = p_module and p.action = any(p_actions) on conflict do nothing;
$f$;
-- Nilai awal yang bisa diubah Owner di menu Role dan Izin.
select pg_temp.g('MARKETING','qurban','{view,create,edit,export}');
select pg_temp.g('MARKETING','qc_report','{view}');
select pg_temp.g('ACCOUNTING','qurban','{view,edit,export}');
select pg_temp.g('ACCOUNTING','qc_report','{view}');
select pg_temp.g('PRODUKSI','qc_report','{view,create}');

-- ---------------------------------------------------------------
-- Pengaturan dan tarif
-- ---------------------------------------------------------------
create table public.qurban_settings (
  key        text primary key,
  value      text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);
insert into public.qurban_settings (key, value) values
  ('care_end', '2027-05-17'),         -- akhir masa perawatan
  ('notice_deadline', '2027-04-17');  -- batas pemilik memberi tahu pilihan (30 hari sebelum Idul Adha)

create table public.qurban_price_classes (
  id             uuid primary key default gen_random_uuid(),
  min_kg         numeric(8,2) not null check (min_kg >= 0),
  max_kg         numeric(8,2),  -- null = tanpa batas atas
  buy_price      numeric(18,2) not null check (buy_price >= 0),      -- per Kg
  care_price     numeric(18,2) not null check (care_price >= 0),     -- per hari
  buyback_price  numeric(18,2) not null check (buyback_price >= 0),  -- per Kg
  effective_from date not null,
  created_at     timestamptz not null default now(),
  created_by     uuid references auth.users(id),
  updated_at     timestamptz not null default now(),
  updated_by     uuid references auth.users(id),
  unique (min_kg, effective_from),
  check (max_kg is null or max_kg >= min_kg)
);
insert into public.qurban_price_classes (min_kg, max_kg, buy_price, care_price, buyback_price, effective_from) values
  (350, 599, 58000, 46000, 63000, '2026-01-01'),
  (600, 699, 63000, 53000, 68000, '2026-01-01'),
  (700, 799, 68000, 58000, 73000, '2026-01-01'),
  (800, 899, 75000, 63000, 80000, '2026-01-01'),
  (900, null, 80000, 70000, 95000, '2026-01-01');

-- ---------------------------------------------------------------
-- Pesanan, penimbangan, tagihan, QC, data pembeli
-- ---------------------------------------------------------------
create table public.qurban_orders (
  id             uuid primary key default gen_random_uuid(),
  cow_no         text not null check (btrim(cow_no) <> ''),   -- nomor sapi boleh ganda
  customer_nick  text not null check (btrim(customer_nick) <> ''),
  start_date     date not null,
  initial_weight numeric(8,2) not null check (initial_weight > 0),
  pay_mode       text not null check (pay_mode in ('FULL','MONTHLY')),
  class_min      numeric(8,2) not null,
  class_max      numeric(8,2),
  buy_price      numeric(18,2) not null,
  care_price     numeric(18,2) not null,
  buyback_price  numeric(18,2) not null,
  discount       numeric(18,2) not null default 0 check (discount >= 0),
  down_payment   numeric(18,2) not null default 0 check (down_payment >= 0),
  status         text not null default 'PROFORMA' check (status in ('PROFORMA','INVOICE','PAID','CANCELLED')),
  pro_no         text unique,
  pro_date       date,
  inv_no         text unique,
  inv_date       date,
  due_date       date,
  paid_at        timestamptz,
  owner_choice   text check (owner_choice in ('SELF','SELL_OUT','SELL_BACK')),
  choice_date    date,
  cancel_reason  text,
  created_at     timestamptz not null default now(),
  created_by     uuid references auth.users(id),
  updated_at     timestamptz not null default now(),
  updated_by     uuid references auth.users(id),
  deleted_at     timestamptz
);
create index qurban_orders_status_idx   on public.qurban_orders(status);
create index qurban_orders_customer_idx on public.qurban_orders(customer_nick);

create table public.qurban_weighings (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.qurban_orders(id),
  weigh_date  date not null,
  weight      numeric(8,2) not null check (weight > 0),
  note        text,
  created_at  timestamptz not null default now(),
  created_by  uuid references auth.users(id),
  updated_at  timestamptz not null default now(),
  updated_by  uuid references auth.users(id)
);
create index qurban_weighings_order_idx on public.qurban_weighings(order_id, weigh_date);

create table public.qurban_bills (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.qurban_orders(id),
  bill_no      text not null unique,
  ym           text not null check (ym ~ '^[0-9]{4}-[0-9]{2}$'),
  days         integer not null check (days > 0),
  rate         numeric(18,2) not null check (rate >= 0),
  basis_weight numeric(8,2) not null,
  bill_date    date not null,
  due_date     date not null,
  status       text not null default 'ISSUED' check (status in ('ISSUED','PAID','CANCELLED')),
  paid_at      timestamptz,
  created_at   timestamptz not null default now(),
  created_by   uuid references auth.users(id),
  updated_at   timestamptz not null default now(),
  updated_by   uuid references auth.users(id)
);
create unique index qurban_bills_month_uniq on public.qurban_bills(order_id, ym) where status <> 'CANCELLED';

create table public.qurban_qc_reports (
  id             uuid primary key default gen_random_uuid(),
  qc_no          text not null unique,
  ym             text not null check (ym ~ '^[0-9]{4}-[0-9]{2}$'),
  customer_nick  text not null,
  publish_date   date not null,
  note           text not null default 'Sapi dalam keadaan sehat.',
  ppic_name      text not null default 'Maheswara Aulia Khrisna',
  qc_name        text not null default 'Johan Luthfi Frambudi',
  director_name  text not null default 'Misbahudin',
  created_at     timestamptz not null default now(),
  created_by     uuid references auth.users(id),
  updated_at     timestamptz not null default now(),
  updated_by     uuid references auth.users(id),
  unique (ym, customer_nick)
);

-- Data pembeli (KTP dst) hanya diisi saat membuat Surat Perjanjian dan hanya terbaca
-- oleh yang berhak membuat surat. Tabel terpisah agar bisa dibatasi sendiri.
create table public.qurban_buyer_details (
  order_id   uuid primary key references public.qurban_orders(id),
  full_name  text not null check (btrim(full_name) <> ''),
  nik        text not null check (nik ~ '^[0-9]{16}$'),
  address    text not null check (btrim(address) <> ''),
  phone      text,
  cow_type   text not null check (btrim(cow_type) <> ''),
  sp_date    date not null,
  sp_seq     integer not null,
  sp_jb_no   text not null unique,
  sp_pl_no   text not null unique,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create table public.qurban_sequences (
  kind        text not null,
  ym          text not null,
  last_number integer not null default 0,
  primary key (kind, ym)
);
alter table public.qurban_sequences enable row level security;  -- tanpa policy: hanya fungsi

-- Pengisian pembuat/pengubah dan jejak audit
do $$
declare t text;
begin
  foreach t in array array['qurban_price_classes','qurban_orders','qurban_weighings','qurban_bills','qurban_qc_reports','qurban_buyer_details'] loop
    execute format('create trigger %I before insert or update on public.%I
                    for each row execute function public.set_actor_columns()', t || '_actor', t);
    execute format('create trigger %I after insert or update or delete on public.%I
                    for each row execute function public.audit_row_change()', t || '_audit', t);
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;
alter table public.qurban_settings enable row level security;

-- ---------------------------------------------------------------
-- RLS: hanya baca langsung. Semua penulisan lewat fungsi di bawah.
-- ---------------------------------------------------------------
create policy qurban_settings_select on public.qurban_settings for select to authenticated
  using (public.has_permission('qurban','view') or public.has_permission('qc_report','view'));
create policy qurban_price_classes_select on public.qurban_price_classes for select to authenticated
  using (public.has_permission('qurban','view') or public.has_permission('qc_report','view'));
create policy qurban_orders_select on public.qurban_orders for select to authenticated
  using (deleted_at is null and (public.has_permission('qurban','view') or public.has_permission('qc_report','view')));
create policy qurban_weighings_select on public.qurban_weighings for select to authenticated
  using (public.has_permission('qurban','view') or public.has_permission('qc_report','view'));
create policy qurban_bills_select on public.qurban_bills for select to authenticated
  using (public.has_permission('qurban','view'));
create policy qurban_qc_reports_select on public.qurban_qc_reports for select to authenticated
  using (public.has_permission('qc_report','view') or public.has_permission('qurban','view'));
create policy qurban_buyer_details_select on public.qurban_buyer_details for select to authenticated
  using (public.has_permission('qurban','create') or public.has_permission('qurban','edit'));

grant select on public.qurban_settings, public.qurban_price_classes, public.qurban_orders,
  public.qurban_weighings, public.qurban_bills, public.qurban_qc_reports, public.qurban_buyer_details to authenticated;

-- ---------------------------------------------------------------
-- Fungsi bantu
-- ---------------------------------------------------------------
create or replace function public.qurban_today() returns date
language sql stable as $$ select (now() at time zone 'Asia/Jakarta')::date $$;

create or replace function public.qurban_roman(m integer) returns text
language sql immutable as $$ select (array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'])[m] $$;

create or replace function public.qurban_month_name(p_ym text) returns text
language sql immutable as $$
  select (array['Januari','Februari','Maret','April','Mei','Juni','Juli','Agustus','September','Oktober','November','Desember'])
         [substr(p_ym,6,2)::integer] || ' ' || substr(p_ym,1,4)
$$;

create or replace function public.qurban_setting(p_key text) returns text
language sql stable security definer set search_path = public as $$
  select value from public.qurban_settings where key = p_key
$$;
revoke all on function public.qurban_setting(text) from public, anon;
grant execute on function public.qurban_setting(text) to authenticated;

-- Jumlah hari perawatan pada satu bulan (hari mulai dihitung, hari terakhir dihitung)
create or replace function public.qurban_days(p_ym text, p_start date, p_end date) returns integer
language plpgsql immutable as $$
declare
  v_first date := (p_ym || '-01')::date;
  v_last  date := ((p_ym || '-01')::date + interval '1 month - 1 day')::date;
begin
  return greatest(0, (least(v_last, p_end) - greatest(v_first, p_start)) + 1);
end $$;

-- Nomor urut per jenis dan bulan (dipakai PRO, INV, SP, QC)
create or replace function public.qurban_next(p_kind text, p_date date) returns integer
language plpgsql security definer set search_path = public as $$
declare v_n integer;
begin
  insert into public.qurban_sequences as s (kind, ym, last_number)
  values (p_kind, to_char(p_date, 'YYYY-MM'), 1)
  on conflict (kind, ym) do update set last_number = s.last_number + 1
  returning last_number into v_n;
  return v_n;
end $$;
revoke all on function public.qurban_next(text, date) from public, anon, authenticated;

-- Kelas harga untuk bobot tertentu pada tanggal tertentu (tarif terbaru yang sudah berlaku)
create or replace function public.qurban_class_at(p_weight numeric, p_on date)
returns public.qurban_price_classes
language plpgsql stable security definer set search_path = public as $$
declare v public.qurban_price_classes;
begin
  select c.* into v
    from public.qurban_price_classes c
   where c.min_kg <= p_weight
     and c.effective_from = (select max(c2.effective_from) from public.qurban_price_classes c2
                              where c2.min_kg = c.min_kg and c2.effective_from <= p_on)
   order by c.min_kg desc
   limit 1;
  return v;
end $$;
revoke all on function public.qurban_class_at(numeric, date) from public, anon;
grant execute on function public.qurban_class_at(numeric, date) to authenticated;

-- Baris invoice/proforma sebuah pesanan (satu sumber kebenaran untuk tampilan dan unduhan)
create or replace function public.qurban_order_lines(p_id uuid)
returns table (line_no integer, descr text, qty numeric, unit text, price numeric)
language sql stable set search_path = public as $$
  with o as (select * from public.qurban_orders where id = p_id),
  e as (select public.qurban_setting('care_end')::date as d),
  months as (
    select to_char(m, 'YYYY-MM') as ym, (row_number() over (order by m))::integer as rn
      from o, e,
           generate_series(date_trunc('month', o.start_date::timestamp), date_trunc('month', e.d::timestamp), interval '1 month') as m
     where o.pay_mode = 'FULL' or m = date_trunc('month', o.start_date::timestamp)
  )
  select 1, 'Sapi Nomor ' || o.cow_no, o.initial_weight, 'Kg'::text, o.buy_price from o
  union all
  select months.rn + 1, 'Perawatan Bulan ' || public.qurban_month_name(months.ym),
         public.qurban_days(months.ym, o.start_date, e.d)::numeric, 'Hari'::text, o.care_price
    from o, e, months
   order by 1
$$;

create view public.v_qurban_orders with (security_invoker = true) as
select o.*,
       t.total,
       (t.total - o.discount - o.down_payment) as due_amount,
       coalesce((select w.weight from public.qurban_weighings w where w.order_id = o.id order by w.weigh_date desc, w.created_at desc limit 1), o.initial_weight) as last_weight,
       (select count(*) from public.qurban_bills b where b.order_id = o.id and b.status <> 'CANCELLED') as bill_count
  from public.qurban_orders o
 cross join lateral (select coalesce(sum(l.qty * l.price), 0) as total from public.qurban_order_lines(o.id) l) t
 where o.deleted_at is null;
grant select on public.v_qurban_orders to authenticated;

-- ---------------------------------------------------------------
-- Fungsi aksi
-- ---------------------------------------------------------------
create or replace function public.qurban_need(p_module text, p_action text, p_msg text) returns void
language plpgsql stable as $$
begin
  if not public.has_permission(p_module, p_action) then
    raise exception '%', p_msg using errcode = '42501';
  end if;
end $$;

create or replace function public.qurban_create_order(p_cow text, p_nick text, p_weight numeric, p_start date, p_mode text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_today date := public.qurban_today();
  v_cls   public.qurban_price_classes;
  v_id    uuid;
  v_end   date := public.qurban_setting('care_end')::date;
begin
  perform public.qurban_need('qurban','create','Anda tidak memiliki izin membuat pesanan Qurban');
  if btrim(coalesce(p_cow,'')) = '' or btrim(coalesce(p_nick,'')) = '' then
    raise exception 'Nama pelanggan dan nomor sapi wajib diisi' using errcode = '22023';
  end if;
  if p_mode not in ('FULL','MONTHLY') then
    raise exception 'Cara pembayaran perawatan tidak valid' using errcode = '22023';
  end if;
  if p_weight is null or p_weight <= 0 then
    raise exception 'Hasil timbang wajib diisi' using errcode = '22023';
  end if;
  if p_start is null or p_start > v_end then
    raise exception 'Tanggal mulai pemeliharaan tidak valid atau melewati akhir masa perawatan' using errcode = '22023';
  end if;
  v_cls := public.qurban_class_at(p_weight, v_today);
  if v_cls.id is null then
    raise exception 'Bobot di bawah 350 Kg tidak ada di daftar harga Qurban Cerdas' using errcode = '22023';
  end if;

  insert into public.qurban_orders (cow_no, customer_nick, start_date, initial_weight, pay_mode,
         class_min, class_max, buy_price, care_price, buyback_price, pro_no, pro_date)
  values (btrim(p_cow), btrim(p_nick), p_start, p_weight, p_mode,
          v_cls.min_kg, v_cls.max_kg, v_cls.buy_price, v_cls.care_price, v_cls.buyback_price,
          'PRO-INV-' || lpad(public.qurban_next('PRO', v_today)::text, 3, '0') || '-' ||
            public.qurban_roman(extract(month from v_today)::integer) || '-' || to_char(v_today, 'YY'),
          v_today)
  returning id into v_id;

  insert into public.qurban_weighings (order_id, weigh_date, weight, note) values (v_id, p_start, p_weight, 'Timbang awal');
  return v_id;
end $$;

create or replace function public.qurban_set_discount(p_id uuid, p_amount numeric)
returns void
language plpgsql security definer set search_path = public as $$
declare v public.qurban_orders%rowtype; v_total numeric;
begin
  perform public.qurban_need('qurban','approve','Diskon hanya boleh diisi oleh Owner');
  select * into v from public.qurban_orders where id = p_id and deleted_at is null for update;
  if not found then raise exception 'Pesanan tidak ditemukan' using errcode = 'P0002'; end if;
  if v.status <> 'PROFORMA' then
    raise exception 'Diskon hanya bisa diubah selama masih proforma' using errcode = '55000';
  end if;
  select coalesce(sum(qty * price), 0) into v_total from public.qurban_order_lines(p_id);
  if p_amount is null or p_amount < 0 or p_amount > v_total then
    raise exception 'Diskon tidak boleh negatif atau melebihi total' using errcode = '22023';
  end if;
  update public.qurban_orders set discount = p_amount where id = p_id;
end $$;

create or replace function public.qurban_issue_invoice(p_id uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare v public.qurban_orders%rowtype; v_today date := public.qurban_today(); v_no text;
begin
  perform public.qurban_need('qurban','edit','Anda tidak memiliki izin menerbitkan invoice');
  select * into v from public.qurban_orders where id = p_id and deleted_at is null for update;
  if not found then raise exception 'Pesanan tidak ditemukan' using errcode = 'P0002'; end if;
  if v.status <> 'PROFORMA' then
    raise exception 'Invoice hanya bisa diterbitkan dari proforma' using errcode = '55000';
  end if;
  v_no := 'INV-' || lpad(public.qurban_next('INV', v_today)::text, 3, '0') || '-' ||
          public.qurban_roman(extract(month from v_today)::integer) || '-' || to_char(v_today, 'YY');
  update public.qurban_orders
     set status = 'INVOICE', inv_no = v_no, inv_date = v_today, due_date = v_today + 1
   where id = p_id;
  return v_no;
end $$;

create or replace function public.qurban_mark_paid(p_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v public.qurban_orders%rowtype;
begin
  perform public.qurban_need('qurban','edit','Anda tidak memiliki izin mengubah status pembayaran');
  select * into v from public.qurban_orders where id = p_id and deleted_at is null for update;
  if not found then raise exception 'Pesanan tidak ditemukan' using errcode = 'P0002'; end if;
  if v.status <> 'INVOICE' then
    raise exception 'Hanya invoice yang sudah terbit yang bisa ditandai lunas' using errcode = '55000';
  end if;
  update public.qurban_orders set status = 'PAID', paid_at = now() where id = p_id;
end $$;

create or replace function public.qurban_cancel(p_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public as $$
declare v public.qurban_orders%rowtype;
begin
  perform public.qurban_need('qurban','delete','Anda tidak memiliki izin membatalkan pesanan');
  select * into v from public.qurban_orders where id = p_id and deleted_at is null for update;
  if not found then raise exception 'Pesanan tidak ditemukan' using errcode = 'P0002'; end if;
  if v.status not in ('PROFORMA','INVOICE') then
    raise exception 'Pesanan yang sudah lunas atau batal tidak bisa dibatalkan di sini' using errcode = '55000';
  end if;
  if btrim(coalesce(p_reason,'')) = '' then
    raise exception 'Alasan pembatalan wajib diisi' using errcode = '22023';
  end if;
  update public.qurban_orders set status = 'CANCELLED', cancel_reason = btrim(p_reason) where id = p_id;
end $$;

create or replace function public.qurban_add_weighing(p_id uuid, p_date date, p_weight numeric, p_note text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare v public.qurban_orders%rowtype;
begin
  perform public.qurban_need('qc_report','create','Anda tidak memiliki izin mencatat penimbangan');
  select * into v from public.qurban_orders where id = p_id and deleted_at is null;
  if not found then raise exception 'Pesanan tidak ditemukan' using errcode = 'P0002'; end if;
  if v.status = 'CANCELLED' then
    raise exception 'Pesanan ini sudah dibatalkan' using errcode = '55000';
  end if;
  if p_date is null or p_date > public.qurban_today() or p_date < v.start_date then
    raise exception 'Tanggal timbang harus antara tanggal mulai dan hari ini' using errcode = '22023';
  end if;
  if p_weight is null or p_weight <= 0 then
    raise exception 'Bobot wajib diisi' using errcode = '22023';
  end if;
  insert into public.qurban_weighings (order_id, weigh_date, weight, note)
  values (p_id, p_date, p_weight, coalesce(nullif(btrim(p_note), ''), 'Penimbangan'));
end $$;

create or replace function public.qurban_create_bill(p_id uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v public.qurban_orders%rowtype;
  v_today date := public.qurban_today();
  v_end date := public.qurban_setting('care_end')::date;
  v_last text;
  v_ym text;
  v_first date;
  v_basis numeric;
  v_cls public.qurban_price_classes;
  v_days integer;
  v_no text;
begin
  perform public.qurban_need('qurban','create','Anda tidak memiliki izin membuat tagihan');
  select * into v from public.qurban_orders where id = p_id and deleted_at is null for update;
  if not found then raise exception 'Pesanan tidak ditemukan' using errcode = 'P0002'; end if;
  if v.pay_mode <> 'MONTHLY' then
    raise exception 'Pesanan ini membayar perawatan lunas di awal, tidak ada tagihan bulanan' using errcode = '55000';
  end if;
  if v.status <> 'PAID' then
    raise exception 'Tagihan bulanan baru bisa dibuat setelah invoice awal lunas' using errcode = '55000';
  end if;
  select max(ym) into v_last from public.qurban_bills where order_id = p_id and status <> 'CANCELLED';
  v_ym := to_char((coalesce((v_last || '-01')::date, date_trunc('month', v.start_date)::date) + interval '1 month')::date, 'YYYY-MM');
  if v_ym > to_char(v_end, 'YYYY-MM') then
    raise exception 'Masa perawatan sudah berakhir, tidak ada tagihan lagi' using errcode = '55000';
  end if;
  v_first := (v_ym || '-01')::date;
  select coalesce((select w.weight from public.qurban_weighings w
                    where w.order_id = p_id and w.weigh_date < v_first
                    order by w.weigh_date desc, w.created_at desc limit 1), v.initial_weight)
    into v_basis;
  v_cls := public.qurban_class_at(v_basis, v_today);
  if v_cls.id is null then
    raise exception 'Bobot timbang terakhir di bawah 350 Kg tidak ada di daftar harga' using errcode = '22023';
  end if;
  v_days := public.qurban_days(v_ym, v.start_date, v_end);
  v_no := 'INV-' || lpad(public.qurban_next('INV', v_today)::text, 3, '0') || '-' ||
          public.qurban_roman(extract(month from v_today)::integer) || '-' || to_char(v_today, 'YY');
  insert into public.qurban_bills (order_id, bill_no, ym, days, rate, basis_weight, bill_date, due_date)
  values (p_id, v_no, v_ym, v_days, v_cls.care_price, v_basis, v_today, v_today + 7);
  return v_no;
end $$;

create or replace function public.qurban_mark_bill_paid(p_bill_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v public.qurban_bills%rowtype;
begin
  perform public.qurban_need('qurban','edit','Anda tidak memiliki izin mengubah status pembayaran');
  select * into v from public.qurban_bills where id = p_bill_id for update;
  if not found then raise exception 'Tagihan tidak ditemukan' using errcode = 'P0002'; end if;
  if v.status <> 'ISSUED' then
    raise exception 'Tagihan ini sudah lunas atau dibatalkan' using errcode = '55000';
  end if;
  update public.qurban_bills set status = 'PAID', paid_at = now() where id = p_bill_id;
end $$;

create or replace function public.qurban_set_choice(p_id uuid, p_choice text)
returns void
language plpgsql security definer set search_path = public as $$
declare v public.qurban_orders%rowtype;
begin
  perform public.qurban_need('qurban','edit','Anda tidak memiliki izin mencatat pilihan pemilik');
  select * into v from public.qurban_orders where id = p_id and deleted_at is null for update;
  if not found then raise exception 'Pesanan tidak ditemukan' using errcode = 'P0002'; end if;
  if v.status <> 'PAID' then
    raise exception 'Pilihan pemilik dicatat setelah invoice lunas' using errcode = '55000';
  end if;
  if p_choice not in ('SELF','SELL_OUT','SELL_BACK') then
    raise exception 'Pilihan tidak valid' using errcode = '22023';
  end if;
  update public.qurban_orders set owner_choice = p_choice, choice_date = public.qurban_today() where id = p_id;
end $$;

-- Data pembeli diisi di sini, saat Surat Perjanjian dibuat. Nomor surat dibuat sekali dan tetap
-- walau data diperbaiki kemudian.
create or replace function public.qurban_save_sp(p_id uuid, p_name text, p_nik text, p_addr text, p_phone text, p_type text, p_date date)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v public.qurban_orders%rowtype;
  d public.qurban_buyer_details%rowtype;
  v_seq integer;
  v_suffix text;
begin
  if not (public.has_permission('qurban','create') or public.has_permission('qurban','edit')) then
    raise exception 'Anda tidak memiliki izin membuat surat perjanjian' using errcode = '42501';
  end if;
  select * into v from public.qurban_orders where id = p_id and deleted_at is null for update;
  if not found then raise exception 'Pesanan tidak ditemukan' using errcode = 'P0002'; end if;
  if v.status <> 'PAID' then
    raise exception 'Surat perjanjian dibuat setelah invoice lunas' using errcode = '55000';
  end if;
  if btrim(coalesce(p_name,'')) = '' or btrim(coalesce(p_addr,'')) = '' or btrim(coalesce(p_type,'')) = '' then
    raise exception 'Nama lengkap, alamat, dan jenis sapi wajib diisi' using errcode = '22023';
  end if;
  if coalesce(p_nik,'') !~ '^[0-9]{16}$' then
    raise exception 'No. KTP harus 16 angka' using errcode = '22023';
  end if;
  if p_date is null then
    raise exception 'Tanggal surat wajib diisi' using errcode = '22023';
  end if;

  select * into d from public.qurban_buyer_details where order_id = p_id;
  if found then
    update public.qurban_buyer_details
       set full_name = btrim(p_name), nik = p_nik, address = btrim(p_addr), phone = nullif(btrim(coalesce(p_phone,'')), ''),
           cow_type = btrim(p_type), sp_date = p_date
     where order_id = p_id;
  else
    v_seq := public.qurban_next('SP', p_date);
    v_suffix := lpad(v_seq::text, 3, '0') || '-' || public.qurban_roman(extract(month from p_date)::integer)
                || '-AMF-' || to_char(p_date, 'YY');
    insert into public.qurban_buyer_details (order_id, full_name, nik, address, phone, cow_type, sp_date, sp_seq, sp_jb_no, sp_pl_no)
    values (p_id, btrim(p_name), p_nik, btrim(p_addr), nullif(btrim(coalesce(p_phone,'')), ''), btrim(p_type), p_date, v_seq,
            'SP-JB-' || v_suffix, 'SP-PL-' || v_suffix);
  end if;
end $$;

create or replace function public.qurban_create_qc(p_ym text, p_nick text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_today date := public.qurban_today();
  v_first date;
  v_pub date;
  v_id uuid;
  v_no text;
begin
  perform public.qurban_need('qc_report','create','Anda tidak memiliki izin membuat QC Report');
  if coalesce(p_ym,'') !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'Bulan tidak valid' using errcode = '22023';
  end if;
  if not exists (select 1 from public.qurban_orders where customer_nick = p_nick and status in ('INVOICE','PAID') and deleted_at is null) then
    raise exception 'Pelanggan ini belum punya sapi yang invoicenya terbit' using errcode = '22023';
  end if;
  select id into v_id from public.qurban_qc_reports where ym = p_ym and customer_nick = p_nick;
  if found then return v_id; end if;
  v_first := (p_ym || '-01')::date;
  v_pub := least(((v_first + interval '1 month - 1 day')::date), v_today);
  v_no := 'QC-' || lpad(public.qurban_next('QC', v_first)::text, 3, '0') || '-' ||
          public.qurban_roman(extract(month from v_first)::integer) || '-' || to_char(v_first, 'YY');
  insert into public.qurban_qc_reports (qc_no, ym, customer_nick, publish_date)
  values (v_no, p_ym, p_nick, greatest(v_pub, v_first))
  returning id into v_id;
  return v_id;
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'qurban_create_order(text,text,numeric,date,text)','qurban_set_discount(uuid,numeric)',
    'qurban_issue_invoice(uuid)','qurban_mark_paid(uuid)','qurban_cancel(uuid,text)',
    'qurban_add_weighing(uuid,date,numeric,text)','qurban_create_bill(uuid)','qurban_mark_bill_paid(uuid)',
    'qurban_set_choice(uuid,text)','qurban_save_sp(uuid,text,text,text,text,text,date)','qurban_create_qc(text,text)'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
revoke all on function public.qurban_need(text, text, text) from public, anon;
grant execute on function public.qurban_need(text, text, text) to authenticated;


-- ===== 0013_ro_fields.sql =====
-- HMI Internal System - RO: kolom tambahan sesuai form baru + penomoran RO-KODE-URUT-BULAN-TAHUN
alter table public.request_orders
  add column orderer_name     text,
  add column phone            text,
  add column delivery_address text,
  add column delivery_time    text,
  add column payment_method   text,
  add column est_pay_date     date,
  add column delivery_method  text,
  add constraint ro_payment_method_chk check (payment_method is null or payment_method in ('Tempo','Transfer','Cash','QRIS')),
  add constraint ro_delivery_method_chk check (delivery_method is null or delivery_method in ('Delivery','Pick Up di Toko')),
  add constraint ro_delivery_time_chk check (delivery_time is null or delivery_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$');

alter table public.ro_items
  add column cut_type  text,
  add column packaging text,
  add constraint ro_items_packaging_chk check (packaging is null or packaging in ('Vacuum 1 Kg','Vacuum 4 Kg','Tray + Wrap','Wrap + Vacuum 4 Kg'));

update public.doc_registry set
  header_cols = '{customer_id,order_date,delivery_date,notes,orderer_name,phone,delivery_address,delivery_time,payment_method,est_pay_date,delivery_method}',
  children = '[{"key":"items","table":"ro_items","fk":"ro_id","cols":["product_id","qty","unit_price","notes","cut_type","packaging"]}]'
where doc_type = 'RO';

-- Nomor RO: RO-{kode customer}-{urut 3 angka}-{bulan romawi}-{2 angka tahun}, urut per customer per bulan.
create table public.ro_sequences (
  customer_id uuid not null references public.customers(id),
  ym          text not null,
  last_number integer not null default 0,
  primary key (customer_id, ym)
);
alter table public.ro_sequences enable row level security;

create or replace function public.ro_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_code text; v_ym text; v_n integer;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
begin
  if new.doc_number is not null then return new; end if;
  select code into v_code from public.customers where id = new.customer_id;
  v_ym := to_char(new.order_date, 'YYYYMM');
  insert into public.ro_sequences as s (customer_id, ym, last_number) values (new.customer_id, v_ym, 1)
  on conflict (customer_id, ym) do update set last_number = s.last_number + 1
  returning last_number into v_n;
  new.doc_number := format('RO-%s-%s-%s-%s', v_code, lpad(v_n::text, 3, '0'),
    v_roman[extract(month from new.order_date)::int], to_char(new.order_date, 'YY'));
  return new;
end $$;
revoke all on function public.ro_assign_number() from public, anon, authenticated;

drop trigger request_orders_docno on public.request_orders;
create trigger request_orders_docno before insert on public.request_orders
  for each row execute function public.ro_assign_number();


-- ===== 0014_ro_quick_product.sql =====
-- Tambah produk cepat dari form RO (hak: membuat RO). Produk tercatat sebagai MANUFACTURE.
create or replace function public.ro_quick_product(p_name text, p_unit_id uuid, p_category_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_name text := btrim(coalesce(p_name,'')); v_code text; v_id uuid; v_i int := 0;
begin
  if not public.has_permission('ro','create') then
    raise exception 'Tidak berhak' using errcode = '42501';
  end if;
  if v_name = '' or length(v_name) > 100 then
    raise exception 'Nama produk tidak valid' using errcode = '22023';
  end if;
  select id into v_id from public.products where lower(name) = lower(v_name);
  if v_id is not null then return v_id; end if;
  v_code := upper(regexp_replace(v_name, '[^A-Za-z0-9]+', '-', 'g'));
  v_code := trim(both '-' from left(v_code, 30));
  if v_code = '' then v_code := 'PRD'; end if;
  while exists (select 1 from public.products where code = case when v_i = 0 then v_code else v_code || '-' || v_i end) loop
    v_i := v_i + 1;
  end loop;
  if v_i > 0 then v_code := v_code || '-' || v_i; end if;
  insert into public.products (code, name, product_type, category_id, unit_id)
  values (v_code, v_name, 'MANUFACTURE', p_category_id, p_unit_id) returning id into v_id;
  return v_id;
end $$;
revoke all on function public.ro_quick_product(text, uuid, uuid) from public, anon;
grant execute on function public.ro_quick_product(text, uuid, uuid) to authenticated;


-- ===== 0015_prod_fields.sql =====
-- Production Order: kolom tambahan sesuai form baru, nomor dari RO, satu RO hanya satu PO aktif.
alter table public.production_orders
  add column send_note        text,
  add column delivery_address text,
  add column pic              text,
  add column cow_codes        text;
alter table public.po_items
  add column ro_product_id uuid references public.products(id),
  add column cut_type      text,
  add column packaging     text,
  add constraint po_items_packaging_chk check (packaging is null or packaging in ('Vacuum 1 Kg','Vacuum 4 Kg','Tray + Wrap','Wrap + Vacuum 4 Kg'));

update public.doc_registry set
  header_cols = '{ro_id,order_date,needed_date,notes,send_note,delivery_address,pic,cow_codes}',
  children = '[{"key":"items","table":"po_items","fk":"po_id","cols":["product_id","qty","notes","ro_product_id","cut_type","packaging"]}]'
where doc_type = 'PROD';

-- Nomor: PROD-{kode customer}-{urut dari RO}-{bulan romawi hari ini}-{YY}, akhiran -R2, -R3 untuk PO pengganti.
create or replace function public.prod_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_ro text; v_core text; v_n int;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
begin
  if new.doc_number is not null then return new; end if;
  if new.ro_id is not null then
    select doc_number into v_ro from public.request_orders where id = new.ro_id;
    v_core := substring(v_ro from '^RO-(.*-[0-9]{3})-[IVX]+-[0-9]{2}$');
  end if;
  if v_core is null then
    new.doc_number := public.next_doc_number('PROD', 'PROD');
    return new;
  end if;
  select count(*) into v_n from public.production_orders where ro_id = new.ro_id;
  new.doc_number := format('PROD-%s-%s-%s', v_core, v_roman[extract(month from v_today)::int], to_char(v_today, 'YY'))
                    || case when v_n > 0 then '-R' || (v_n + 1) else '' end;
  return new;
end $$;
revoke all on function public.prod_assign_number() from public, anon, authenticated;
drop trigger production_orders_docno on public.production_orders;
create trigger production_orders_docno before insert on public.production_orders
  for each row execute function public.prod_assign_number();

create or replace function public.prod_one_active() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.ro_id is not null and exists (
    select 1 from public.production_orders
    where ro_id = new.ro_id and id <> new.id and deleted_at is null and status not in ('REJECTED','CANCELLED')
  ) then
    raise exception 'RO ini sudah punya Production Order yang aktif' using errcode = '22023';
  end if;
  return new;
end $$;
create trigger production_orders_one_active before insert on public.production_orders
  for each row execute function public.prod_one_active();


-- ===== 0016_pl_fields.sql =====
-- Packing List: satu baris = satu kemasan (berat net dan gross), seperti contoh Packing_List.pdf.
alter table public.pl_items drop constraint pl_items_pl_id_product_id_key;
alter table public.pl_items
  add column gross_weight numeric(14,3),
  add constraint pl_items_gross_chk check (gross_weight is null or gross_weight >= qty);
alter table public.packing_lists
  add column phone      text,
  add column supervisor text;

update public.doc_registry set
  header_cols = '{po_id,ro_id,customer_id,warehouse_id,pack_date,driver_name,vehicle_plate,notes,phone,supervisor}',
  children = '[{"key":"items","table":"pl_items","fk":"pl_id","cols":["product_id","qty","notes","gross_weight"]}]'
where doc_type = 'PL';

-- Nomor: PL-{urut 3 angka}-{bulan romawi}-{YY}, urut per bulan (tanggal kemas).
create table public.pl_sequences (
  ym          text primary key,
  last_number integer not null default 0
);
alter table public.pl_sequences enable row level security;

create or replace function public.pl_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_ym text; v_n integer;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
begin
  if new.doc_number is not null then return new; end if;
  v_ym := to_char(new.pack_date, 'YYYYMM');
  insert into public.pl_sequences as s (ym, last_number) values (v_ym, 1)
  on conflict (ym) do update set last_number = s.last_number + 1
  returning last_number into v_n;
  new.doc_number := format('PL-%s-%s-%s', lpad(v_n::text, 3, '0'), v_roman[extract(month from new.pack_date)::int], to_char(new.pack_date, 'YY'));
  return new;
end $$;
revoke all on function public.pl_assign_number() from public, anon, authenticated;
drop trigger packing_lists_docno on public.packing_lists;
create trigger packing_lists_docno before insert on public.packing_lists
  for each row execute function public.pl_assign_number();


-- ===== 0017_inv_fields.sql =====
-- Invoice: kolom sesuai contoh (surat jalan, uang muka, bank, penandatangan), nomor INV-URUT-BULAN-TAHUN.
alter table public.invoices
  add column down_payment     numeric(18,2) not null default 0 check (down_payment >= 0),
  add column delivery_note_no text,
  add column buyer_name       text,
  add column phone            text,
  add column bank_info        text,
  add column signer           text,
  add column use_signature    boolean not null default true;
alter table public.inv_items
  add column description text;

update public.doc_registry set
  header_cols = '{customer_id,pl_id,ro_id,invoice_date,due_date,notes,down_payment,delivery_note_no,buyer_name,phone,bank_info,signer,use_signature}',
  children = '[{"key":"items","table":"inv_items","fk":"inv_id","cols":["product_id","qty","unit_price","description"]}]'
where doc_type = 'INV';

-- Nomor: INV-{urut 3 angka}-{bulan romawi}-{YY}, urut per bulan (tanggal invoice).
create table public.inv_sequences (
  ym          text primary key,
  last_number integer not null default 0
);
alter table public.inv_sequences enable row level security;

create or replace function public.inv_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_n integer;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
begin
  if new.doc_number is not null then return new; end if;
  insert into public.inv_sequences as s (ym, last_number) values (to_char(new.invoice_date, 'YYYYMM'), 1)
  on conflict (ym) do update set last_number = s.last_number + 1
  returning last_number into v_n;
  new.doc_number := format('INV-%s-%s-%s', lpad(v_n::text, 3, '0'), v_roman[extract(month from new.invoice_date)::int], to_char(new.invoice_date, 'YY'));
  return new;
end $$;
revoke all on function public.inv_assign_number() from public, anon, authenticated;
drop trigger invoices_docno on public.invoices;
create trigger invoices_docno before insert on public.invoices
  for each row execute function public.inv_assign_number();

-- Pratinjau nomor berikutnya (tidak menambah urutan).
create or replace function public.inv_next_number(p_date date) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v_n integer;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
begin
  if not public.has_permission('invoice','create') then
    raise exception 'Tidak berhak' using errcode = '42501';
  end if;
  select coalesce(max(last_number), 0) + 1 into v_n from public.inv_sequences where ym = to_char(p_date, 'YYYYMM');
  return format('INV-%s-%s-%s', lpad(v_n::text, 3, '0'), v_roman[extract(month from p_date)::int], to_char(p_date, 'YY'));
end $$;
revoke all on function public.inv_next_number(date) from public, anon;
grant execute on function public.inv_next_number(date) to authenticated;

-- Uang muka dihitung sebagai pembayaran saat invoice diterbitkan.
create or replace function public.inv_before() returns trigger language plpgsql security definer set search_path = public as $$
declare v_term int; v_pl text;
begin
  if tg_op = 'INSERT' or new.pl_id is distinct from old.pl_id then
    if new.pl_id is not null then
      select status into v_pl from public.packing_lists where id = new.pl_id;
      if v_pl is null or v_pl not in ('PACKED','DELIVERED') then
        raise exception 'Invoice hanya bisa dibuat dari Packing List yang sudah dikemas' using errcode = '22023';
      end if;
    end if;
  end if;
  if new.due_date is null then
    select payment_term_days into v_term from public.customers where id = new.customer_id;
    new.due_date := new.invoice_date + coalesce(v_term, 0);
  end if;
  if tg_op = 'UPDATE' and new.status = 'VOID' and old.paid_amount > old.down_payment then
    raise exception 'Invoice sudah ada pembayaran. Batalkan CRJ terkait lebih dulu' using errcode = '55000';
  end if;
  if tg_op = 'UPDATE' and new.status = 'ISSUED' and old.status = 'DRAFT' then
    if not exists (select 1 from public.inv_items where inv_id = new.id) or new.total <= 0 then
      raise exception 'Invoice harus memiliki barang dan total lebih dari 0' using errcode = '22023';
    end if;
    if new.down_payment > new.total then
      raise exception 'Uang muka melebihi total invoice' using errcode = '22023';
    end if;
    new.paid_amount := new.down_payment;
    new.status := case when new.down_payment >= new.total then 'PAID' when new.down_payment > 0 then 'PARTIAL' else 'ISSUED' end;
  end if;
  return new;
end $$;

-- Invoice bersaldo uang muka (PARTIAL) tetap bisa dibatalkan selama belum ada CRJ.
insert into public.doc_rules (doc_type, from_status, to_status, module, action, needs_note, label)
values ('INV','PARTIAL','VOID','invoice','delete',true,'Batalkan invoice');


-- ===== 0018_store_income.sql =====
-- HMI Hub - Pemasukan Toko: laporan periodik pemasukan per kanal (Cash, QRIS, Debit, Grab, TF Rek HMI) dan setoran.
-- Dokumen baru, terpisah dari CRJ (bukti uang masuk). Baris pembayaran invoice bisa ditarik otomatis dari Invoice/CRJ.
-- Total Pendapatan = uang cash yang harus disetor + Cash + QRIS + Debit + Grab + TF Rek HMI + semua piutang
-- (rumus dari Excel Owner; kolom Disetor tidak ikut). Uang cash yang harus disetor = Total Cash - Total Disetor.

insert into public.permissions (module, action)
select 'store_income', a.action
from unnest(array['view','create','edit','delete','approve','export']) as a(action)
on conflict (module, action) do nothing;

create or replace function pg_temp.g(p_role text, p_module text, p_actions text[]) returns void language sql as $f$
  insert into public.role_permissions (role_id, permission_id) select r.id, p.id from public.roles r, public.permissions p
   where r.code = p_role and p.module = p_module and p.action = any(p_actions) on conflict do nothing;
$f$;
select pg_temp.g('ACCOUNTING','store_income','{view,create,edit,delete,export}');

create table public.store_income_reports (
  id          uuid primary key default gen_random_uuid(),
  doc_number  text unique,
  period_from date not null,
  period_to   date not null,
  notes       text,
  status      text not null default 'DRAFT' check (status in ('DRAFT','FINAL','VOID')),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id),
  deleted_at timestamptz,
  constraint store_income_period check (period_to >= period_from)
);
create table public.store_income_lines (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references public.store_income_reports(id),
  line_no     integer not null,
  entry_date  date not null,
  description text not null check (btrim(description) <> ''),
  cash        numeric(18,2),
  qris        numeric(18,2),
  debit       numeric(18,2),
  grab        numeric(18,2),
  tf          numeric(18,2),
  deposited   numeric(18,2),
  proof       text,
  invoice_id  uuid references public.invoices(id),
  unique (report_id, line_no)
);
create table public.store_income_receivables (
  id        uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.store_income_reports(id),
  line_no   integer not null,
  name      text not null check (btrim(name) <> ''),
  amount    numeric(18,2) not null default 0,
  unique (report_id, line_no)
);
create index store_income_lines_report_idx on public.store_income_lines(report_id);
create index store_income_recv_report_idx on public.store_income_receivables(report_id);

select public.attach_doc_standard('store_income_reports', 'PMT', 'PMT', 'store_income');
select public.attach_child_standard('store_income_lines', 'store_income');
select public.attach_child_standard('store_income_receivables', 'store_income');

-- Nomor: PMT-{urut 3 angka}-{bulan romawi}-{YY}, urut per bulan (tanggal akhir periode).
create table public.pmt_sequences (ym text primary key, last_number integer not null default 0);
alter table public.pmt_sequences enable row level security;
create or replace function public.pmt_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_n integer;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
begin
  if new.doc_number is not null then return new; end if;
  insert into public.pmt_sequences as s (ym, last_number) values (to_char(new.period_to, 'YYYYMM'), 1)
  on conflict (ym) do update set last_number = s.last_number + 1
  returning last_number into v_n;
  new.doc_number := format('PMT-%s-%s-%s', lpad(v_n::text, 3, '0'), v_roman[extract(month from new.period_to)::int], to_char(new.period_to, 'YY'));
  return new;
end $$;
revoke all on function public.pmt_assign_number() from public, anon, authenticated;
drop trigger store_income_reports_docno on public.store_income_reports;
create trigger store_income_reports_docno before insert on public.store_income_reports
  for each row execute function public.pmt_assign_number();

insert into public.doc_registry (doc_type, table_name, module, header_cols, children) values
 ('PMT','store_income_reports','store_income','{period_from,period_to,notes}',
  '[{"key":"lines","table":"store_income_lines","fk":"report_id","cols":["entry_date","description","cash","qris","debit","grab","tf","deposited","proof","invoice_id"]},
    {"key":"recv","table":"store_income_receivables","fk":"report_id","cols":["name","amount"]}]');
insert into public.doc_rules (doc_type, from_status, to_status, module, action, needs_note, label) values
 ('PMT','DRAFT','FINAL','store_income','edit',false,'Finalkan laporan'),
 ('PMT','DRAFT','VOID','store_income','edit',true,'Batalkan'),
 ('PMT','FINAL','VOID','store_income','delete',true,'Batalkan laporan');

-- Baris pembayaran invoice pada periode: pembayaran CRJ yang sudah diposting (kolom TF Rek HMI) dan uang muka invoice.
create or replace function public.store_income_invoice_lines(p_from date, p_to date)
returns table (entry_date date, description text, tf numeric, invoice_id uuid)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_permission('store_income','create') and not public.has_permission('store_income','edit') then
    raise exception 'Tidak berhak' using errcode = '42501';
  end if;
  return query
  select d.entry_date, d.description, d.tf, d.invoice_id from (
    select r.receipt_date as entry_date, 'Pemasukan ' || i.doc_number as description, sum(a.amount) as tf, i.id as invoice_id
      from public.cash_receipts r
      join public.crj_allocations a on a.crj_id = r.id and a.invoice_id is not null
      join public.invoices i on i.id = a.invoice_id
     where r.status = 'POSTED' and r.deleted_at is null and r.receipt_date between p_from and p_to
     group by r.receipt_date, i.doc_number, i.id
    union all
    select i.invoice_date, 'Pemasukan ' || i.doc_number || ' (uang muka)', i.down_payment, i.id
      from public.invoices i
     where i.down_payment > 0 and i.status <> 'VOID' and i.status <> 'DRAFT' and i.deleted_at is null
       and i.invoice_date between p_from and p_to
  ) d order by d.entry_date, d.description;
end $$;
revoke all on function public.store_income_invoice_lines(date, date) from public, anon;
grant execute on function public.store_income_invoice_lines(date, date) to authenticated;

-- Piutang saat ini per pelanggan: sisa tagihan invoice yang belum lunas.
create or replace function public.store_income_receivables_now()
returns table (name text, amount numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_permission('store_income','create') and not public.has_permission('store_income','edit') then
    raise exception 'Tidak berhak' using errcode = '42501';
  end if;
  return query
  select c.name, sum(i.total - i.paid_amount)::numeric
    from public.invoices i join public.customers c on c.id = i.customer_id
   where i.status in ('ISSUED','PARTIAL') and i.deleted_at is null
   group by c.name having sum(i.total - i.paid_amount) > 0
   order by c.name;
end $$;
revoke all on function public.store_income_receivables_now() from public, anon;
grant execute on function public.store_income_receivables_now() to authenticated;


-- ===== 0019_delivery_order.sql =====
-- HMI Hub - Delivery Order (Surat Jalan): dibuat dari Packing List, berjalan paralel dengan Invoice.
-- Alur status: DRAFT -> SENT (surat jalan terbit, barang berangkat) -> RECEIVED (barang diterima, tanda tangan penerima)
-- -> ARCHIVED (surat jalan fisik sudah dipindai ke Google Drive dan tautannya disimpan di sini).
-- Saat RECEIVED, Packing List yang masih PACKED otomatis menjadi DELIVERED.

insert into public.permissions (module, action)
select 'delivery_order', a.action
from unnest(array['view','create','edit','delete','approve','export']) as a(action)
on conflict (module, action) do nothing;

create or replace function pg_temp.g(p_role text, p_module text, p_actions text[]) returns void language sql as $f$
  insert into public.role_permissions (role_id, permission_id) select r.id, p.id from public.roles r, public.permissions p
   where r.code = p_role and p.module = p_module and p.action = any(p_actions) on conflict do nothing;
$f$;
select pg_temp.g('MARKETING','delivery_order','{view,create,edit,export}');
select pg_temp.g('PRODUKSI','delivery_order','{view,create,edit,export}');
select pg_temp.g('ACCOUNTING','delivery_order','{view,export}');

create table public.delivery_orders (
  id               uuid primary key default gen_random_uuid(),
  doc_number       text unique,
  pl_id            uuid not null references public.packing_lists(id),
  customer_id      uuid not null references public.customers(id),
  do_date          date not null default (now() at time zone 'Asia/Jakarta')::date,
  driver_name      text,
  vehicle_plate    text,
  delivery_address text,
  notes            text,
  receiver_name    text,
  received_on      date,
  scan_url         text,
  status           text not null default 'DRAFT' check (status in ('DRAFT','SENT','RECEIVED','ARCHIVED','VOID')),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id),
  deleted_at timestamptz,
  constraint do_scan_url_chk check (scan_url is null or scan_url ~* '^https://(drive|docs)\.google\.com/')
);
-- Satu Packing List hanya punya satu surat jalan yang masih berlaku.
create unique index delivery_orders_pl_active on public.delivery_orders(pl_id) where status <> 'VOID' and deleted_at is null;
create index delivery_orders_pl_idx on public.delivery_orders(pl_id);

select public.attach_doc_standard('delivery_orders', 'DO', 'DO', 'delivery_order');

-- Nomor: DO-{urut 3 angka}-{bulan romawi}-{YY}, urut per bulan (tanggal surat jalan).
create table public.do_sequences (ym text primary key, last_number integer not null default 0);
alter table public.do_sequences enable row level security;
create or replace function public.do_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_n integer;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
begin
  if new.doc_number is not null then return new; end if;
  insert into public.do_sequences as s (ym, last_number) values (to_char(new.do_date, 'YYYYMM'), 1)
  on conflict (ym) do update set last_number = s.last_number + 1
  returning last_number into v_n;
  new.doc_number := format('DO-%s-%s-%s', lpad(v_n::text, 3, '0'), v_roman[extract(month from new.do_date)::int], to_char(new.do_date, 'YY'));
  return new;
end $$;
revoke all on function public.do_assign_number() from public, anon, authenticated;
drop trigger delivery_orders_docno on public.delivery_orders;
create trigger delivery_orders_docno before insert on public.delivery_orders
  for each row execute function public.do_assign_number();

-- Pemeriksaan: customer mengikuti Packing List, Packing List tidak bisa diganti, syarat tiap tahap.
create or replace function public.do_before() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_pl record;
begin
  new.scan_url := nullif(btrim(coalesce(new.scan_url, '')), '');
  if tg_op = 'INSERT' then
    select customer_id, status into v_pl from public.packing_lists where id = new.pl_id and deleted_at is null;
    if not found then raise exception 'Packing List tidak ditemukan' using errcode = '22023'; end if;
    if v_pl.status not in ('PACKED','DELIVERED') then
      raise exception 'Surat jalan hanya bisa dibuat dari Packing List yang sudah dikemas' using errcode = '22023';
    end if;
    new.customer_id := v_pl.customer_id;
    return new;
  end if;
  if new.pl_id is distinct from old.pl_id then
    raise exception 'Packing List pada surat jalan tidak bisa diganti' using errcode = '22023';
  end if;
  new.customer_id := old.customer_id;
  if new.status is distinct from old.status then
    if new.status = 'SENT' and btrim(coalesce(new.driver_name, '')) = '' then
      raise exception 'Nama sopir wajib diisi sebelum surat jalan diterbitkan' using errcode = '22023';
    end if;
    if new.status = 'RECEIVED' and (btrim(coalesce(new.receiver_name, '')) = '' or new.received_on is null) then
      raise exception 'Nama penerima dan tanggal terima wajib diisi' using errcode = '22023';
    end if;
    if new.status = 'ARCHIVED' and btrim(coalesce(new.scan_url, '')) = '' then
      raise exception 'Tautan Google Drive surat jalan yang sudah dipindai wajib diisi' using errcode = '22023';
    end if;
  end if;
  return new;
end $$;
revoke all on function public.do_before() from public, anon, authenticated;
create trigger delivery_orders_check before insert or update on public.delivery_orders
  for each row execute function public.do_before();

-- Barang diterima -> Packing List yang masih PACKED ikut menjadi DELIVERED (lengkap dengan riwayat status).
create or replace function public.do_on_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'RECEIVED' and old.status = 'SENT' then
    if exists (select 1 from public.packing_lists where id = new.pl_id and status = 'PACKED') then
      update public.packing_lists set status = 'DELIVERED' where id = new.pl_id;
      insert into public.doc_status_history (doc_type, doc_id, from_status, to_status, note, changed_by)
      values ('PL', new.pl_id, 'PACKED', 'DELIVERED', 'Otomatis: surat jalan ' || new.doc_number || ' diterima', auth.uid());
    end if;
  end if;
  return null;
end $$;
revoke all on function public.do_on_status() from public, anon, authenticated;
create trigger delivery_orders_status after update of status on public.delivery_orders
  for each row execute function public.do_on_status();

insert into public.doc_registry (doc_type, table_name, module, header_cols, editable_statuses, children) values
 ('DO','delivery_orders','delivery_order',
  '{pl_id,do_date,driver_name,vehicle_plate,delivery_address,notes,receiver_name,received_on,scan_url}',
  '{DRAFT,SENT,RECEIVED}', '[]');
insert into public.doc_rules (doc_type, from_status, to_status, module, action, needs_note, label) values
 ('DO','DRAFT','SENT','delivery_order','edit',false,'Terbitkan surat jalan'),
 ('DO','SENT','RECEIVED','delivery_order','edit',false,'Barang sudah diterima'),
 ('DO','RECEIVED','ARCHIVED','delivery_order','edit',false,'Arsipkan (scan sudah di Google Drive)'),
 ('DO','DRAFT','VOID','delivery_order','edit',true,'Batalkan'),
 ('DO','SENT','VOID','delivery_order','delete',true,'Batalkan surat jalan'),
 ('DO','RECEIVED','VOID','delivery_order','delete',true,'Batalkan surat jalan'),
 ('DO','ARCHIVED','VOID','delivery_order','delete',true,'Batalkan surat jalan');


-- ===== 0020_cash_journal.sql =====
-- HMI Hub - Cash Payment Journal (CPJ mingguan): jurnal pengeluaran kas dengan kolom rencana dan realisasi.
-- Dokumen baru, terpisah dari CPJ lama (pembayaran per PR). Baris bisa ditarik dari item Purchase Request atau diketik manual.
-- Alur: DRAFT -> WAITING (diajukan ke Owner) -> ACC (Owner menyetujui, dana dirilis) -> REALIZED (realisasi diisi).
-- Setelah di-ACC, kolom rencana terkunci; hanya realisasi (harga, qty, bukti) yang boleh diisi.
-- Nomor: CPJ-{minggu ke- dalam bulan, 3 angka}-{bulan romawi}-{YY}; nomor realisasi di cetakan: R-{nomor}.
-- Saat REALIZED, PR yang barangnya sudah diterima (RECEIVED) otomatis menjadi PAID.

insert into public.permissions (module, action)
select 'cpj_journal', a.action
from unnest(array['view','create','edit','delete','approve','export']) as a(action)
on conflict (module, action) do nothing;

create or replace function pg_temp.g(p_role text, p_module text, p_actions text[]) returns void language sql as $f$
  insert into public.role_permissions (role_id, permission_id) select r.id, p.id from public.roles r, public.permissions p
   where r.code = p_role and p.module = p_module and p.action = any(p_actions) on conflict do nothing;
$f$;
select pg_temp.g('ACCOUNTING','cpj_journal','{view,create,edit,delete,export}');
select pg_temp.g('PURCHASING','cpj_journal','{view}');

create table public.cash_journals (
  id              uuid primary key default gen_random_uuid(),
  doc_number      text unique,
  journal_date    date not null default (now() at time zone 'Asia/Jakarta')::date,
  initiator_name  text,
  initiator_title text,
  approver_name   text,
  approver_title  text,
  pay_note        text,
  notes           text,
  plan_hash       text,
  approved_on     date,
  realized_on     date,
  status          text not null default 'DRAFT' check (status in ('DRAFT','WAITING','ACC','REALIZED','VOID')),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id),
  deleted_at timestamptz
);
create table public.cash_journal_lines (
  id          uuid primary key default gen_random_uuid(),
  journal_id  uuid not null references public.cash_journals(id),
  line_no     integer not null,
  trans_date  date,
  ac          text,
  code        text,
  description text not null check (btrim(description) <> ''),
  price       numeric(18,2) not null default 0 check (price >= 0),
  qty         numeric(14,3) not null default 1 check (qty >= 0),
  unit        text,
  flag        text not null default 'NONE' check (flag in ('NONE','NON_CPJ','OVER','REJECTED','INCOMING')),
  pr_item_id  uuid references public.pr_items(id),
  real_price  numeric(18,2) check (real_price >= 0),
  real_qty    numeric(14,3) check (real_qty >= 0),
  proof       text,
  unique (journal_id, line_no)
);
create index cash_journal_lines_journal_idx on public.cash_journal_lines(journal_id);
create index cash_journal_lines_pr_item_idx on public.cash_journal_lines(pr_item_id);

-- save_doc mengisi kolom yang tidak dikirim dengan NULL; nilai bawaan dipulihkan di sini.
create or replace function public.jcp_line_defaults() returns trigger
language plpgsql as $$
begin
  new.flag  := coalesce(nullif(btrim(new.flag), ''), 'NONE');
  new.price := coalesce(new.price, 0);
  new.qty   := coalesce(new.qty, 1);
  new.ac    := nullif(btrim(coalesce(new.ac, '')), '');
  new.code  := nullif(btrim(coalesce(new.code, '')), '');
  new.unit  := nullif(btrim(coalesce(new.unit, '')), '');
  new.proof := nullif(btrim(coalesce(new.proof, '')), '');
  return new;
end $$;
create trigger cash_journal_lines_defaults before insert on public.cash_journal_lines
  for each row execute function public.jcp_line_defaults();

select public.attach_doc_standard('cash_journals', 'JCP', 'CPJ', 'cpj_journal');
select public.attach_child_standard('cash_journal_lines', 'cpj_journal');

-- Nomor mingguan: minggu ke-1 dimulai tanggal 1 (Senin sebagai awal minggu, sama dengan Purchase Request di preview).
-- Jika minggu itu sudah punya jurnal lain, nomor diberi akhiran -2, -3, dst.
create or replace function public.cpj_week_of(p_date date) returns integer
language sql immutable as $$
  select ((extract(day from p_date)::int - 1 + ((extract(dow from date_trunc('month', p_date))::int + 6) % 7)) / 7) + 1
$$;
create or replace function public.jcp_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
  v_base  text;
  v_n     integer;
begin
  if new.doc_number is not null then return new; end if;
  v_base := format('CPJ-%s-%s-%s', lpad(public.cpj_week_of(new.journal_date)::text, 3, '0'),
                   v_roman[extract(month from new.journal_date)::int], to_char(new.journal_date, 'YY'));
  perform pg_advisory_xact_lock(hashtext(v_base));
  select count(*) into v_n from public.cash_journals where doc_number = v_base or doc_number like v_base || '-%';
  new.doc_number := case when v_n = 0 then v_base else v_base || '-' || (v_n + 1) end;
  return new;
end $$;
revoke all on function public.jcp_assign_number() from public, anon, authenticated;
drop trigger cash_journals_docno on public.cash_journals;
create trigger cash_journals_docno before insert on public.cash_journals
  for each row execute function public.jcp_assign_number();

-- Tanggal ACC dan tanggal realisasi dicatat otomatis; hanya Owner (izin approve) yang bisa membawa jurnal ke ACC.
create or replace function public.jcp_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    if new.status = 'ACC' then new.approved_on := (now() at time zone 'Asia/Jakarta')::date; end if;
    if new.status = 'REALIZED' then
      new.realized_on := (now() at time zone 'Asia/Jakarta')::date;
      if not exists (select 1 from public.cash_journal_lines where journal_id = new.id) then
        raise exception 'Jurnal tanpa baris tidak bisa direalisasi' using errcode = '22023';
      end if;
    end if;
    if new.status = 'WAITING' and not exists (select 1 from public.cash_journal_lines where journal_id = new.id) then
      raise exception 'Isi minimal satu baris sebelum diajukan ke Owner' using errcode = '22023';
    end if;
  end if;
  return new;
end $$;
revoke all on function public.jcp_before() from public, anon, authenticated;
create trigger cash_journals_check before update on public.cash_journals
  for each row execute function public.jcp_before();

-- Realisasi selesai -> PR yang barangnya sudah diterima menjadi PAID (dengan riwayat). Batal setelah realisasi -> kembali RECEIVED.
create or replace function public.jcp_on_status() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.status = 'REALIZED' and old.status = 'ACC' then
    for r in
      select distinct p.id from public.cash_journal_lines l
        join public.pr_items i on i.id = l.pr_item_id
        join public.purchase_requests p on p.id = i.pr_id
       where l.journal_id = new.id and p.status = 'RECEIVED'
    loop
      update public.purchase_requests set status = 'PAID' where id = r.id;
      insert into public.pr_status_history (pr_id, from_status, to_status, note, changed_by)
      values (r.id, 'RECEIVED', 'PAID', 'Dibayar lewat ' || new.doc_number, auth.uid());
    end loop;
  elsif new.status = 'VOID' and old.status = 'REALIZED' then
    for r in
      select distinct p.id from public.cash_journal_lines l
        join public.pr_items i on i.id = l.pr_item_id
        join public.purchase_requests p on p.id = i.pr_id
       where l.journal_id = new.id and p.status = 'PAID'
         and not exists (
           select 1 from public.cash_journal_lines l2
             join public.cash_journals j2 on j2.id = l2.journal_id and j2.status = 'REALIZED' and j2.deleted_at is null and j2.id <> new.id
             join public.pr_items i2 on i2.id = l2.pr_item_id
            where i2.pr_id = p.id)
         and not exists (select 1 from public.cash_payments c where c.pr_id = p.id and c.status = 'POSTED')
    loop
      update public.purchase_requests set status = 'RECEIVED' where id = r.id;
      insert into public.pr_status_history (pr_id, from_status, to_status, note, changed_by)
      values (r.id, 'PAID', 'RECEIVED', 'Jurnal ' || new.doc_number || ' dibatalkan', auth.uid());
    end loop;
  end if;
  return null;
end $$;
revoke all on function public.jcp_on_status() from public, anon, authenticated;
create trigger cash_journals_status after update of status on public.cash_journals
  for each row execute function public.jcp_on_status();

-- Setelah simpan: kunci kolom rencana. Saat DRAFT sidik jari rencana diperbarui; saat ACC rencana harus sama dengan yang di-ACC.
-- Satu item PR tidak boleh ada di dua jurnal yang masih berlaku.
create or replace function public.jcp_after_save(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_status text;
  v_hash   text;
  v_old    text;
  v_dup    text;
begin
  select status, plan_hash into v_status, v_old from public.cash_journals where id = p_id;
  select md5(coalesce(string_agg(concat_ws('|', l.line_no, l.trans_date, l.ac, l.code, l.description, l.price, l.qty, l.unit, l.flag, l.pr_item_id), E'\n' order by l.line_no), ''))
    into v_hash from public.cash_journal_lines l where l.journal_id = p_id;
  if v_status = 'DRAFT' then
    update public.cash_journals set plan_hash = v_hash where id = p_id;
  elsif v_status = 'ACC' and v_hash is distinct from v_old then
    raise exception 'Jurnal sudah di-ACC Owner: kolom rencana tidak boleh diubah, hanya realisasi dan bukti' using errcode = '55000';
  end if;
  select j.doc_number into v_dup
    from public.cash_journal_lines l
    join public.cash_journal_lines o on o.pr_item_id = l.pr_item_id and o.journal_id <> l.journal_id
    join public.cash_journals j on j.id = o.journal_id and j.status <> 'VOID' and j.deleted_at is null
   where l.journal_id = p_id and l.pr_item_id is not null
   limit 1;
  if v_dup is not null then
    raise exception 'Item Purchase Request sudah dipakai di jurnal %', v_dup using errcode = '23505';
  end if;
end $$;
revoke all on function public.jcp_after_save(uuid) from public, anon, authenticated;

insert into public.doc_registry (doc_type, table_name, module, header_cols, editable_statuses, children, after_save_fn) values
 ('JCP','cash_journals','cpj_journal',
  '{journal_date,initiator_name,initiator_title,approver_name,approver_title,pay_note,notes}',
  '{DRAFT,ACC}',
  '[{"key":"lines","table":"cash_journal_lines","fk":"journal_id","cols":["trans_date","ac","code","description","price","qty","unit","flag","pr_item_id","real_price","real_qty","proof"]}]',
  'jcp_after_save');
insert into public.doc_rules (doc_type, from_status, to_status, module, action, needs_note, label) values
 ('JCP','DRAFT','WAITING','cpj_journal','edit',false,'Ajukan ke Owner'),
 ('JCP','WAITING','ACC','cpj_journal','approve',false,'ACC (dana dirilis)'),
 ('JCP','WAITING','DRAFT','cpj_journal','approve',true,'Kembalikan ke draf'),
 ('JCP','ACC','REALIZED','cpj_journal','edit',false,'Selesaikan realisasi'),
 ('JCP','DRAFT','VOID','cpj_journal','edit',true,'Batalkan'),
 ('JCP','WAITING','VOID','cpj_journal','delete',true,'Batalkan jurnal'),
 ('JCP','ACC','VOID','cpj_journal','delete',true,'Batalkan jurnal'),
 ('JCP','REALIZED','VOID','cpj_journal','delete',true,'Batalkan jurnal');

-- Item PR yang bisa ditarik ke jurnal: PR disetujui / dipesan / diterima, belum dipakai di jurnal lain yang masih berlaku.
create or replace function public.cpj_pullable_pr_items()
returns table (pr_item_id uuid, pr_number text, pr_status text, item_name text, qty numeric, unit text, price numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_permission('cpj_journal','create') and not public.has_permission('cpj_journal','edit') then
    raise exception 'Tidak berhak' using errcode = '42501';
  end if;
  return query
  select i.id, p.doc_number, p.status, i.item_name, i.qty, u.name::text, coalesce(i.estimated_price, 0)::numeric
    from public.pr_items i
    join public.purchase_requests p on p.id = i.pr_id and p.deleted_at is null and p.status in ('APPROVED','ORDERED','RECEIVED')
    join public.units u on u.id = i.unit_id
   where not exists (
     select 1 from public.cash_journal_lines l join public.cash_journals j on j.id = l.journal_id and j.status <> 'VOID' and j.deleted_at is null
      where l.pr_item_id = i.id)
   order by p.doc_number, i.line_no;
end $$;
revoke all on function public.cpj_pullable_pr_items() from public, anon;
grant execute on function public.cpj_pullable_pr_items() to authenticated;


-- ===== 0021_pr_lines.sql =====
-- HMI Hub - Purchase Request per barang (lembar PR mingguan).
-- Satu lembar PR per minggu (nomor PR-{minggu 3 angka}-{bulan romawi}-{YY}); status dicatat PER BARANG:
-- DRAFT -> SUBMITTED (Purchasing mengajukan) -> APPROVED / REJECTED (Owner) -> ORDERED -> RECEIVED -> CLOSED (saat CPJ direalisasi)
-- CANCELLED bisa dari hampir semua status (kecuali barang sudah masuk jurnal CPJ yang berlaku).
-- Lembar lama (alur per dokumen) tetap ada; statusnya dipindahkan ke barang dan lembarnya tidak bisa diubah per barang.

-- ---------------------------------------------------------------
-- Kolom baru
-- ---------------------------------------------------------------
alter table public.purchase_requests drop constraint purchase_requests_status_check;
alter table public.purchase_requests add constraint purchase_requests_status_check check (status in
  ('OPEN','DRAFT','SUBMITTED','UNDER_REVIEW','APPROVED','REJECTED','ORDERED','RECEIVED','PAID','CLOSED'));

alter table public.pr_items
  add column status       text not null default 'DRAFT' check (status in
                          ('DRAFT','SUBMITTED','APPROVED','REJECTED','ORDERED','RECEIVED','CLOSED','CANCELLED')),
  add column ac           text not null default 'OPR' check (ac in ('OPR','RT','MKT','TOKO')),
  add column code         text not null default 'BP' check (btrim(code) <> ''),
  add column pay_method   text not null default 'tf',
  add column proof        text,
  add column item_date    date not null default (now() at time zone 'Asia/Jakarta')::date,
  add column requester_id uuid references public.user_profiles(id),
  add column unit         text,
  add column decided_by   uuid references public.user_profiles(id),
  add column decided_at   timestamptz,
  add column review_note  text;
alter table public.pr_items alter column unit_id drop not null;

-- Pindahkan data lama: status PR menjadi status barang
update public.pr_items i
   set requester_id = p.requester_id,
       item_date    = p.request_date,
       unit         = (select u.name from public.units u where u.id = i.unit_id),
       status       = case p.status
                        when 'DRAFT' then 'DRAFT'
                        when 'SUBMITTED' then 'SUBMITTED' when 'UNDER_REVIEW' then 'SUBMITTED'
                        when 'APPROVED' then 'APPROVED' when 'REJECTED' then 'REJECTED'
                        when 'ORDERED' then 'ORDERED' when 'RECEIVED' then 'RECEIVED'
                        else 'CLOSED' end
  from public.purchase_requests p where p.id = i.pr_id;
update public.pr_items i set status = 'CANCELLED'
  from public.purchase_requests p where p.id = i.pr_id and p.deleted_at is not null;
alter table public.pr_items alter column requester_id set not null;
create index pr_items_requester_idx on public.pr_items(requester_id);
create index pr_items_status_idx on public.pr_items(status);

alter table public.pr_status_history add column item_id uuid references public.pr_items(id);
create index pr_status_history_item_idx on public.pr_status_history(item_id);

-- ---------------------------------------------------------------
-- Hak lihat: pemilik barang melihat barangnya sendiri; yang punya izin "lihat semua PR" melihat semuanya
-- ---------------------------------------------------------------
drop policy purchase_requests_select on public.purchase_requests;
drop policy pr_items_select on public.pr_items;
drop policy pr_status_history_select on public.pr_status_history;

create policy pr_items_select on public.pr_items for select to authenticated
  using (public.has_permission('purchase_request','view')
         and (requester_id = auth.uid() or public.has_permission('purchase_request_all','view')));
create policy purchase_requests_select on public.purchase_requests for select to authenticated
  using (public.has_permission('purchase_request','view')
         and (requester_id = auth.uid() or public.has_permission('purchase_request_all','view')
              or exists (select 1 from public.pr_items i where i.pr_id = purchase_requests.id and i.requester_id = auth.uid())));
create policy pr_status_history_select on public.pr_status_history for select to authenticated
  using (exists (select 1 from public.purchase_requests p where p.id = pr_id));

-- ---------------------------------------------------------------
-- Fungsi lama (alur per dokumen) diganti
-- ---------------------------------------------------------------
drop function public.save_purchase_request(uuid,text,text,jsonb);
drop function public.pr_change_status(uuid,text,text);
drop function public.pr_discard(uuid);
drop function public.pr_set_item_supplier(uuid,uuid);

-- ---------------------------------------------------------------
-- Nomor lembar mingguan
-- ---------------------------------------------------------------
create or replace function public.pr_sheet_number(p_date date) returns text
language sql immutable as $$
  select format('PR-%s-%s-%s', lpad(public.cpj_week_of(p_date)::text, 3, '0'),
         (array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'])[extract(month from p_date)::int],
         to_char(p_date, 'YY'))
$$;

-- ---------------------------------------------------------------
-- Tambah barang ke lembar minggu itu (dibuat otomatis bila belum ada)
-- Barang baru selalu DRAFT. Tanggal selain hari ini hanya untuk yang berhak memproses (Purchasing / Owner).
-- ---------------------------------------------------------------
create or replace function public.pr_add_items(p_items jsonb, p_date date default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_date  date := coalesce(p_date, v_today);
  v_no    text;
  v_sheet public.purchase_requests%rowtype;
  v_it    jsonb;
  v_line  integer;
  v_id    uuid;
  v_desc  text; v_qty numeric; v_price numeric; v_unit text;
begin
  if not public.has_permission('purchase_request','create') then
    raise exception 'Anda tidak memiliki izin membuat Purchase Request' using errcode = '42501';
  end if;
  if v_date <> v_today and not public.has_permission('purchase_request','edit') then
    raise exception 'Barang hanya bisa ditambahkan ke lembar minggu ini' using errcode = '42501';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Isi minimal satu barang' using errcode = '22023';
  end if;

  v_no := public.pr_sheet_number(v_date);
  perform pg_advisory_xact_lock(hashtext(v_no));
  select * into v_sheet from public.purchase_requests where doc_number = v_no and deleted_at is null;
  if not found then
    insert into public.purchase_requests (doc_number, request_date, requester_id, department_id, reason, status)
    select v_no, v_date, v_uid, up.department_id, 'Lembar PR mingguan', 'OPEN'
      from public.user_profiles up where up.id = v_uid
    returning * into v_sheet;
  elsif v_sheet.status <> 'OPEN' then
    raise exception 'Lembar % memakai alur lama dan tidak bisa ditambah barang', v_no using errcode = '55000';
  end if;

  select coalesce(max(line_no), 0) into v_line from public.pr_items where pr_id = v_sheet.id;
  for v_it in select * from jsonb_array_elements(p_items) loop
    v_desc  := btrim(coalesce(v_it->>'item_name', ''));
    v_qty   := nullif(v_it->>'qty', '')::numeric;
    v_price := coalesce(nullif(v_it->>'price', '')::numeric, 0);
    v_unit  := btrim(coalesce(v_it->>'unit', ''));
    if v_desc = '' then raise exception 'Description wajib diisi' using errcode = '22023'; end if;
    if v_qty is null or v_qty <= 0 then raise exception 'Qty harus lebih dari 0' using errcode = '22023'; end if;
    if v_price < 0 then raise exception 'Harga tidak boleh negatif' using errcode = '22023'; end if;
    if v_unit = '' then raise exception 'Satuan wajib diisi' using errcode = '22023'; end if;
    v_line := v_line + 1;
    insert into public.pr_items (pr_id, line_no, item_name, qty, unit, estimated_price, ac, code, pay_method, item_date, requester_id, status)
    values (v_sheet.id, v_line, v_desc, v_qty, v_unit, v_price,
            coalesce(nullif(v_it->>'ac', ''), 'OPR'), coalesce(nullif(btrim(v_it->>'code'), ''), 'BP'),
            coalesce(nullif(btrim(v_it->>'pay_method'), ''), 'tf'), v_date, v_uid, 'DRAFT')
    returning id into v_id;
    insert into public.pr_status_history (pr_id, item_id, from_status, to_status, changed_by)
    values (v_sheet.id, v_id, null, 'DRAFT', v_uid);
  end loop;
  return v_sheet.id;
end $$;

-- ---------------------------------------------------------------
-- Ubah isian satu barang. Isian utama hanya saat DRAFT (pembuat atau Purchasing/Owner);
-- Pembelian dan bukti boleh diisi pemroses di status apa pun yang masih berjalan.
-- ---------------------------------------------------------------
create or replace function public.pr_update_item(p_id uuid, p_fields jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  i public.pr_items%rowtype;
  v_sheet_status text;
  v_edit boolean := public.has_permission('purchase_request','edit');
  v_main boolean := p_fields ?| array['item_name','qty','unit','price','ac','code','item_date'];
begin
  select * into i from public.pr_items where id = p_id for update;
  if not found then raise exception 'Barang tidak ditemukan' using errcode = 'P0002'; end if;
  select status into v_sheet_status from public.purchase_requests where id = i.pr_id and deleted_at is null;
  if v_sheet_status is null then raise exception 'Barang tidak ditemukan' using errcode = 'P0002'; end if;
  if v_sheet_status <> 'OPEN' then raise exception 'Lembar lama tidak bisa diubah per barang' using errcode = '55000'; end if;

  if v_main then
    if i.status <> 'DRAFT' then raise exception 'Isian barang hanya bisa diubah saat masih Draft' using errcode = '55000'; end if;
    if not ((i.requester_id = v_uid and public.has_permission('purchase_request','create')) or v_edit) then
      raise exception 'Anda tidak boleh mengubah barang ini' using errcode = '42501';
    end if;
  end if;
  if p_fields ?| array['pay_method','proof'] then
    if not (v_edit or (i.status = 'DRAFT' and i.requester_id = v_uid)) then
      raise exception 'Anda tidak memiliki izin memproses pembelian' using errcode = '42501';
    end if;
    if i.status in ('CANCELLED','REJECTED') then
      raise exception 'Barang yang dibatalkan atau ditolak tidak bisa diubah' using errcode = '55000';
    end if;
  end if;

  update public.pr_items set
    item_name       = case when p_fields ? 'item_name' then btrim(p_fields->>'item_name') else item_name end,
    qty             = case when p_fields ? 'qty' then (p_fields->>'qty')::numeric else qty end,
    unit            = case when p_fields ? 'unit' then btrim(p_fields->>'unit') else unit end,
    estimated_price = case when p_fields ? 'price' then coalesce(nullif(p_fields->>'price','')::numeric, 0) else estimated_price end,
    ac              = case when p_fields ? 'ac' then p_fields->>'ac' else ac end,
    code            = case when p_fields ? 'code' then coalesce(nullif(btrim(p_fields->>'code'), ''), 'BP') else code end,
    item_date       = case when p_fields ? 'item_date' then (p_fields->>'item_date')::date else item_date end,
    pay_method      = case when p_fields ? 'pay_method' then coalesce(nullif(btrim(p_fields->>'pay_method'), ''), 'tf') else pay_method end,
    proof           = case when p_fields ? 'proof' then nullif(btrim(p_fields->>'proof'), '') else proof end
   where id = p_id;
end $$;

-- ---------------------------------------------------------------
-- Pindah status beberapa barang sekaligus. Barang yang tidak cocok dilewati; hasilnya jumlah yang berpindah.
-- ---------------------------------------------------------------
create or replace function public.pr_move_items(p_ids uuid[], p_to text, p_note text default null)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_n   integer := 0;
  i     record;
  v_new text;
  v_in_journal boolean;
begin
  if not public.has_permission('purchase_request','view') then
    raise exception 'Anda tidak memiliki izin' using errcode = '42501';
  end if;
  if p_to not in ('SUBMITTED','APPROVED','REJECTED','ORDERED','RECEIVED','CANCELLED') then
    raise exception 'Status tujuan tidak dikenal' using errcode = '22023';
  end if;
  if p_to = 'SUBMITTED' and not public.has_permission('purchase_request','edit') then
    raise exception 'Hanya Purchasing yang boleh mengajukan ke Owner' using errcode = '42501';
  end if;
  if p_to in ('APPROVED','REJECTED') and not public.has_permission('purchase_request','approve') then
    raise exception 'Hanya Owner yang boleh menyetujui atau menolak' using errcode = '42501';
  end if;
  if p_to in ('ORDERED','RECEIVED') and not public.has_permission('purchase_request','edit') then
    raise exception 'Anda tidak memiliki izin memproses pembelian' using errcode = '42501';
  end if;
  if p_to = 'REJECTED' and btrim(coalesce(p_note, '')) = '' then
    raise exception 'Alasan penolakan wajib diisi' using errcode = '22023';
  end if;

  for i in
    select it.*, p.status as sheet_status from public.pr_items it
      join public.purchase_requests p on p.id = it.pr_id and p.deleted_at is null
     where it.id = any(p_ids) order by it.id for update of it
  loop
    continue when i.sheet_status <> 'OPEN';
    continue when not (
      (p_to = 'SUBMITTED' and i.status = 'DRAFT')
      or (p_to in ('APPROVED','REJECTED') and i.status = 'SUBMITTED')
      or (p_to = 'ORDERED' and i.status = 'APPROVED')
      or (p_to = 'RECEIVED' and i.status in ('APPROVED','ORDERED'))
      or (p_to = 'CANCELLED' and i.status in ('DRAFT','SUBMITTED','APPROVED','ORDERED','RECEIVED','REJECTED')));
    if p_to = 'CANCELLED' then
      continue when not (public.has_permission('purchase_request','delete')
                         or (i.status = 'DRAFT' and i.requester_id = v_uid and public.has_permission('purchase_request','create')));
      select exists (select 1 from public.cash_journal_lines l join public.cash_journals j on j.id = l.journal_id
                      where l.pr_item_id = i.id and j.status <> 'VOID' and j.deleted_at is null) into v_in_journal;
      continue when v_in_journal;
    end if;

    v_new := p_to;
    -- barang diterima yang sudah dibayar lewat CPJ yang direalisasi langsung CLOSED
    if p_to = 'RECEIVED' and exists (select 1 from public.cash_journal_lines l join public.cash_journals j on j.id = l.journal_id
                                      where l.pr_item_id = i.id and j.status = 'REALIZED' and j.deleted_at is null) then
      v_new := 'CLOSED';
    end if;

    update public.pr_items set status = v_new,
           decided_by  = case when p_to in ('APPROVED','REJECTED') then v_uid else decided_by end,
           decided_at  = case when p_to in ('APPROVED','REJECTED') then now() else decided_at end,
           review_note = case when p_to = 'REJECTED' then btrim(p_note) else review_note end
     where id = i.id;
    insert into public.pr_status_history (pr_id, item_id, from_status, to_status, note, changed_by)
    values (i.pr_id, i.id, i.status, v_new, nullif(btrim(coalesce(p_note, '')), ''), v_uid);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- Nomor CPJ yang memuat barang (untuk kolom CPJ di lembar PR). Hanya untuk id yang diberikan pemanggil.
create or replace function public.pr_item_journals(p_ids uuid[])
returns table (pr_item_id uuid, journal_number text, journal_status text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_permission('purchase_request','view') then
    raise exception 'Anda tidak memiliki izin' using errcode = '42501';
  end if;
  return query
  select l.pr_item_id, j.doc_number, j.status
    from public.cash_journal_lines l join public.cash_journals j on j.id = l.journal_id and j.status <> 'VOID' and j.deleted_at is null
   where l.pr_item_id = any(p_ids);
end $$;

revoke all on function public.pr_add_items(jsonb, date) from public, anon;
revoke all on function public.pr_update_item(uuid, jsonb) from public, anon;
revoke all on function public.pr_move_items(uuid[], text, text) from public, anon;
revoke all on function public.pr_item_journals(uuid[]) from public, anon;
grant execute on function public.pr_add_items(jsonb, date) to authenticated;
grant execute on function public.pr_update_item(uuid, jsonb) to authenticated;
grant execute on function public.pr_move_items(uuid[], text, text) to authenticated;
grant execute on function public.pr_item_journals(uuid[]) to authenticated;

-- ---------------------------------------------------------------
-- CPJ baru (JCP) membaca status per barang
-- ---------------------------------------------------------------
drop function public.cpj_pullable_pr_items();
create function public.cpj_pullable_pr_items()
returns table (pr_item_id uuid, pr_number text, pr_status text, item_name text, qty numeric, unit text, price numeric, ac text, code text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_permission('cpj_journal','create') and not public.has_permission('cpj_journal','edit') then
    raise exception 'Tidak berhak' using errcode = '42501';
  end if;
  return query
  select i.id, p.doc_number, i.status, i.item_name, i.qty, coalesce(i.unit, u.name)::text, coalesce(i.estimated_price, 0)::numeric, i.ac, i.code
    from public.pr_items i
    join public.purchase_requests p on p.id = i.pr_id and p.deleted_at is null
    left join public.units u on u.id = i.unit_id
   where i.status in ('APPROVED','ORDERED','RECEIVED')
     and not exists (
       select 1 from public.cash_journal_lines l join public.cash_journals j on j.id = l.journal_id and j.status <> 'VOID' and j.deleted_at is null
        where l.pr_item_id = i.id)
   order by p.doc_number, i.line_no;
end $$;
revoke all on function public.cpj_pullable_pr_items() from public, anon;
grant execute on function public.cpj_pullable_pr_items() to authenticated;

-- Realisasi selesai -> barang PR yang sudah diterima menjadi CLOSED. Batal setelah realisasi -> kembali RECEIVED.
create or replace function public.jcp_on_status() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.status = 'REALIZED' and old.status = 'ACC' then
    for r in
      select i.id, i.pr_id from public.cash_journal_lines l
        join public.pr_items i on i.id = l.pr_item_id
       where l.journal_id = new.id and i.status = 'RECEIVED'
    loop
      update public.pr_items set status = 'CLOSED' where id = r.id;
      insert into public.pr_status_history (pr_id, item_id, from_status, to_status, note, changed_by)
      values (r.pr_id, r.id, 'RECEIVED', 'CLOSED', 'Dibayar lewat ' || new.doc_number, auth.uid());
    end loop;
  elsif new.status = 'VOID' and old.status = 'REALIZED' then
    for r in
      select i.id, i.pr_id from public.cash_journal_lines l
        join public.pr_items i on i.id = l.pr_item_id
       where l.journal_id = new.id and i.status = 'CLOSED'
         and not exists (
           select 1 from public.cash_journal_lines l2
             join public.cash_journals j2 on j2.id = l2.journal_id and j2.status = 'REALIZED' and j2.deleted_at is null and j2.id <> new.id
            where l2.pr_item_id = i.id)
    loop
      update public.pr_items set status = 'RECEIVED' where id = r.id;
      insert into public.pr_status_history (pr_id, item_id, from_status, to_status, note, changed_by)
      values (r.pr_id, r.id, 'CLOSED', 'RECEIVED', 'Jurnal ' || new.doc_number || ' dibatalkan', auth.uid());
    end loop;
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------
-- Dashboard: barang PR yang menunggu persetujuan Owner
-- ---------------------------------------------------------------
create or replace function public.dashboard_summary()
returns jsonb
language plpgsql stable
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_month date := date_trunc('month', now() at time zone 'Asia/Jakarta')::date;
  out jsonb := '{}'::jsonb;
  v_n numeric; v_m numeric;
begin
  if public.has_permission('stock','view') then
    select count(*) into v_n from public.v_stock_summary where is_low;
    out := out || jsonb_build_object('low_stock', v_n);
  end if;
  if public.has_permission('purchase_request','approve') then
    select count(*) into v_n from public.pr_items i join public.purchase_requests p on p.id = i.pr_id and p.deleted_at is null
     where i.status = 'SUBMITTED';
    out := out || jsonb_build_object('pr_waiting', v_n);
  end if;
  if public.has_permission('production_order','approve') then
    select count(*) into v_n from public.production_orders where status = 'SUBMITTED' and deleted_at is null;
    out := out || jsonb_build_object('prod_waiting', v_n);
  end if;
  if public.has_permission('ro','view') then
    select count(*) into v_n from public.request_orders where status = 'CONFIRMED' and deleted_at is null;
    out := out || jsonb_build_object('ro_open', v_n);
  end if;
  if public.has_permission('packing_list','view') then
    select count(*) into v_n from public.packing_lists where status = 'PACKED' and deleted_at is null;
    out := out || jsonb_build_object('pl_on_the_way', v_n);
  end if;
  if public.has_permission('invoice','view') then
    select coalesce(sum(outstanding),0), coalesce(sum(outstanding) filter (where days_overdue > 0),0)
      into v_n, v_m from public.v_receivables;
    out := out || jsonb_build_object('receivable_total', v_n, 'receivable_overdue', v_m);
  end if;
  if public.has_permission('crj','view') then
    select coalesce(sum(amount),0) into v_n from public.cash_receipts
     where status = 'POSTED' and deleted_at is null and receipt_date >= v_month and receipt_date <= v_today;
    out := out || jsonb_build_object('cash_in_month', v_n);
  end if;
  if public.has_permission('cpj','view') then
    select coalesce(sum(amount),0) into v_n from public.cash_payments
     where status = 'POSTED' and deleted_at is null and pay_date >= v_month and pay_date <= v_today;
    out := out || jsonb_build_object('cash_out_month', v_n);
  end if;
  return out;
end;
$$;

-- ---------------------------------------------------------------
-- Izin: Accounting melihat semua PR (dipakai menyusun CPJ); Purchasing boleh unduh PDF/Excel PR
-- ---------------------------------------------------------------
create or replace function pg_temp.g(p_role text, p_module text, p_actions text[]) returns void language sql as $f$
  insert into public.role_permissions (role_id, permission_id) select r.id, p.id from public.roles r, public.permissions p
   where r.code = p_role and p.module = p_module and p.action = any(p_actions) on conflict do nothing;
$f$;
select pg_temp.g('ACCOUNTING','purchase_request_all','{view}');
select pg_temp.g('PURCHASING','purchase_request','{export}');
select pg_temp.g('ACCOUNTING','purchase_request','{export}');


-- ===== 0022_ap_sheet.sql =====
-- HMI Hub - Analisa Pembelian mengikuti contoh ANALISA_PEMBELIAN (satu analisa untuk satu atau beberapa ekor sapi).
-- Nomor: {urut 3 angka per tahun}-{SUPPLIER}-{JENIS SAPI}-{bulan romawi}-{YY}, mis. 001-AINUL-BX-IV-26.
-- Perubahan: supplier, jenis sapi, TOP, nomor invoice supplier, banyak sapi per analisa (ap_cows), penjualan non-karkas
-- diketik di analisa (ap_nonk), Lower Side / UpperSide, dan Total Biaya yang boleh diisi manual.

-- ---------------------------------------------------------------
-- Kolom header baru
-- ---------------------------------------------------------------
alter table public.purchase_analyses
  add column supplier_id        uuid references public.suppliers(id),
  add column cow_type_id        uuid references public.cow_types(id),
  add column top_date           date,
  add column supplier_invoice   text,
  add column lower_side         numeric(12,3) check (lower_side is null or lower_side >= 0),
  add column upper_side         numeric(12,3) check (upper_side is null or upper_side >= 0),
  add column manual_total_cost  numeric(18,2) check (manual_total_cost is null or manual_total_cost >= 0),
  alter column cw_id drop not null;   -- analisa lama masih menyimpan cw_id; analisa baru memakai ap_cows
drop index public.purchase_analyses_cw_uq;

-- ---------------------------------------------------------------
-- Sapi yang dianalisa (dari Penimbangan Karkas)
-- ---------------------------------------------------------------
create table public.ap_cows (
  id       uuid primary key default gen_random_uuid(),
  ap_id    uuid not null references public.purchase_analyses(id),
  line_no  integer not null,
  cw_id    uuid not null references public.carcass_weighings(id),
  unique (ap_id, line_no), unique (ap_id, cw_id)
);
create index ap_cows_ap_idx on public.ap_cows(ap_id);
create index ap_cows_cw_idx on public.ap_cows(cw_id);

-- Penjualan non-karkas (Babat, Lemak, Kepala, Kaki, Kulit, ...): diketik di analisa. Berat boleh kosong.
create table public.ap_nonk (
  id         uuid primary key default gen_random_uuid(),
  ap_id      uuid not null references public.purchase_analyses(id),
  line_no    integer not null,
  name       text not null check (btrim(name) <> ''),
  weight     numeric(12,3) check (weight is null or weight >= 0),
  unit_price numeric(18,2) not null default 0 check (unit_price >= 0),
  unique (ap_id, line_no)
);
create index ap_nonk_ap_idx on public.ap_nonk(ap_id);

-- Analisa lama: satu sapi (cw_id) menjadi satu baris ap_cows; supplier dan jenis sapi ikut penimbangan.
insert into public.ap_cows (ap_id, line_no, cw_id) select id, 1, cw_id from public.purchase_analyses where cw_id is not null;
update public.purchase_analyses a set supplier_id = w.supplier_id, cow_type_id = w.cow_type_id
  from public.carcass_weighings w where w.id = a.cw_id;

select public.attach_child_standard('ap_cows', 'purchase_analysis');
select public.attach_child_standard('ap_nonk', 'purchase_analysis');

-- ---------------------------------------------------------------
-- Penomoran
-- ---------------------------------------------------------------
create table public.ap_sequences (yy text primary key, last_number integer not null default 0);
alter table public.ap_sequences enable row level security;
create or replace function public.ap_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_n integer; v_sup text; v_type text;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
begin
  if new.doc_number is not null then return new; end if;
  select upper(regexp_replace(name, '[^A-Za-z0-9]', '', 'g')) into v_sup from public.suppliers where id = new.supplier_id;
  select upper(regexp_replace(code, '[^A-Za-z0-9]', '', 'g')) into v_type from public.cow_types where id = new.cow_type_id;
  insert into public.ap_sequences as s (yy, last_number) values (to_char(new.analysis_date, 'YY'), 1)
  on conflict (yy) do update set last_number = s.last_number + 1
  returning last_number into v_n;
  new.doc_number := format('%s-%s-%s-%s-%s', lpad(v_n::text, 3, '0'), coalesce(nullif(v_sup, ''), 'SUPPLIER'), coalesce(nullif(v_type, ''), 'SAPI'),
                           v_roman[extract(month from new.analysis_date)::int], to_char(new.analysis_date, 'YY'));
  return new;
end $$;
revoke all on function public.ap_assign_number() from public, anon, authenticated;
drop trigger purchase_analyses_docno on public.purchase_analyses;
create trigger purchase_analyses_docno before insert on public.purchase_analyses
  for each row execute function public.ap_assign_number();

-- ---------------------------------------------------------------
-- Pemeriksaan
-- ---------------------------------------------------------------
create or replace function public.ap_before() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.supplier_id is null and (tg_op = 'INSERT' or old.supplier_id is not null) then
    raise exception 'Supplier wajib diisi' using errcode = '22023';
  end if;
  if new.cow_type_id is null and (tg_op = 'INSERT' or old.cow_type_id is not null) then
    raise exception 'Jenis sapi wajib diisi' using errcode = '22023';
  end if;
  return new;
end $$;

-- Sapi harus sudah final dan tidak boleh dipakai analisa lain yang masih berlaku.
create or replace function public.ap_cows_check() returns trigger language plpgsql security definer set search_path = public as $$
declare v_st text;
begin
  perform pg_advisory_xact_lock(hashtext('ap_cow:' || new.cw_id::text));
  select status into v_st from public.carcass_weighings where id = new.cw_id and deleted_at is null;
  if v_st is distinct from 'FINAL' then
    raise exception 'Analisa hanya bisa dibuat setelah penimbangan karkas selesai (final)' using errcode = '22023';
  end if;
  if exists (select 1 from public.ap_cows c join public.purchase_analyses a on a.id = c.ap_id
              where c.cw_id = new.cw_id and c.ap_id <> new.ap_id and a.status <> 'VOID' and a.deleted_at is null) then
    raise exception 'Sapi ini sudah dipakai di analisa lain' using errcode = '23505';
  end if;
  return new;
end $$;
create trigger ap_cows_check before insert or update of cw_id on public.ap_cows
  for each row execute function public.ap_cows_check();

create or replace function public.ap_on_final() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'FINAL' and old.status = 'DRAFT' then
    if not exists (select 1 from public.ap_cows where ap_id = new.id) then
      raise exception 'Analisa belum memiliki sapi' using errcode = '22023';
    end if;
    if not exists (select 1 from public.ap_items where ap_id = new.id) then
      raise exception 'Analisa belum memiliki item produk' using errcode = '22023';
    end if;
  end if;
  return new;
end $$;

-- Penimbangan final tidak boleh dibatalkan selama masih dipakai analisa yang berlaku.
create or replace function public.cw_on_status() returns trigger language plpgsql security definer set search_path = public as $$
declare i record; v_meat numeric;
begin
  if new.status = 'FINAL' and old.status = 'DRAFT' then
    select coalesce(sum(weight), 0) into v_meat from public.cw_items where cw_id = new.id and product_id is not null;
    if not exists (select 1 from public.cw_items where cw_id = new.id) then
      raise exception 'Penimbangan belum memiliki hasil potongan' using errcode = '22023';
    end if;
    if v_meat > new.carcass_weight then
      raise exception 'Total berat daging (% kg) melebihi berat karkas (% kg)', v_meat, new.carcass_weight using errcode = '22023';
    end if;
    for i in select * from public.cw_items where cw_id = new.id and product_id is not null loop
      perform public.post_stock(i.product_id, new.warehouse_id, 'IN_PRODUCTION', i.weight, null, 'CW', new.id,
                                'Penimbangan karkas ' || new.doc_number, new.weigh_date);
    end loop;
  elsif new.status = 'VOID' and old.status = 'FINAL' then
    if exists (select 1 from public.ap_cows c join public.purchase_analyses a on a.id = c.ap_id
                where c.cw_id = new.id and a.status <> 'VOID' and a.deleted_at is null) then
      raise exception 'Batalkan Analisa Pembelian terkait terlebih dahulu' using errcode = '55000';
    end if;
    for i in select * from public.cw_items where cw_id = new.id and product_id is not null loop
      perform public.post_stock(i.product_id, new.warehouse_id, 'REVERSAL_OUT', -i.weight, null, 'CW', new.id,
                                'Batal penimbangan ' || new.doc_number);
    end loop;
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------
-- Hasil analisa
-- karkas % = karkas / hidup; Daging = berat item berkategori Daging; daging % = daging / karkas;
-- harga karkas = harga sapi / karkas; Total Biaya = isian manual, atau harga sapi + biaya operasional.
-- ---------------------------------------------------------------
drop view public.v_purchase_analysis;
create view public.v_purchase_analysis as
select a.id, a.doc_number, a.status, a.analysis_date, a.notes, a.total_purchase,
       a.supplier_id, a.cow_type_id, a.top_date, a.supplier_invoice, a.lower_side, a.upper_side,
       w.cow_number, w.live_weight, w.carcass_weight,
       case when w.live_weight > 0 then round(w.carcass_weight / w.live_weight * 100, 2) end            as carcass_pct,
       coalesce(i.meat_weight, 0)                                                                         as meat_weight,
       case when w.carcass_weight > 0 then round(coalesce(i.meat_weight, 0) / w.carcass_weight * 100, 2) end as meat_pct,
       case when w.carcass_weight > 0 then round(a.total_purchase / w.carcass_weight, 2) end             as carcass_price_per_kg,
       coalesce(i.revenue, 0)                                                                             as revenue,
       coalesce(n.amount, 0)                                                                              as noncarcass_amount,
       coalesce(c.cost_total, 0)                                                                          as cost_total,
       coalesce(a.manual_total_cost, a.total_purchase + coalesce(c.cost_total, 0))                        as total_cost,
       coalesce(i.revenue, 0) + coalesce(n.amount, 0) - coalesce(a.manual_total_cost, a.total_purchase + coalesce(c.cost_total, 0)) as profit
  from public.purchase_analyses a
  left join (select ac.ap_id, string_agg(cw.cow_number, ', ' order by ac.line_no) cow_number, sum(cw.live_weight) live_weight, sum(cw.carcass_weight) carcass_weight
               from public.ap_cows ac join public.carcass_weighings cw on cw.id = ac.cw_id group by ac.ap_id) w on w.ap_id = a.id
  left join (select it.ap_id, sum(it.weight) filter (where pc.code = 'DAGING') meat_weight, sum(it.weight * it.unit_price) revenue
               from public.ap_items it join public.products p on p.id = it.product_id left join public.product_categories pc on pc.id = p.category_id group by it.ap_id) i on i.ap_id = a.id
  left join (select ap_id, sum(amount) cost_total from public.ap_costs group by ap_id) c on c.ap_id = a.id
  left join (select ap_id, sum(coalesce(weight, 0) * unit_price) amount from public.ap_nonk group by ap_id) n on n.ap_id = a.id
 where a.deleted_at is null and public.has_permission('purchase_analysis','view');
revoke all on public.v_purchase_analysis from public, anon;
grant select on public.v_purchase_analysis to authenticated;

-- ---------------------------------------------------------------
-- Registry
-- ---------------------------------------------------------------
update public.doc_registry set
  header_cols = '{analysis_date,supplier_id,cow_type_id,top_date,supplier_invoice,total_purchase,lower_side,upper_side,manual_total_cost,notes}',
  children = '[{"key":"cows","table":"ap_cows","fk":"ap_id","cols":["cw_id"]},{"key":"items","table":"ap_items","fk":"ap_id","cols":["product_id","weight","unit_price","price_source"]},{"key":"nonk","table":"ap_nonk","fk":"ap_id","cols":["name","weight","unit_price"]},{"key":"costs","table":"ap_costs","fk":"ap_id","cols":["cost_type_id","amount","note"]}]'
 where doc_type = 'AP';

-- Urutan berikutnya pada tahun tertentu (untuk pratinjau nomor di form; nomor resmi dibuat saat disimpan).
create or replace function public.ap_next_seq(p_yy text) returns integer
language sql stable security definer set search_path = public as $$
  select case when public.has_permission('purchase_analysis', 'view') then coalesce((select last_number from public.ap_sequences where yy = p_yy), 0) + 1 end;
$$;
revoke all on function public.ap_next_seq(text) from public, anon;
grant execute on function public.ap_next_seq(text) to authenticated;


-- ===== 0023_cw_sheet.sql =====
-- HMI Hub - Penimbangan Karkas mengikuti preview: berat hidup dan jenis sapi opsional, nomor CW-001-KODESAPI-IV-26,
-- item diketik bebas dengan kategori (Daging/Tulang/Jeroan/Non-Karkas); item yang belum ada di master dibuat otomatis.

alter table public.carcass_weighings
  alter column cow_type_id drop not null,
  alter column live_weight drop not null;   -- cek live_weight > 0 dan karkas <= hidup tetap berlaku bila diisi

-- Nomor: CW-{urut 3 angka}-{KODE SAPI}-{bulan romawi}-{YY}. Urutan berjalan terus (tidak mulai ulang tiap tahun), melanjutkan jumlah CW yang sudah ada.
create table public.cw_counter (id boolean primary key default true check (id), last_number integer not null);
insert into public.cw_counter (id, last_number) select true, count(*) from public.carcass_weighings;
alter table public.cw_counter enable row level security;
create or replace function public.cw_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_n integer; v_code text;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
begin
  if new.doc_number is not null then return new; end if;
  update public.cw_counter set last_number = last_number + 1 returning last_number into v_n;
  v_code := upper(regexp_replace(coalesce(new.cow_number, ''), '[^A-Za-z0-9]', '', 'g'));
  new.doc_number := format('CW-%s-%s-%s-%s', lpad(v_n::text, 3, '0'), coalesce(nullif(v_code, ''), 'KODE'),
                           v_roman[extract(month from new.weigh_date)::int], to_char(new.weigh_date, 'YY'));
  return new;
end $$;
revoke all on function public.cw_assign_number() from public, anon, authenticated;
drop trigger carcass_weighings_docno on public.carcass_weighings;
create trigger carcass_weighings_docno before insert on public.carcass_weighings
  for each row execute function public.cw_assign_number();

-- Mengubah daftar [{name, cat}] menjadi id master. Nama yang sudah ada dipakai apa adanya (tanpa mengubah kategorinya);
-- nama baru dibuat di master dengan kategori yang dipilih. cat: Daging, Tulang, Jeroan (produk, masuk stok) atau Non-Karkas.
create or replace function public.cw_resolve_items(p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  e jsonb; v_name text; v_cat text; v_pid uuid; v_nid uuid; v_code text; v_i int; v_out jsonb := '[]'::jsonb;
  v_cat_code text; v_cat_id uuid; v_unit uuid;
begin
  if not (public.has_permission('carcass_weighing', 'create') or public.has_permission('carcass_weighing', 'edit')) then
    raise exception 'Anda tidak memiliki izin menyimpan penimbangan' using errcode = '42501';
  end if;
  for e in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    v_name := btrim(coalesce(e->>'name', '')); v_cat := coalesce(e->>'cat', 'Daging'); v_pid := null; v_nid := null;
    if v_name = '' or length(v_name) > 100 then raise exception 'Nama item tidak valid' using errcode = '22023'; end if;
    select id into v_pid from public.products where lower(name) = lower(v_name);
    if v_pid is null then select id into v_nid from public.non_carcass_types where lower(name) = lower(v_name); end if;
    if v_pid is null and v_nid is null then
      v_code := trim(both '-' from left(upper(regexp_replace(v_name, '[^A-Za-z0-9]+', '-', 'g')), 30));
      if v_code = '' then v_code := 'ITEM'; end if;
      v_i := 0;
      if v_cat = 'Non-Karkas' then
        while exists (select 1 from public.non_carcass_types where code = case when v_i = 0 then v_code else v_code || '-' || v_i end) loop v_i := v_i + 1; end loop;
        insert into public.non_carcass_types (code, name) values (case when v_i = 0 then v_code else v_code || '-' || v_i end, v_name) returning id into v_nid;
      else
        v_cat_code := case v_cat when 'Tulang' then 'TULANG' when 'Jeroan' then 'JEROHAN' when 'Daging' then 'DAGING' else null end;
        if v_cat_code is null then raise exception 'Kategori item tidak dikenal' using errcode = '22023'; end if;
        select id into v_cat_id from public.product_categories where code = v_cat_code;
        select id into v_unit from public.units where code = 'KG';
        if v_unit is null then raise exception 'Satuan KG belum ada di master' using errcode = '22023'; end if;
        while exists (select 1 from public.products where code = case when v_i = 0 then v_code else v_code || '-' || v_i end) loop v_i := v_i + 1; end loop;
        insert into public.products (code, name, product_type, category_id, unit_id)
        values (case when v_i = 0 then v_code else v_code || '-' || v_i end, v_name, 'MANUFACTURE', v_cat_id, v_unit) returning id into v_pid;
      end if;
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('product_id', v_pid, 'non_carcass_type_id', v_nid));
  end loop;
  return v_out;
end $$;
revoke all on function public.cw_resolve_items(jsonb) from public, anon;
grant execute on function public.cw_resolve_items(jsonb) to authenticated;

-- Urutan CW berikutnya (untuk pratinjau nomor di form; nomor resmi dibuat saat disimpan).
create or replace function public.cw_next_seq() returns integer
language sql stable security definer set search_path = public as $$
  select case when public.has_permission('carcass_weighing', 'view') then (select last_number from public.cw_counter where id) + 1 end;
$$;
revoke all on function public.cw_next_seq() from public, anon;
grant execute on function public.cw_next_seq() to authenticated;


-- ===== 0024_ncs_per_cow.sql =====
-- HMI Hub - Nota Penjualan Non-Karkas: satu nota aktif untuk satu sapi (penimbangan karkas).
-- Nota yang dibatalkan (VOID) atau dihapus tidak dihitung, jadi sapi yang sama bisa dibuatkan nota baru.
do $$
begin
  if exists (select 1 from public.noncarcass_sales where cw_id is not null and status <> 'VOID' and deleted_at is null group by cw_id having count(*) > 1) then
    raise notice 'Ada sapi dengan lebih dari satu nota non-karkas aktif; batasan satu nota per sapi tidak dipasang. Batalkan nota gandanya lalu jalankan ulang migrasi ini.';
  else
    create unique index if not exists noncarcass_sales_cw_active_uq on public.noncarcass_sales (cw_id)
      where cw_id is not null and status <> 'VOID' and deleted_at is null;
  end if;
end $$;
