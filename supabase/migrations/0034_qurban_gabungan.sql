-- Proforma dan invoice gabungan: beberapa sapi milik satu pembeli dalam satu nomor dan satu file.
-- Tiap sapi tetap satu pesanan (timbangan, QC, Surat Perjanjian, diskon per sapi). Pesanan yang digabung memakai group_id yang sama
-- dan nomor proforma/invoice yang sama. Pesanan tunggal tidak berubah (group_id kosong). Pesanan arsip tidak ikut.
--   - Membuat pesanan: satu kali isi bisa memuat beberapa sapi (qurban_create_orders).
--   - Menggabungkan pesanan proforma milik pelanggan yang sama kapan saja (qurban_merge_proforma), dan melepasnya lagi (qurban_ungroup).
--   - Menerbitkan invoice dan menandai lunas berlaku untuk seluruh sapi dalam satu kelompok.

alter table public.qurban_orders add column group_id uuid;
create index qurban_orders_group_idx on public.qurban_orders(group_id) where group_id is not null;

-- Nomor proforma/invoice boleh sama hanya di dalam kelompok yang sama.
drop index public.qurban_orders_pro_no_uniq;
drop index public.qurban_orders_inv_no_uniq;
create or replace function public.qurban_no_guard() returns trigger
language plpgsql as $$
begin
  if new.is_legacy then return new; end if;
  if new.pro_no is not null then
    perform pg_advisory_xact_lock(hashtext('qurban-pro:' || new.pro_no));
    if exists (select 1 from public.qurban_orders o
                where o.pro_no = new.pro_no and not o.is_legacy and o.id <> new.id
                  and (new.group_id is null or o.group_id is distinct from new.group_id)) then
      raise exception 'Nomor proforma % sudah dipakai pesanan lain', new.pro_no using errcode = '23505';
    end if;
  end if;
  if new.inv_no is not null then
    perform pg_advisory_xact_lock(hashtext('qurban-inv:' || new.inv_no));
    if exists (select 1 from public.qurban_orders o
                where o.inv_no = new.inv_no and not o.is_legacy and o.id <> new.id
                  and (new.group_id is null or o.group_id is distinct from new.group_id)) then
      raise exception 'Nomor invoice % sudah dipakai pesanan lain', new.inv_no using errcode = '23505';
    end if;
  end if;
  return new;
end $$;
create trigger qurban_orders_no_guard before insert or update of pro_no, inv_no, group_id on public.qurban_orders
  for each row execute function public.qurban_no_guard();

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

-- Buat pesanan: satu atau beberapa sapi untuk satu pelanggan. Dua sapi atau lebih = satu nomor proforma dan satu kelompok.
-- p_cows: [{"cow": "#012", "weight": 650.5}, ...]
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
    begin v_w := (e->>'weight')::numeric; exception when others then v_w := null; end;
    if v_w is null or v_w <= 0 then
      raise exception 'Hasil timbang wajib diisi' using errcode = '22023';
    end if;
    if (public.qurban_class_at(v_w, v_today)).id is null then
      raise exception 'Bobot % Kg (sapi %) di bawah 350 Kg tidak ada di daftar harga Qurban Cerdas', v_w, v_cow using errcode = '22023';
    end if;
  end loop;

  v_pro := 'PRO-INV-' || lpad(public.qurban_next('PRO', v_today)::text, 3, '0') || '-' ||
           public.qurban_roman(extract(month from v_today)::integer) || '-' || to_char(v_today, 'YY');
  if v_n > 1 then v_group := gen_random_uuid(); end if;

  for e in select * from jsonb_array_elements(p_cows) loop
    v_cow := btrim(e->>'cow'); v_w := (e->>'weight')::numeric;
    v_cls := public.qurban_class_at(v_w, v_today);
    insert into public.qurban_orders (cow_no, customer_nick, start_date, initial_weight, pay_mode,
           class_min, class_max, buy_price, care_price, buyback_price, pro_no, pro_date, group_id)
    values (v_cow, btrim(p_nick), p_start, v_w, p_mode,
            v_cls.min_kg, v_cls.max_kg, v_cls.buy_price, v_cls.care_price, v_cls.buyback_price, v_pro, v_today, v_group)
    returning id into v_id;
    insert into public.qurban_weighings (order_id, weigh_date, weight, note) values (v_id, p_start, v_w, 'Timbang awal');
    if v_first is null then v_first := v_id; end if;
  end loop;
  return v_first;
end $$;

-- Cara lama (satu sapi) tetap tersedia.
create or replace function public.qurban_create_order(p_cow text, p_nick text, p_weight numeric, p_start date, p_mode text)
returns uuid
language plpgsql security definer set search_path = public as $$
begin
  return public.qurban_create_orders(p_nick, p_start, p_mode, jsonb_build_array(jsonb_build_object('cow', p_cow, 'weight', p_weight)));
end $$;

