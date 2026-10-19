-- ============================================================================
-- Migrasi RO (Request Order) dan Production Order lama (arsip Google Sheets)
-- DIBUAT OTOMATIS oleh scripts/gen_ro_po.py — jangan diubah tangan.
-- Jalankan SEKALI di Supabase SQL Editor (aman diulang: berhenti jika nomor RO sudah ada; semua-atau-tidak sama sekali).
-- Syarat: migrasi 0027 sudah dijalankan.
-- Isi: pelanggan (dicocokkan dengan yang sudah ada), produk (dicocokkan lewat nama), RO, Production Order beserta barisnya.
-- Nomor dokumen dipertahankan seperti di dokumen asli. Status: tanggal kirim sudah lewat → RO COMPLETED / PO DONE,
-- selain itu RO CONFIRMED / PO APPROVED. Harga di RO per kg seperti tertulis di dokumen.
-- ============================================================================
do $mig$
declare
  v        jsonb := $json$/*DATA*/$json$::jsonb;
  v_today  date  := (now() at time zone 'Asia/Jakarta')::date;
  c jsonb; p jsonb; r jsonb; it jsonb;
  v_cust   jsonb := '{}'::jsonb;   -- kode customer -> id
  v_prod   jsonb := '{}'::jsonb;   -- nama produk -> id
  v_ro     jsonb := '{}'::jsonb;   -- nomor RO -> id
  v_dup text; v_ids uuid[]; v_id uuid; v_cat uuid; v_unit uuid; v_code text; v_i int; v_ln int; v_pid uuid; v_cid uuid;
  n_c_new int := 0; n_c_old int := 0; n_p_new int := 0; n_p_old int := 0; n_ro int := 0; n_po int := 0; n_it int := 0;
