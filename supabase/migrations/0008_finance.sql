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
