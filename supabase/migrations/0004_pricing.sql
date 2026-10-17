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
