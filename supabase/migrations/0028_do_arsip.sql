-- Surat Jalan arsip (dokumen lama): boleh tanpa Packing List dan membawa daftar barangnya sendiri.
-- Surat jalan baru dari aplikasi tetap WAJIB punya Packing List (is_legacy hanya bisa diisi lewat skrip migrasi,
-- bukan lewat form: kolomnya tidak ada di daftar kolom dokumen DO).
alter table public.delivery_orders alter column pl_id drop not null;
alter table public.delivery_orders add column is_legacy boolean not null default false;
alter table public.delivery_orders add constraint do_pl_required check (pl_id is not null or is_legacy);

create table public.do_legacy_items (
  id          uuid primary key default gen_random_uuid(),
  do_id       uuid not null references public.delivery_orders(id),
  line_no     integer not null,
  description text,
  item_type   text,
  qty_text    text,
  unique (do_id, line_no)
);
create index do_legacy_items_do_idx on public.do_legacy_items(do_id);
select public.attach_child_standard('do_legacy_items', 'delivery_order');

create or replace function public.do_before() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_pl record;
begin
  new.scan_url := nullif(btrim(coalesce(new.scan_url, '')), '');
  if tg_op = 'INSERT' then
    if new.pl_id is null then
      if not new.is_legacy then raise exception 'Surat jalan harus dibuat dari Packing List' using errcode = '22023'; end if;
      return new;
    end if;
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
  if new.is_legacy is distinct from old.is_legacy then
    raise exception 'Status dokumen arsip tidak bisa diubah' using errcode = '22023';
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