begin
  if not exists (select 1 from pg_constraint where conname = 'ro_items_packaging_chk' and pg_get_constraintdef(oid) like '%Vacuum 3 Kg%')
     or exists (select 1 from pg_constraint where conname = 'ro_items_ro_id_product_id_key') then
    raise exception 'Jalankan dulu migrasi 0027, lalu ulangi skrip ini';
  end if;
  if (select count(*) from public.units where code in ('GRAM','EKOR','LS')) < 3 then
    raise exception 'Satuan Gram/Ekor/Lumpsum belum ada. Jalankan migrasi 0026 dan 0027 dulu.';
  end if;
  select string_agg(doc_number, ', ' order by doc_number) into v_dup from (select doc_number from public.request_orders where doc_number in (select e.j->>'no' from jsonb_array_elements(v->'ros') as e(j)) order by doc_number limit 5) q;
  if v_dup is not null then
    raise exception 'Nomor RO sudah ada: % (dan mungkin lainnya). Skrip ini sudah pernah dijalankan, atau nomor tersebut sudah terpakai oleh dokumen baru — dihentikan agar tidak ganda.', v_dup;
  end if;
  select string_agg(doc_number, ', ' order by doc_number) into v_dup from (select doc_number from public.production_orders where doc_number in (select e.j->>'no' from jsonb_array_elements(v->'pos') as e(j)) order by doc_number limit 5) q;
  if v_dup is not null then
    raise exception 'Nomor Production Order sudah ada: % (dan mungkin lainnya). Skrip ini sudah pernah dijalankan, atau nomor tersebut sudah terpakai oleh dokumen baru — dihentikan agar tidak ganda.', v_dup;
  end if;

  -- 1) Pelanggan: pakai yang sudah ada (kode / nama / pola nama), selain itu dibuat.
  for c in select * from jsonb_array_elements(v->'customers') loop
    select array_agg(id) into v_ids from public.customers
     where lower(name) = lower(c->>'name')
        or (c->>'type' = 'HOREKA' and code = c->>'code')
        or lower(name) like any (array(select lower(jsonb_array_elements_text(c->'like'))));
    if coalesce(array_length(v_ids, 1), 0) > 1 then
      raise exception 'Customer % cocok dengan lebih dari satu data di master Pelanggan. Samakan namanya dulu.', c->>'name';
    elsif coalesce(array_length(v_ids, 1), 0) = 1 then
      v_id := v_ids[1]; n_c_old := n_c_old + 1;
      raise notice 'Customer % → pakai yang sudah ada (%)', c->>'name', (select code || ' / ' || name from public.customers where id = v_id);
    else
      v_code := c->>'code'; v_i := 0;
      while exists (select 1 from public.customers where code = case when v_i = 0 then v_code else v_code || '-' || v_i end) loop v_i := v_i + 1; end loop;
      insert into public.customers (code, name, type, address, phone, payment_term_days)
      values (case when v_i = 0 then v_code else v_code || '-' || v_i end, c->>'name', c->>'type', c->>'address', c->>'phone', (c->>'term')::int)
      returning id into v_id;
      n_c_new := n_c_new + 1;
    end if;
    v_cust := v_cust || jsonb_build_object(c->>'code', v_id);
  end loop;

  -- 2) Produk: cocokkan nama (tanpa huruf besar/kecil); belum ada → dibuat.
  for p in select * from jsonb_array_elements(v->'products') loop
    select id into v_pid from public.products where lower(name) = lower(p->>'name');
    if v_pid is null then
      v_cat := null;
      if p->>'cat' is not null then
        select id into v_cat from public.product_categories
         where code = case p->>'cat' when 'Tulang' then 'TULANG' when 'Jeroan' then 'JEROHAN' else 'DAGING' end;
        if v_cat is null then
          select id into v_cat from public.product_categories
           where lower(name) = any (case p->>'cat' when 'Tulang' then array['tulang','tulang sapi']
                                                   when 'Jeroan' then array['jerohan','jeroan','jerohan sapi','jeroan sapi']
                                                   else array['daging','daging sapi'] end)
           order by created_at limit 1;
        end if;
        if v_cat is null then
          insert into public.product_categories (code, name)
          values (case p->>'cat' when 'Tulang' then 'TULANG' when 'Jeroan' then 'JEROHAN' else 'DAGING' end, case p->>'cat' when 'Jeroan' then 'Jerohan' else p->>'cat' end)
          returning id into v_cat;
        end if;
      end if;
      select id into v_unit from public.units where code = p->>'unit';
      v_code := trim(both '-' from left(upper(regexp_replace(p->>'name', '[^A-Za-z0-9]+', '-', 'g')), 30)); v_i := 0;
      while exists (select 1 from public.products where code = case when v_i = 0 then v_code else v_code || '-' || v_i end) loop v_i := v_i + 1; end loop;
      insert into public.products (code, name, product_type, category_id, unit_id)
      values (case when v_i = 0 then v_code else v_code || '-' || v_i end, p->>'name', p->>'type', v_cat, v_unit)
      returning id into v_pid;
      n_p_new := n_p_new + 1;
    else
      n_p_old := n_p_old + 1;
    end if;
    v_prod := v_prod || jsonb_build_object(p->>'name', v_pid);
  end loop;

  -- Aturan "PO hanya dari RO berstatus CONFIRMED" dan "satu RO satu PO aktif" tidak berlaku untuk arsip (status akhir sudah selesai,
  -- dan beberapa RO memang punya lebih dari satu PO). Dinyalakan lagi di akhir; bila ada kegagalan semuanya dibatalkan.
  alter table public.production_orders disable trigger production_orders_check;
  alter table public.production_orders disable trigger production_orders_one_active;

  -- 3) RO + barisnya
  for r in select * from jsonb_array_elements(v->'ros') loop
    insert into public.request_orders (doc_number, customer_id, order_date, delivery_date, notes, status,
                                       orderer_name, phone, delivery_address, delivery_time, payment_method, delivery_method)
    values (r->>'no', (v_cust->>(r->>'c'))::uuid, (r->>'od')::date, (r->>'dd')::date, r->>'n',
            case when coalesce((r->>'dd')::date, (r->>'od')::date) < v_today then 'COMPLETED' else 'CONFIRMED' end,
            r->>'on', r->>'ph', r->>'ad', r->>'tm', r->>'pay', r->>'dm')
    returning id into v_id;
    v_ro := v_ro || jsonb_build_object(r->>'no', v_id);
    v_ln := 0;
    for it in select * from jsonb_array_elements(r->'it') loop
      v_ln := v_ln + 1; n_it := n_it + 1;
      insert into public.ro_items (ro_id, line_no, product_id, qty, unit_price, notes, cut_type, packaging)
      values (v_id, v_ln, (v_prod->>(it->>'p'))::uuid, (it->>'q')::numeric, (it->>'pr')::numeric, it->>'n', it->>'cut', it->>'pk');
    end loop;
    perform public.ro_recalc(v_id);
    n_ro := n_ro + 1;
  end loop;

  -- Urutan nomor RO berikutnya per customer per bulan melanjutkan arsip (supaya nomor baru tidak bentrok).
  insert into public.ro_sequences (customer_id, ym, last_number)
  select customer_id, to_char(order_date, 'YYYYMM'), max((substring(doc_number from '^RO-[A-Z0-9]+-([0-9]{3})-'))::int)
    from public.request_orders
   where doc_number in (select e.j->>'no' from jsonb_array_elements(v->'ros') as e(j)) and doc_number ~ '^RO-[A-Z0-9]+-[0-9]{3}-[IVX]+-[0-9]{2}$'
     and customer_id in (select id from public.customers where type = 'HOREKA')
   group by customer_id, to_char(order_date, 'YYYYMM')
  on conflict (customer_id, ym) do update set last_number = greatest(public.ro_sequences.last_number, excluded.last_number);

  -- 4) Production Order + barisnya
  for r in select * from jsonb_array_elements(v->'pos') loop
    insert into public.production_orders (doc_number, ro_id, order_date, needed_date, notes, send_note, delivery_address, pic, cow_codes, status)
    values (r->>'no', (v_ro->>(r->>'ro'))::uuid, (r->>'od')::date, (r->>'nd')::date, r->>'n', r->>'sn', r->>'ad', r->>'pic', r->>'cow',
            case when coalesce((r->>'nd')::date, (r->>'od')::date) < v_today then 'DONE' else 'APPROVED' end)
    returning id into v_id;
    v_ln := 0;
    for it in select * from jsonb_array_elements(r->'it') loop
      v_ln := v_ln + 1; n_it := n_it + 1;
      v_pid := (v_prod->>(it->>'p'))::uuid;
      insert into public.po_items (po_id, line_no, product_id, ro_product_id, qty, notes, cut_type, packaging)
      values (v_id, v_ln, v_pid, v_pid, (it->>'q')::numeric, it->>'n', it->>'cut', it->>'pk');
    end loop;
    n_po := n_po + 1;
  end loop;

  alter table public.production_orders enable trigger production_orders_check;
  alter table public.production_orders enable trigger production_orders_one_active;

  raise notice 'Selesai: % RO, % Production Order, % baris barang. Customer baru % (sudah ada %), produk baru % (sudah ada %).',
    n_ro, n_po, n_it, n_c_new, n_c_old, n_p_new, n_p_old;
end
$mig$;
