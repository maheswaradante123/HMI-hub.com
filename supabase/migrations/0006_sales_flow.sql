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
