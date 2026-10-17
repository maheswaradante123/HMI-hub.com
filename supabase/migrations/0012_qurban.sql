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
