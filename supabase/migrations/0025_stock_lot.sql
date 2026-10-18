-- HMI Hub - Stok per kode sapi (lot), mengikuti preview: tiap mutasi boleh membawa kode sapi, dan tiap item punya
-- rincian Asal Sapi (masuk, keluar, sisa). Buku mutasi lama tidak diubah: mutasi dari penimbangan karkas (CW) otomatis
-- dikenali dari dokumennya, dan keluaran tanpa kode sapi dibebankan ke sapi tertua lebih dulu (FIFO) saat ditampilkan.

alter table public.stock_movements add column lot text check (lot is null or (lot = upper(btrim(lot)) and lot <> ''));
create index stock_movements_lot_idx on public.stock_movements (product_id, lot);

-- Kode sapi efektif tiap mutasi: kolom lot bila ada; untuk mutasi CW lama, kode sapi pada penimbangannya.
create view public.v_stock_ledger with (security_invoker = true) as
  select m.id, m.product_id, m.warehouse_id, m.movement_date, m.movement_type, m.qty, m.unit_cost, m.ref_type, m.ref_id, m.note,
         m.created_at, m.created_by,
         coalesce(m.lot, case when m.ref_type = 'CW' then (select upper(btrim(w.cow_number)) from public.carcass_weighings w where w.id = m.ref_id) end) as lot
    from public.stock_movements m;
grant select on public.v_stock_ledger to authenticated;

-- Asal sapi per item. Mutasi tanpa kode sapi yang bersih-bersih keluar (mis. packing list) memakai sisa sapi tertua lebih dulu.
create view public.v_stock_lots with (security_invoker = true) as
  with t as (
    select product_id, lot,
           sum(case when qty > 0 then qty else 0 end) as qty_in,
           sum(case when qty < 0 then -qty else 0 end) as qty_out,
           min(case when qty > 0 then movement_date end) as first_in
      from public.v_stock_ledger where lot is not null group by product_id, lot
  ), u as (
    select product_id, sum(case when qty > 0 then qty else 0 end) as pos, sum(case when qty < 0 then -qty else 0 end) as neg
      from public.v_stock_ledger where lot is null group by product_id
  ), r as (
    select t.*, greatest(t.qty_in - t.qty_out, 0) as pos_rest,
           coalesce(sum(greatest(t.qty_in - t.qty_out, 0)) over (partition by t.product_id order by t.first_in nulls last, t.lot
                    rows between unbounded preceding and 1 preceding), 0) as before_rest,
           greatest(coalesce(u.neg, 0) - coalesce(u.pos, 0), 0) as consume
      from t left join u on u.product_id = t.product_id
  ), x as (
    select product_id, lot, first_in, qty_in, qty_out, pos_rest, least(pos_rest, greatest(consume - before_rest, 0)) as take from r
  )
  select product_id, lot, first_in, qty_in::numeric(14,3), (qty_out + take)::numeric(14,3) as qty_out,
         (qty_in - qty_out - take)::numeric(14,3) as qty_rest
    from x
  union all
  select u.product_id, null::text, null::date, u.pos::numeric(14,3),
         (u.pos - greatest(u.pos - u.neg, 0))::numeric(14,3) as qty_out, greatest(u.pos - u.neg, 0)::numeric(14,3)
    from u where u.pos > 0;
grant select on public.v_stock_lots to authenticated;

-- post_stock dan record_stock_movement menerima kode sapi (opsional).
drop function public.post_stock(uuid,uuid,text,numeric,numeric,text,uuid,text,date);
create or replace function public.post_stock(
  p_product uuid, p_wh uuid, p_type text, p_qty numeric, p_cost numeric,
  p_ref_type text, p_ref_id uuid, p_note text, p_date date default null, p_lot text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_bal  numeric;
  v_name text;
  v_lot  text := nullif(upper(btrim(coalesce(p_lot, ''))), '');
  v_rest numeric;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_product::text || p_wh::text, 0));
  if p_qty < 0 then
    select coalesce(sum(qty), 0) into v_bal from public.stock_movements where product_id = p_product and warehouse_id = p_wh;
    if v_bal + p_qty < 0 then
      select name into v_name from public.products where id = p_product;
      raise exception 'Stok % tidak cukup (tersedia %, diminta %)', v_name, v_bal, -p_qty using errcode = '22023';
    end if;
    if v_lot is not null then
      select coalesce(sum(qty_rest), 0) into v_rest from public.v_stock_lots where product_id = p_product and lot = v_lot;
      if v_rest + p_qty < 0 then
        select name into v_name from public.products where id = p_product;
        raise exception 'Stok % dari sapi % tidak cukup (sisa %, diminta %)', v_name, v_lot, v_rest, -p_qty using errcode = '22023';
      end if;
    end if;
  end if;
  insert into public.stock_movements (product_id, warehouse_id, movement_date, movement_type, qty, unit_cost, ref_type, ref_id, note, lot)
  values (p_product, p_wh, coalesce(p_date, (now() at time zone 'Asia/Jakarta')::date), p_type, p_qty, p_cost, p_ref_type, p_ref_id, p_note, v_lot);
end;
$$;
revoke all on function public.post_stock(uuid,uuid,text,numeric,numeric,text,uuid,text,date,text) from public, anon, authenticated;

drop function public.record_stock_movement(uuid,uuid,text,numeric,numeric,text,date);
create or replace function public.record_stock_movement(
  p_product uuid, p_wh uuid, p_type text, p_qty numeric, p_cost numeric, p_note text, p_date date default null, p_lot text default null)
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
  if length(btrim(coalesce(p_lot, ''))) > 40 then
    raise exception 'Kode sapi terlalu panjang (maksimal 40 huruf)' using errcode = '22023';
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
    p_cost, 'MANUAL', null, nullif(btrim(coalesce(p_note,'')), ''), p_date, p_lot);
end;
$$;
revoke all on function public.record_stock_movement(uuid,uuid,text,numeric,numeric,text,date,text) from public, anon;
grant execute on function public.record_stock_movement(uuid,uuid,text,numeric,numeric,text,date,text) to authenticated;
