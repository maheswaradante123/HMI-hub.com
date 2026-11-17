-- Qurban Cerdas: sapi jogrok = dijual per ekor (harga tetap), bukan per timbangan.
-- Pesanan jogrok: sale_mode = 'HEAD'. buy_price menyimpan harga per EKOR, buyback_price nilai beli kembali per EKOR,
-- care_price tarif perawatan tetap per hari (care_fixed = true), bobot awal boleh kosong dan tidak memengaruhi harga.
-- Pesanan lama tetap 'WEIGHT' (harga per Kg x bobot) dan tidak berubah.

alter table public.qurban_orders add column sale_mode text not null default 'WEIGHT' check (sale_mode in ('WEIGHT','HEAD'));
alter table public.qurban_orders alter column initial_weight drop not null;
alter table public.qurban_orders add constraint qurban_orders_weight_mode check (sale_mode = 'HEAD' or initial_weight is not null);

-- Rincian invoice: jogrok = 1 Ekor x harga per ekor.
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
  select 1, 'Sapi Nomor ' || o.cow_no,
         case when o.sale_mode = 'HEAD' then 1::numeric else o.initial_weight end,
         case when o.sale_mode = 'HEAD' then 'Ekor' else 'Kg' end::text, o.buy_price from o
  union all
  select months.rn + 1, 'Perawatan Bulan ' || public.qurban_month_name(months.ym),
         public.qurban_days(months.ym, o.start_date, e.d)::numeric, 'Hari'::text, o.care_price
    from o, e, months
   order by 1
$$;

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

-- Buat pesanan. Tiap sapi: {"cow","weight"} (per timbangan) atau {"cow","head_price","care_price","buyback_price","weight"?} (jogrok).
create or replace function public.qurban_create_orders(p_nick text, p_start date, p_mode text, p_cows jsonb)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_today date := public.qurban_today();
  v_end   date := public.qurban_setting('care_end')::date;
  v_cls   public.qurban_price_classes;
  v_n     integer;
  v_pro   text;
  v_group uuid;
  v_id    uuid;
  v_first uuid;
  e       jsonb;
  v_cow   text;
  v_w     numeric;
  v_head  numeric; v_care numeric; v_back numeric;
  v_seen  text[] := '{}';
