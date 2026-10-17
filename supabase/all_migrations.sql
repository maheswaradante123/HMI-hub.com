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
