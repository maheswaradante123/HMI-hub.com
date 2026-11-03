-- Tarif perawatan tetap per pesanan.
-- Biasanya tagihan bulanan memakai tarif kelas berdasarkan timbangan terakhir. Pesanan yang dinego dengan tarif
-- perawatan tetap per hari (contoh Dedi Trimulyanto #192: Rp50.000/hari) ditandai care_fixed: tagihan bulanan
-- selalu memakai care_price pesanan itu, berapa pun bobot timbangannya.

alter table public.qurban_orders add column care_fixed boolean not null default false;

-- Tampilan pesanan ikut membawa kolom baru (o.* dibaca saat tampilan dibuat).
drop view public.v_qurban_orders;
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
  if v_cls.id is null and not v.care_fixed then
    raise exception 'Bobot timbang terakhir di bawah 350 Kg tidak ada di daftar harga' using errcode = '22023';
  end if;
  v_days := public.qurban_days(v_ym, v.start_date, v_end);
  v_no := 'INV-' || lpad(public.qurban_next('INV', v_today)::text, 3, '0') || '-' ||
          public.qurban_roman(extract(month from v_today)::integer) || '-' || to_char(v_today, 'YY');
  insert into public.qurban_bills (order_id, bill_no, ym, days, rate, basis_weight, bill_date, due_date)
  values (p_id, v_no, v_ym, v_days, case when v.care_fixed then v.care_price else v_cls.care_price end, v_basis, v_today, v_today + 7);
  return v_no;
end $$;

create or replace function public.qurban_set_care_fixed(p_id uuid, p_fixed boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare v public.qurban_orders%rowtype;
begin
  perform public.qurban_need('qurban','approve','Tarif perawatan tetap hanya boleh diatur oleh Owner');
  select * into v from public.qurban_orders where id = p_id and deleted_at is null for update;
  if not found then raise exception 'Pesanan tidak ditemukan' using errcode = 'P0002'; end if;
  if v.status = 'CANCELLED' then
    raise exception 'Pesanan sudah dibatalkan' using errcode = '55000';
  end if;
  if p_fixed is null then raise exception 'Pilihan tidak valid' using errcode = '22023'; end if;
  update public.qurban_orders set care_fixed = p_fixed where id = p_id;
end $$;
revoke all on function public.qurban_set_care_fixed(uuid, boolean) from public, anon;
grant execute on function public.qurban_set_care_fixed(uuid, boolean) to authenticated;