begin
  perform public.qurban_need('qurban','create','Anda tidak memiliki izin membuat pesanan Qurban');
  if btrim(coalesce(p_nick,'')) = '' then
    raise exception 'Nama pelanggan dan nomor sapi wajib diisi' using errcode = '22023';
  end if;
  if p_mode not in ('FULL','MONTHLY') then
    raise exception 'Cara pembayaran perawatan tidak valid' using errcode = '22023';
  end if;
  if p_cows is null or jsonb_typeof(p_cows) <> 'array' then
    raise exception 'Isi minimal satu sapi' using errcode = '22023';
  end if;
  v_n := jsonb_array_length(p_cows);
  if v_n < 1 then raise exception 'Isi minimal satu sapi' using errcode = '22023'; end if;
  if v_n > 20 then raise exception 'Maksimal 20 sapi dalam satu proforma' using errcode = '22023'; end if;
  if p_start is null or p_start > v_end then
    raise exception 'Tanggal mulai pemeliharaan tidak valid atau melewati akhir masa perawatan' using errcode = '22023';
  end if;

  -- periksa semua sapi dulu supaya tidak ada pesanan setengah jadi
  for e in select * from jsonb_array_elements(p_cows) loop
    v_cow := btrim(coalesce(e->>'cow', ''));
    if v_cow = '' then raise exception 'Nama pelanggan dan nomor sapi wajib diisi' using errcode = '22023'; end if;
    if lower(v_cow) = any (v_seen) then
      raise exception 'Nomor sapi % diisi dua kali dalam satu proforma', v_cow using errcode = '22023';
    end if;
    v_seen := v_seen || lower(v_cow);
    begin v_w := nullif(e->>'weight', '')::numeric; exception when others then v_w := -1; end;
    if e ? 'head_price' then
      begin v_head := (e->>'head_price')::numeric; exception when others then v_head := null; end;
      begin v_care := (e->>'care_price')::numeric; exception when others then v_care := null; end;
      begin v_back := (e->>'buyback_price')::numeric; exception when others then v_back := null; end;
      if v_head is null or v_head <= 0 then raise exception 'Harga jogrok sapi % wajib diisi (per ekor)', v_cow using errcode = '22023'; end if;
      if v_care is null or v_care < 0 then raise exception 'Tarif perawatan per hari sapi % wajib diisi', v_cow using errcode = '22023'; end if;
      if v_back is null or v_back < 0 then raise exception 'Nilai beli kembali per ekor sapi % wajib diisi', v_cow using errcode = '22023'; end if;
      if v_w is not null and v_w <= 0 then raise exception 'Bobot sapi % harus lebih dari 0 atau dikosongkan', v_cow using errcode = '22023'; end if;
    else
      if v_w is null or v_w <= 0 then
        raise exception 'Hasil timbang wajib diisi' using errcode = '22023';
      end if;
      if (public.qurban_class_at(v_w, v_today)).id is null then
        raise exception 'Bobot % Kg (sapi %) di bawah 350 Kg tidak ada di daftar harga Qurban Cerdas', v_w, v_cow using errcode = '22023';
      end if;
    end if;
  end loop;

  v_pro := 'PRO-INV-' || lpad(public.qurban_next('PRO', v_today)::text, 3, '0') || '-' ||
           public.qurban_roman(extract(month from v_today)::integer) || '-' || to_char(v_today, 'YY');
  if v_n > 1 then v_group := gen_random_uuid(); end if;

  for e in select * from jsonb_array_elements(p_cows) loop
    v_cow := btrim(e->>'cow');
    begin v_w := nullif(e->>'weight', '')::numeric; exception when others then v_w := null; end;
    if e ? 'head_price' then
      insert into public.qurban_orders (cow_no, customer_nick, start_date, initial_weight, pay_mode, sale_mode,
             class_min, class_max, buy_price, care_price, buyback_price, care_fixed, pro_no, pro_date, group_id)
      values (v_cow, btrim(p_nick), p_start, v_w, p_mode, 'HEAD',
              0, null, (e->>'head_price')::numeric, (e->>'care_price')::numeric, (e->>'buyback_price')::numeric, true, v_pro, v_today, v_group)
      returning id into v_id;
    else
      v_cls := public.qurban_class_at(v_w, v_today);
      insert into public.qurban_orders (cow_no, customer_nick, start_date, initial_weight, pay_mode,
             class_min, class_max, buy_price, care_price, buyback_price, pro_no, pro_date, group_id)
      values (v_cow, btrim(p_nick), p_start, v_w, p_mode,
              v_cls.min_kg, v_cls.max_kg, v_cls.buy_price, v_cls.care_price, v_cls.buyback_price, v_pro, v_today, v_group)
      returning id into v_id;
    end if;
    if v_w is not null and v_w > 0 then
      insert into public.qurban_weighings (order_id, weigh_date, weight, note) values (v_id, p_start, v_w, 'Timbang awal');
    end if;
    if v_first is null then v_first := v_id; end if;
  end loop;
  return v_first;
end $$;

-- Tagihan bulanan: jogrok memakai tarif tetap pesanan, bobot hanya dicatat bila ada (0 bila belum pernah ditimbang).
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
                    order by w.weigh_date desc, w.created_at desc limit 1), v.initial_weight, 0)
    into v_basis;
  if not v.care_fixed then
    v_cls := public.qurban_class_at(v_basis, v_today);
    if v_cls.id is null then
      raise exception 'Bobot timbang terakhir di bawah 350 Kg tidak ada di daftar harga' using errcode = '22023';
    end if;
  end if;
  v_days := public.qurban_days(v_ym, v.start_date, v_end);
  v_no := 'INV-' || lpad(public.qurban_next('INV', v_today)::text, 3, '0') || '-' ||
          public.qurban_roman(extract(month from v_today)::integer) || '-' || to_char(v_today, 'YY');
  insert into public.qurban_bills (order_id, bill_no, ym, days, rate, basis_weight, bill_date, due_date)
  values (p_id, v_no, v_ym, v_days, case when v.care_fixed then v.care_price else v_cls.care_price end, v_basis, v_today, v_today + 7);
  return v_no;
end $$;
