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
