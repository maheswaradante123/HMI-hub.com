-- ============================================================================
-- Migrasi stok awal daging/tulang/jeroan dari aplikasi lama (Product Management La Mitra)
-- DIBUAT OTOMATIS oleh scripts/gen-stok-awal.mjs dari supabase/data/stok_awal_daging.tsv
-- Jalankan SEKALI di Supabase SQL Editor (aman diulang: berhenti jika sudah pernah dijalankan).
--
-- UBAH 2 BARIS INI SEBELUM MENJALANKAN:
--   v_date : tanggal stok dihitung ("cut-off"), tidak boleh di masa depan
--   v_wh   : kode gudang tujuan
-- Syarat: migrasi 0026 (satuan Gram) sudah dijalankan. Semua jumlah dalam gram.
-- ============================================================================
do $mig$
declare
  v_date  date := (now() at time zone 'Asia/Jakarta')::date;   -- << tanggal cut-off
  v_wh    text := 'GD-TOKO';                                   -- << kode gudang
  v_whid  uuid; v_pid uuid; v_cat uuid; v_unit uuid; v_code text; v_i int;
  r record; n_new int := 0; n_old int := 0; n_mov int := 0; n_wh int;
  c_marker constant text := 'Migrasi stok awal La Mitra';
begin
  -- Gudang: pakai kode di atas; bila tidak ada → pakai satu-satunya gudang aktif; bila belum ada gudang sama sekali → dibuat.
  select id into v_whid from public.warehouses where code = v_wh and is_active;
  if v_whid is null then
    select count(*) into n_wh from public.warehouses where is_active;
    if n_wh = 1 then
      select id, code into v_whid, v_wh from public.warehouses where is_active;
    elsif n_wh = 0 then
      insert into public.warehouses (code, name) values (v_wh, 'Gudang Toko') returning id into v_whid;
    else
      raise exception 'Gudang % tidak ditemukan dan ada lebih dari satu gudang aktif. Isi v_wh dengan salah satu kode gudang yang ada.', v_wh;
    end if;
  end if;
  -- Kategori produk dasar dibuat bila belum ada (di database produksi hanya ada bila sudah diisi manual).
  insert into public.product_categories (code, name) values ('DAGING','Daging'), ('TULANG','Tulang'), ('JEROHAN','Jerohan') on conflict do nothing;
  if to_regprocedure('public.post_stock(uuid,uuid,text,numeric,numeric,text,uuid,text,date,text)') is null then
    raise exception 'Jalankan dulu migrasi 0025 (stok per kode sapi), lalu ulangi skrip ini';
  end if;
  if not exists (select 1 from public.units where code = 'GRAM') then
    raise exception 'Jalankan dulu migrasi 0026 (satuan Gram), lalu ulangi skrip ini';
  end if;
  if v_date > (now() at time zone 'Asia/Jakarta')::date then raise exception 'Tanggal cut-off tidak boleh di masa depan'; end if;
  if exists (select 1 from public.stock_movements where note like c_marker || '%') then
    raise exception 'Migrasi ini sudah pernah dijalankan — dihentikan agar stok tidak ganda';
  end if;

  -- 1) Master item: cocokkan nama (tanpa huruf besar/kecil); belum ada → dibuat (MANUFACTURE)
  for r in select * from (values
    ('Babat', 'Jeroan', 'GRAM'),
    ('Babat Handuk', 'Jeroan', 'GRAM'),
    ('Buntut', 'Jeroan', 'GRAM'),
    ('Gandik', 'Daging', 'GRAM'),
    ('Ginjal', 'Jeroan', 'GRAM'),
    ('Has Dalam', 'Daging', 'GRAM'),
    ('Has Luar', 'Daging', 'GRAM'),
    ('Hati', 'Jeroan', 'GRAM'),
    ('Jantung', 'Jeroan', 'GRAM'),
    ('Knuckle', 'Daging', 'GRAM'),
    ('Lamusir', 'Daging', 'GRAM'),
    ('Limpa', 'Jeroan', 'GRAM'),
    ('Otak', 'Jeroan', 'GRAM'),
    ('Paru', 'Jeroan', 'GRAM'),
    ('Punuk', 'Daging', 'GRAM'),
    ('Sampil', 'Daging', 'GRAM'),
    ('Sancan', 'Daging', 'GRAM'),
    ('Sandung Lamur', 'Daging', 'GRAM'),
    ('Short Ribs', 'Tulang', 'GRAM'),
    ('Topside', 'Daging', 'GRAM'),
    ('Tulang Sop', 'Tulang', 'GRAM'),
    ('Tulang Sumsum', 'Tulang', 'GRAM'),
    ('Usus', 'Jeroan', 'GRAM')
  ) as t(name, cat, unit) loop
    select id into v_pid from public.products where lower(name) = lower(r.name);
    if v_pid is null then
      select id into v_cat from public.product_categories where code = case r.cat when 'Tulang' then 'TULANG' when 'Jeroan' then 'JEROHAN' else 'DAGING' end;
      select id into v_unit from public.units where code = r.unit;
      if v_cat is null or v_unit is null then raise exception 'Kategori/satuan untuk % belum ada di master', r.name; end if;
      v_code := trim(both '-' from left(upper(regexp_replace(r.name, '[^A-Za-z0-9]+', '-', 'g')), 30)); v_i := 0;
      while exists (select 1 from public.products where code = case when v_i = 0 then v_code else v_code || '-' || v_i end) loop v_i := v_i + 1; end loop;
      insert into public.products (code, name, product_type, category_id, unit_id)
      values (case when v_i = 0 then v_code else v_code || '-' || v_i end, r.name, 'MANUFACTURE', v_cat, v_unit);
      n_new := n_new + 1;
    else
      if (select u.code from public.products p join public.units u on u.id = p.unit_id where p.id = v_pid) <> 'GRAM' then
        raise exception 'Item % di master masih bersatuan selain Gram. Jalankan migrasi 0026 dulu.', r.name;
      end if;
      n_old := n_old + 1;
    end if;
  end loop;

  -- 2) Stok awal per item per kode sapi, dalam gram. lot kosong = tanpa kode sapi.
  for r in select * from (values
    ('Babat', 'AINUL001', 3585::numeric, 'JR003AINUL001'),
    ('Babat', 'AMF002', 7655::numeric, 'JR006AMF002'),
    ('Babat', 'AMF003', 8315::numeric, 'JR002AMF003'),
    ('Babat', 'AMF005', 11605::numeric, 'JR004AMF005'),
    ('Babat', 'AMF006', 5405::numeric, 'DG015AMF006'),
    ('Babat', 'AMF007', 7980::numeric, 'JR015AMF007'),
    ('Babat', 'AMF008', 8985::numeric, 'JR016AMF008'),
    ('Babat', 'NUR001', 8695::numeric, 'JR023NUR001'),
    ('Babat', 'NUR002', 11885::numeric, 'JR017NUR002'),
    ('Babat', 'OKA001', 8580::numeric, 'JR002OKA001'),
    ('Babat', 'REOT008', 9390::numeric, 'JR006REOT008'),
    ('Babat', 'REOT016', 10420::numeric, 'JR002REOT016'),
    ('Babat', 'REOT017', 8360::numeric, 'JR002REOT017'),
    ('Babat', 'REOT018', 9250::numeric, 'JR001REOT018'),
    ('Babat', 'REOT019', 7455::numeric, 'JR002REOT019'),
    ('Babat', 'REOT020', 15050::numeric, 'JR003REOT020'),
    ('Babat', 'REOT021', 11955::numeric, 'JR002REOT021'),
    ('Babat', 'REOT022', 13385::numeric, 'JR002REOT022'),
    ('Babat', 'REOT023', 8300::numeric, 'JR003REOT023'),
    ('Babat', 'REOT024', 9845::numeric, 'JR003REOT024'),
    ('Babat', 'REOT025', 7680::numeric, 'JR003REOT025'),
    ('Babat', 'REOT026', 5115::numeric, 'JR003REOT026'),
    ('Babat', 'REOT027', 12675::numeric, 'JR004REOT027'),
    ('Babat Handuk', 'AMF004', 5325::numeric, 'JR003AMF004'),
    ('Buntut', 'AMF007', 35::numeric, 'JR017AMF007'),
    ('Buntut', 'AMF011', 665::numeric, 'JR015AMF011'),
    ('Buntut', 'RPH001', 11721::numeric, 'TL001RPH001'),
    ('Gandik', 'NUR001', 10845::numeric, 'DG005NUR001'),
    ('Gandik', 'NUR002', 9995::numeric, 'DG005NUR002'),
    ('Ginjal', 'AMF002', 705::numeric, 'JR008AMF002'),
    ('Ginjal', 'AMF010', 730::numeric, 'JR024AMF010'),
    ('Ginjal', 'AMF012', 840::numeric, 'JR008AMF012'),
    ('Ginjal', 'NUR001', 765::numeric, 'JR018NUR001'),
    ('Has Dalam', 'AMF014', 2635::numeric, 'DG001AMF014'),
    ('Has Dalam', 'NUR001', 1155::numeric, 'DG001NUR001'),
    ('Has Dalam', 'NUR002', 8710::numeric, 'DG001NUR002'),
    ('Has Luar', 'AMF002', 6350::numeric, 'DG002AMF002'),
    ('Has Luar', 'AMF005', 5840::numeric, 'DG002AMF005'),
    ('Has Luar', 'AMF012', 5885::numeric, 'DG002AMF012'),
    ('Has Luar', 'AMF013', 2150::numeric, 'DG1AMF013'),
    ('Has Luar', 'NUR001', 12010::numeric, 'DG002NUR001'),
    ('Has Luar', 'NUR002', 14620::numeric, 'DG002NUR002'),
    ('Hati', null::text, 23755::numeric, 'JR002'),
    ('Hati', 'AINUL001', 3415::numeric, 'JR002AINUL001'),
    ('Hati', 'AMF002', 11880::numeric, 'JRAMF002, JR002AMF002'),
    ('Hati', 'AMF003', 815::numeric, 'JR004AMF003'),
    ('Hati', 'AMF005', 675::numeric, 'JR002AMF005'),
    ('Hati', 'AMF008', 2383::numeric, 'JR012AMF008'),
    ('Hati', 'AMF012', 4555::numeric, 'JR002AMF012'),
    ('Hati', 'NUR002', 4935::numeric, 'JR015NUR002'),
    ('Hati', 'OKA001', 5395::numeric, 'JR003OKA001'),
    ('Hati', 'REOT008', 2705::numeric, 'JR002REOT008'),
    ('Hati', 'REOT016', 3480::numeric, 'JR004REOT016'),
    ('Hati', 'REOT017', 2630::numeric, 'JR004REOT017'),
    ('Hati', 'REOT018', 3575::numeric, 'JR004REOT018'),
    ('Hati', 'REOT019', 1245::numeric, 'JR004REOT019'),
    ('Hati', 'REOT020', 1305::numeric, 'JR002REOT020'),
    ('Hati', 'REOT021', 2315::numeric, 'JR004REOT021'),
    ('Hati', 'REOT023', 2921::numeric, 'JR002REOT023'),
    ('Hati', 'REOT024', 3865::numeric, 'JR002REOT024'),
    ('Hati', 'REOT025', 3560::numeric, 'JR001REOT025'),
    ('Hati', 'REOT027', 4690::numeric, 'JR002REOT027'),
    ('Jantung', null::text, 10870::numeric, 'JR005'),
    ('Jantung', 'AMF002', 1415::numeric, 'JR004AMF002'),
    ('Jantung', 'AMF010', 1060::numeric, 'JR017AMF010'),
    ('Jantung', 'AMF011', 1335::numeric, 'JR018AMF011'),
    ('Jantung', 'AMF012', 1470::numeric, 'JR006AMF012'),
    ('Jantung', 'NUR001', 1260::numeric, 'JR017NUR001'),
    ('Jantung', 'NUR002', 1730::numeric, 'JR020NUR002'),
    ('Jantung', 'REOT008', 1785::numeric, 'JR004REOT008'),
    ('Knuckle', 'NUR002', 6385::numeric, 'DG003NUR002'),
    ('Knuckle', 'REOT008', 485::numeric, 'DG011REOT008'),
    ('Lamusir', 'REOT001', 70::numeric, 'DG005REOT001'),
    ('Limpa', null::text, 6120::numeric, 'JR003'),
    ('Limpa', 'AMF002', 1080::numeric, 'JR003AMF002'),
    ('Limpa', 'AMF010', 1075::numeric, 'JR023AMF010'),
    ('Limpa', 'AMF012', 830::numeric, 'JR007AMF012'),
    ('Limpa', 'NUR001', 640::numeric, 'JR019NUR001'),
    ('Limpa', 'NUR002', 1030::numeric, 'JR019NUR002'),
    ('Otak', 'AMF002', 395::numeric, 'JR005AMF002'),
    ('Otak', 'AMF004', 375::numeric, 'JR006AMF004'),
    ('Otak', 'AMF006', 360::numeric, 'DG014AMF006'),
    ('Otak', 'AMF008', 275::numeric, 'JR014AMF008'),
    ('Otak', 'AMF011', 360::numeric, 'JR017AMF011'),
    ('Otak', 'NUR001', 410::numeric, 'JR016NUR001'),
    ('Otak', 'REOT008', 495::numeric, 'JR005REOT008'),
    ('Paru', 'AMF008', 4630::numeric, 'JR013AMF008'),
    ('Paru', 'NUR002', 1730::numeric, 'JR016NUR002'),
    ('Punuk', 'AINUL001', 1390::numeric, 'DG012AINUL001'),
    ('Punuk', 'AMF005', 13650::numeric, 'DG012AMF005'),
    ('Punuk', 'AMF008', 4905::numeric, 'DG011AMF008'),
    ('Punuk', 'AMF009', 12790::numeric, 'DG012AMF009'),
    ('Punuk', 'AMF010', 5775::numeric, 'DG010AMF010'),
    ('Punuk', 'AMF012', 4575::numeric, 'DG011AMF012'),
    ('Punuk', 'NUR002', 5915::numeric, 'DG010NUR002'),
    ('Punuk', 'REOT027', 8280::numeric, 'DG012REOT027'),
    ('Sampil', 'AMF011', 40::numeric, 'DG006AMF011'),
    ('Sampil', 'REOT007', 155::numeric, 'DG003REOT007'),
    ('Sancan', 'NUR002', 14175::numeric, 'DG008NUR002'),
    ('Sandung Lamur', 'AMF005', 14185::numeric, 'DG010AMF005'),
    ('Sandung Lamur', 'NUR002', 12150::numeric, 'DG009NUR002'),
    ('Sandung Lamur', 'REOT027', 2745::numeric, 'DG010REOT027'),
    ('Short Ribs', null::text, 49435::numeric, 'Tulang IGA Kr jati'),
    ('Short Ribs', 'NUR002', 970::numeric, 'TL012NUR002'),
    ('Topside', 'AMF011', 125::numeric, 'DG004AMF011'),
    ('Topside', 'NUR001', 4065::numeric, 'DG004NUR001'),
    ('Topside', 'NUR002', 13125::numeric, 'DG004NUR002'),
    ('Topside', 'REOT026', 45::numeric, 'DG003REOT026'),
    ('Tulang Sop', null::text, 81675::numeric, 'Tlkr01'),
    ('Tulang Sop', 'AMF002', 7150::numeric, 'TL002AMF002'),
    ('Tulang Sop', 'AMF007', 2240::numeric, 'TL021AMF007'),
    ('Tulang Sop', 'AMF011', 7525::numeric, 'TL013AMF011'),
    ('Tulang Sop', 'AMF012', 6510::numeric, 'TL002AMF012'),
    ('Tulang Sop', 'AMF013', 8435::numeric, 'TL2AMF013'),
    ('Tulang Sop', 'NUR001', 3540::numeric, 'TL013NUR001'),
    ('Tulang Sop', 'NUR002', 11225::numeric, 'TL013NUR002'),
    ('Tulang Sop', 'REOT007', 10115::numeric, 'TL002REOT007'),
    ('Tulang Sumsum', 'AMF007', 14320::numeric, 'TL020AMF007'),
    ('Usus', 'AINUL001', 11080::numeric, 'JR004AINUL001'),
    ('Usus', 'AMF002', 10615::numeric, 'JR007AMF002'),
    ('Usus', 'AMF003', 8190::numeric, 'JR003AMF003'),
    ('Usus', 'AMF004', 6550::numeric, 'JR004AMF004'),
    ('Usus', 'AMF005', 13055::numeric, 'JR005AMF005'),
    ('Usus', 'AMF007', 7000::numeric, 'JR016AMF007'),
    ('Usus', 'AMF008', 10925::numeric, 'JR017AMF008'),
    ('Usus', 'NUR001', 13270::numeric, 'JR024NUR001'),
    ('Usus', 'NUR002', 13595::numeric, 'JR018NUR002'),
    ('Usus', 'OKA001', 9250::numeric, 'JR004OKA001'),
    ('Usus', 'REOT008', 11905::numeric, 'JR007REOT008'),
    ('Usus', 'REOT016', 9870::numeric, 'JR003REOT016'),
    ('Usus', 'REOT017', 8785::numeric, 'JR003REOT017'),
    ('Usus', 'REOT018', 10335::numeric, 'JR002REOT018'),
    ('Usus', 'REOT019', 7135::numeric, 'JR003REOT019'),
    ('Usus', 'REOT020', 9120::numeric, 'JR004REOT020'),
    ('Usus', 'REOT021', 8995::numeric, 'JR003REOT021'),
    ('Usus', 'REOT022', 11845::numeric, 'JR003REOT022'),
    ('Usus', 'REOT023', 7680::numeric, 'JR004REOT023'),
    ('Usus', 'REOT024', 7455::numeric, 'JR004REOT024'),
    ('Usus', 'REOT025', 7455::numeric, 'JR004REOT025'),
    ('Usus', 'REOT026', 3530::numeric, 'JR004REOT026'),
    ('Usus', 'REOT027', 11200::numeric, 'JR005REOT027')
  ) as t(name, lot, qty, codes) loop
    select id into v_pid from public.products where lower(name) = lower(r.name);
    perform public.post_stock(v_pid, v_whid, 'OPENING', r.qty, null, 'MANUAL', null,
      c_marker || ' (kode lama: ' || r.codes || ')', v_date, r.lot);
    n_mov := n_mov + 1;
  end loop;

  raise notice 'Selesai: gudang %, % item baru, % item sudah ada di master, % baris stok awal.', v_wh, n_new, n_old, n_mov;
end
$mig$;

-- Cek hasil (jalankan terpisah):
-- select p.name, sum(m.qty) as total from public.stock_movements m join public.products p on p.id = m.product_id
--  where m.note like 'Migrasi stok awal La Mitra%' group by p.name order by p.name;
