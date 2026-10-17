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