-- Terbitkan invoice: seluruh sapi dalam kelompok yang masih proforma ikut terbit dengan satu nomor.
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
  if v.group_id is not null then
    perform 1 from public.qurban_orders where group_id = v.group_id and deleted_at is null for update;
  end if;
  v_no := 'INV-' || lpad(public.qurban_next('INV', v_today)::text, 3, '0') || '-' ||
          public.qurban_roman(extract(month from v_today)::integer) || '-' || to_char(v_today, 'YY');
  update public.qurban_orders
     set status = 'INVOICE', inv_no = v_no, inv_date = v_today, due_date = v_today + 1
   where deleted_at is null and status = 'PROFORMA' and (id = p_id or (v.group_id is not null and group_id = v.group_id));
  return v_no;
end $$;

-- Tandai lunas: seluruh sapi yang berinvoice sama ikut lunas.
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
  if v.group_id is not null then
    perform 1 from public.qurban_orders where group_id = v.group_id and deleted_at is null for update;
  end if;
  update public.qurban_orders set status = 'PAID', paid_at = now()
   where deleted_at is null and status = 'INVOICE'
     and (id = p_id or (v.group_id is not null and group_id = v.group_id and inv_no is not distinct from v.inv_no));
end $$;

-- Gabungkan pesanan proforma milik pelanggan yang sama ke satu nomor proforma (nomor dan tanggal mengikuti pesanan utama).
create or replace function public.qurban_merge_proforma(p_id uuid, p_ids uuid[])
returns void
language plpgsql security definer set search_path = public as $$
declare v public.qurban_orders%rowtype; o public.qurban_orders%rowtype; v_group uuid; x uuid;
begin
  perform public.qurban_need('qurban','edit','Anda tidak memiliki izin menggabungkan proforma');
  select * into v from public.qurban_orders where id = p_id and deleted_at is null for update;
  if not found then raise exception 'Pesanan tidak ditemukan' using errcode = 'P0002'; end if;
  if v.status <> 'PROFORMA' or v.is_legacy then
    raise exception 'Hanya pesanan yang masih proforma yang bisa digabung' using errcode = '55000';
  end if;
  if p_ids is null or cardinality(p_ids) = 0 then
    raise exception 'Pilih minimal satu pesanan untuk digabung' using errcode = '22023';
  end if;
  foreach x in array p_ids loop
    select * into o from public.qurban_orders where id = x and deleted_at is null for update;
    if not found then raise exception 'Pesanan tidak ditemukan' using errcode = 'P0002'; end if;
    if o.id = v.id then raise exception 'Pesanan utama tidak perlu dipilih lagi' using errcode = '22023'; end if;
    if o.status <> 'PROFORMA' or o.is_legacy or o.group_id is not null then
      raise exception 'Sapi % belum bisa digabung: harus masih proforma dan belum tergabung', o.cow_no using errcode = '55000';
    end if;
    if o.customer_nick <> v.customer_nick then
      raise exception 'Sapi % milik pelanggan lain (%)', o.cow_no, o.customer_nick using errcode = '22023';
    end if;
  end loop;
  v_group := coalesce(v.group_id, gen_random_uuid());
  update public.qurban_orders set group_id = v_group where id = v.id;
  update public.qurban_orders set group_id = v_group, pro_no = v.pro_no, pro_date = v.pro_date where id = any (p_ids);
end $$;

-- Lepaskan satu sapi dari proforma gabungan: sapi itu mendapat nomor proforma sendiri.
create or replace function public.qurban_ungroup(p_id uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare v public.qurban_orders%rowtype; v_today date := public.qurban_today(); v_no text; v_left integer; v_g uuid;
begin
  perform public.qurban_need('qurban','edit','Anda tidak memiliki izin mengubah proforma');
  select * into v from public.qurban_orders where id = p_id and deleted_at is null for update;
  if not found then raise exception 'Pesanan tidak ditemukan' using errcode = 'P0002'; end if;
  if v.group_id is null then raise exception 'Pesanan ini tidak tergabung dengan pesanan lain' using errcode = '55000'; end if;
  if v.status <> 'PROFORMA' then
    raise exception 'Sapi hanya bisa dilepas selama masih proforma (sebelum invoice terbit)' using errcode = '55000';
  end if;
  v_g := v.group_id;
  v_no := 'PRO-INV-' || lpad(public.qurban_next('PRO', v_today)::text, 3, '0') || '-' ||
          public.qurban_roman(extract(month from v_today)::integer) || '-' || to_char(v_today, 'YY');
  update public.qurban_orders set group_id = null, pro_no = v_no, pro_date = v_today where id = p_id;
  select count(*) into v_left from public.qurban_orders where group_id = v_g and deleted_at is null and status <> 'CANCELLED';
  if v_left <= 1 then update public.qurban_orders set group_id = null where group_id = v_g; end if;
  return v_no;
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'qurban_create_orders(text,date,text,jsonb)','qurban_create_order(text,text,numeric,date,text)','qurban_issue_invoice(uuid)',
    'qurban_mark_paid(uuid)','qurban_merge_proforma(uuid,uuid[])','qurban_ungroup(uuid)'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
