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
