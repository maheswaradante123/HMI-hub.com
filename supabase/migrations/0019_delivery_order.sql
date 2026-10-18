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
