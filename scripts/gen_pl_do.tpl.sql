-- ============================================================================
-- Migrasi Packing List dan Surat Jalan lama (arsip Google Sheets)
-- DIBUAT OTOMATIS oleh scripts/gen_pl_do.py — jangan diubah tangan.
-- Jalankan SEKALI di Supabase SQL Editor, SETELAH migrasi 0028 dan skrip migrasi RO/PO
-- (aman diulang: berhenti jika nomor sudah ada; semua-atau-tidak sama sekali).
--
-- UBAH 1 BARIS INI SEBELUM MENJALANKAN:
--   v_wh : kode gudang yang dicatat pada Packing List (bila tidak ada → satu-satunya gudang aktif)
--
-- PENTING: Packing List arsip langsung berstatus DELIVERED. Stok TIDAK dikurangi (stok awal sudah menghitung posisi terkini).
-- Surat Jalan arsip berstatus RECEIVED, bertanda "dokumen arsip", dan memuat daftar barangnya sendiri.
-- Tautan PL -> PO/RO dan Surat Jalan -> PL hanya dibuat bila pelanggan dan tanggalnya cocok satu-satunya.
-- ============================================================================
do $mig$
declare
  v_wh     text  := 'GD-TOKO';                                  -- << kode gudang
  v        jsonb := $json$/*DATA*/$json$::jsonb;
  v_today  date  := (now() at time zone 'Asia/Jakarta')::date;
  c jsonb; p jsonb; r jsonb; it jsonb;
  v_cust   jsonb := '{}'::jsonb;   -- kode customer -> id
  v_prod   jsonb := '{}'::jsonb;   -- nama produk -> id
  v_pl     jsonb := '{}'::jsonb;   -- nomor PL -> id
  v_dup text; v_ids uuid[]; v_id uuid; v_cat uuid; v_unit uuid; v_code text; v_i int; v_ln int; v_pid uuid; v_whid uuid; n_wh int;
  v_ro uuid; v_po uuid;
  n_c_new int := 0; n_c_old int := 0; n_p_new int := 0; n_p_old int := 0; n_pl int := 0; n_do int := 0; n_pli int := 0; n_doi int := 0;
begin
  if to_regclass('public.do_legacy_items') is null then raise exception 'Jalankan dulu migrasi 0028, lalu ulangi skrip ini'; end if;
  if not exists (select 1 from public.request_orders where doc_number = 'RO-ALN-001-II-26') then
    raise exception 'Jalankan dulu skrip migrasi RO/Production Order (migrasi_ro_po.sql), lalu ulangi skrip ini';
  end if;
  if not exists (select 1 from public.units where code = 'GRAM') then raise exception 'Jalankan dulu migrasi 0026 (satuan Gram)'; end if;
  select string_agg(doc_number, ', ' order by doc_number) into v_dup from (select doc_number from public.packing_lists where doc_number in (select e.j->>'no' from jsonb_array_elements(v->'pls') as e(j)) order by doc_number limit 5) q;
  if v_dup is not null then
    raise exception 'Nomor Packing List sudah ada: % (dan mungkin lainnya). Skrip ini sudah pernah dijalankan, atau nomor tersebut sudah terpakai oleh dokumen baru — dihentikan agar tidak ganda.', v_dup;
  end if;
  select string_agg(doc_number, ', ' order by doc_number) into v_dup from (select doc_number from public.delivery_orders where doc_number in (select e.j->>'no' from jsonb_array_elements(v->'dos') as e(j)) order by doc_number limit 5) q;
  if v_dup is not null then
    raise exception 'Nomor Surat Jalan sudah ada: % (dan mungkin lainnya). Skrip ini sudah pernah dijalankan, atau nomor tersebut sudah terpakai oleh dokumen baru — dihentikan agar tidak ganda.', v_dup;
  end if;

  -- Gudang untuk Packing List
  select id into v_whid from public.warehouses where code = v_wh and is_active;
  if v_whid is null then
    select count(*) into n_wh from public.warehouses where is_active;
    if n_wh = 1 then select id into v_whid from public.warehouses where is_active;
    elsif n_wh = 0 then insert into public.warehouses (code, name) values (v_wh, 'Gudang Toko') returning id into v_whid;
    else raise exception 'Gudang % tidak ditemukan dan ada lebih dari satu gudang aktif. Isi v_wh dengan salah satu kode gudang yang ada.', v_wh;
    end if;
  end if;

  -- 1) Pelanggan: pakai yang sudah ada (nama / kode Horeka / pola nama), selain itu dibuat.
  for c in select * from jsonb_array_elements(v->'customers') loop
    select array_agg(id) into v_ids from public.customers
     where lower(name) = lower(c->>'name')
        or (c->>'type' = 'HOREKA' and code = c->>'code')
        or lower(name) like any (array(select lower(jsonb_array_elements_text(c->'like'))));
    if coalesce(array_length(v_ids, 1), 0) > 1 then
      raise exception 'Customer % cocok dengan lebih dari satu data di master Pelanggan. Samakan namanya dulu.', c->>'name';
    elsif coalesce(array_length(v_ids, 1), 0) = 1 then
      v_id := v_ids[1]; n_c_old := n_c_old + 1;
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

  -- 2) Produk: cocokkan nama; belum ada → dibuat.
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
    else n_p_old := n_p_old + 1;
    end if;
    v_prod := v_prod || jsonb_build_object(p->>'name', v_pid);
  end loop;

  -- Aturan "PL hanya dari PO berstatus APPROVED" tidak berlaku untuk arsip. Dinyalakan lagi di akhir.
  alter table public.packing_lists disable trigger packing_lists_check;

  -- 3) Packing List + baris. Langsung DELIVERED; pembaruan status tidak terjadi sehingga stok tidak berubah.
  for r in select * from jsonb_array_elements(v->'pls') loop
    v_ro := null; v_po := null;
    if r->>'ro' is not null then select id into v_ro from public.request_orders where doc_number = r->>'ro'; end if;
    if r->>'po' is not null then select id into v_po from public.production_orders where doc_number = r->>'po'; end if;
    insert into public.packing_lists (doc_number, po_id, ro_id, customer_id, warehouse_id, pack_date, notes, phone, supervisor, status, delivered_at)
    values (r->>'no', v_po, v_ro, (v_cust->>(r->>'c'))::uuid, v_whid, (r->>'d')::date, r->>'n', r->>'ph', r->>'sup', 'DELIVERED',
            ((r->>'d')::date + time '12:00') at time zone 'Asia/Jakarta')
    returning id into v_id;
    v_pl := v_pl || jsonb_build_object(r->>'no', v_id);
    v_ln := 0;
    for it in select * from jsonb_array_elements(r->'it') loop
      v_ln := v_ln + 1; n_pli := n_pli + 1;
      insert into public.pl_items (pl_id, line_no, product_id, qty, notes, gross_weight)
      values (v_id, v_ln, (v_prod->>(it->>'p'))::uuid, (it->>'q')::numeric, it->>'n', (it->>'g')::numeric);
    end loop;
    n_pl := n_pl + 1;
  end loop;

  -- 4) Surat Jalan arsip + daftar barangnya
  for r in select * from jsonb_array_elements(v->'dos') loop
    insert into public.delivery_orders (doc_number, pl_id, customer_id, do_date, driver_name, notes, receiver_name, received_on, status, is_legacy)
    values (r->>'no', (v_pl->>(r->>'pl'))::uuid, (v_cust->>(r->>'c'))::uuid, (r->>'d')::date, r->>'drv', r->>'n',
            coalesce(r->>'rc', (select name from public.customers where id = (v_cust->>(r->>'c'))::uuid)), (r->>'d')::date, 'RECEIVED', true)
    returning id into v_id;
    v_ln := 0;
    for it in select * from jsonb_array_elements(r->'it') loop
      v_ln := v_ln + 1; n_doi := n_doi + 1;
      insert into public.do_legacy_items (do_id, line_no, description, item_type, qty_text) values (v_id, v_ln, it->>'d', it->>'j', it->>'q');
    end loop;
    n_do := n_do + 1;
  end loop;

  alter table public.packing_lists enable trigger packing_lists_check;

  -- Urutan nomor berikutnya melanjutkan arsip (supaya nomor baru tidak bentrok).
  insert into public.pl_sequences (ym, last_number)
  select to_char(pack_date, 'YYYYMM'), max((substring(doc_number from '^PL-([0-9]{3})-'))::int)
    from public.packing_lists
   where doc_number in (select e.j->>'no' from jsonb_array_elements(v->'pls') as e(j)) and doc_number ~ '^PL-[0-9]{3}-[IVX]+-[0-9]{2}$'
   group by to_char(pack_date, 'YYYYMM')
  on conflict (ym) do update set last_number = greatest(public.pl_sequences.last_number, excluded.last_number);
  insert into public.do_sequences (ym, last_number)
  select to_char(do_date, 'YYYYMM'), max((substring(doc_number from '^DO-([0-9]{3})-'))::int)
    from public.delivery_orders
   where doc_number in (select e.j->>'no' from jsonb_array_elements(v->'dos') as e(j)) and doc_number ~ '^DO-[0-9]{3}-[IVX]+-[0-9]{2}$'
   group by to_char(do_date, 'YYYYMM')
  on conflict (ym) do update set last_number = greatest(public.do_sequences.last_number, excluded.last_number);

  raise notice 'Selesai: % Packing List (% baris), % Surat Jalan (% baris). Customer baru % (sudah ada %), produk baru % (sudah ada %).',
    n_pl, n_pli, n_do, n_doi, n_c_new, n_c_old, n_p_new, n_p_old;
end
$mig$;
