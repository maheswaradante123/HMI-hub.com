-- ============================================================================
-- Migrasi stok awal daging/tulang/jeroan dari aplikasi lama (Product Management La Mitra)
-- DIBUAT OTOMATIS oleh scripts/gen-stok-awal.mjs dari supabase/data/stok_awal_daging.tsv
-- Jalankan SEKALI di Supabase SQL Editor (aman diulang: berhenti jika sudah pernah dijalankan).
--
-- UBAH 2 BARIS INI SEBELUM MENJALANKAN:
--   v_date : tanggal stok dihitung ("cut-off"), tidak boleh di masa depan
--   v_wh   : kode gudang tujuan
--   v_otak_kg : false = Otak dihitung PCS (angka apa adanya); true = Otak dihitung KG (angka gram ÷ 1000)
-- ============================================================================
do $mig$
declare
  v_date  date := (now() at time zone 'Asia/Jakarta')::date;   -- << tanggal cut-off
  v_wh    text := 'GD-TOKO';                                   -- << kode gudang
  v_otak_kg boolean := false;                                  -- << true bila angka Otak sebenarnya gram
  v_whid  uuid; v_pid uuid; v_cat uuid; v_unit uuid; v_code text; v_i int;
  r record; n_new int := 0; n_old int := 0; n_mov int := 0;
  c_marker constant text := 'Migrasi stok awal La Mitra';
begin
  select id into v_whid from public.warehouses where code = v_wh and is_active;
  if v_whid is null then raise exception 'Gudang % tidak ditemukan', v_wh; end if;
  if to_regprocedure('public.post_stock(uuid,uuid,text,numeric,numeric,text,uuid,text,date,text)') is null then
    raise exception 'Jalankan dulu migrasi 0025 (stok per kode sapi), lalu ulangi skrip ini';
  end if;
  if v_date > (now() at time zone 'Asia/Jakarta')::date then raise exception 'Tanggal cut-off tidak boleh di masa depan'; end if;
  if exists (select 1 from public.stock_movements where note like c_marker || '%') then
    raise exception 'Migrasi ini sudah pernah dijalankan — dihentikan agar stok tidak ganda';
  end if;

  -- 1) Master item: cocokkan nama (tanpa huruf besar/kecil); belum ada → dibuat (MANUFACTURE)
  for r in select * from (values
    ('Babat', 'Jeroan', 'KG'),
    ('Babat Handuk', 'Jeroan', 'KG'),
    ('Buntut', 'Jeroan', 'KG'),
    ('Gandik', 'Daging', 'KG'),
    ('Ginjal', 'Jeroan', 'KG'),
    ('Has Dalam', 'Daging', 'KG'),
    ('Has Luar', 'Daging', 'KG'),
    ('Hati', 'Jeroan', 'KG'),
    ('Jantung', 'Jeroan', 'KG'),
    ('Knuckle', 'Daging', 'KG'),
    ('Lamusir', 'Daging', 'KG'),
    ('Limpa', 'Jeroan', 'KG'),
    ('Otak', 'Jeroan', 'PCS'),
    ('Paru', 'Jeroan', 'KG'),
    ('Punuk', 'Daging', 'KG'),
    ('Sampil', 'Daging', 'KG'),
    ('Sancan', 'Daging', 'KG'),
    ('Sandung Lamur', 'Daging', 'KG'),
    ('Short Ribs', 'Tulang', 'KG'),
    ('Topside', 'Daging', 'KG'),
    ('Tulang Sop', 'Tulang', 'KG'),
    ('Tulang Sumsum', 'Tulang', 'KG'),
    ('Usus', 'Jeroan', 'KG')
  ) as t(name, cat, unit) loop
    select id into v_pid from public.products where lower(name) = lower(r.name);
    if v_pid is null then
      select id into v_cat from public.product_categories where code = case r.cat when 'Tulang' then 'TULANG' when 'Jeroan' then 'JEROHAN' else 'DAGING' end;
      select id into v_unit from public.units where code = case when r.name = 'Otak' and v_otak_kg then 'KG' else r.unit end;
      if v_cat is null or v_unit is null then raise exception 'Kategori/satuan untuk % belum ada di master', r.name; end if;
      v_code := trim(both '-' from left(upper(regexp_replace(r.name, '[^A-Za-z0-9]+', '-', 'g')), 30)); v_i := 0;
      while exists (select 1 from public.products where code = case when v_i = 0 then v_code else v_code || '-' || v_i end) loop v_i := v_i + 1; end loop;
      insert into public.products (code, name, product_type, category_id, unit_id)
      values (case when v_i = 0 then v_code else v_code || '-' || v_i end, r.name, 'MANUFACTURE', v_cat, v_unit);
      n_new := n_new + 1;
    else
      n_old := n_old + 1;
    end if;
  end loop;

  -- 2) Stok awal per item per kode sapi (kg; Otak = pcs). lot kosong = tanpa kode sapi.
  for r in select * from (values
    ('Babat', 'AINUL001', 3.585::numeric, 'JR003AINUL001'),
    ('Babat', 'AMF002', 7.655::numeric, 'JR006AMF002'),
    ('Babat', 'AMF003', 8.315::numeric, 'JR002AMF003'),
    ('Babat', 'AMF005', 11.605::numeric, 'JR004AMF005'),
    ('Babat', 'AMF006', 5.405::numeric, 'DG015AMF006'),
    ('Babat', 'AMF007', 7.98::numeric, 'JR015AMF007'),
    ('Babat', 'AMF008', 8.985::numeric, 'JR016AMF008'),
    ('Babat', 'NUR001', 8.695::numeric, 'JR023NUR001'),
    ('Babat', 'NUR002', 11.885::numeric, 'JR017NUR002'),
    ('Babat', 'OKA001', 8.58::numeric, 'JR002OKA001'),
    ('Babat', 'REOT008', 9.39::numeric, 'JR006REOT008'),
    ('Babat', 'REOT016', 10.42::numeric, 'JR002REOT016'),
    ('Babat', 'REOT017', 8.36::numeric, 'JR002REOT017'),
    ('Babat', 'REOT018', 9.25::numeric, 'JR001REOT018'),
    ('Babat', 'REOT019', 7.455::numeric, 'JR002REOT019'),
    ('Babat', 'REOT020', 15.05::numeric, 'JR003REOT020'),
    ('Babat', 'REOT021', 11.955::numeric, 'JR002REOT021'),
    ('Babat', 'REOT022', 13.385::numeric, 'JR002REOT022'),
    ('Babat', 'REOT023', 8.3::numeric, 'JR003REOT023'),
    ('Babat', 'REOT024', 9.845::numeric, 'JR003REOT024'),
    ('Babat', 'REOT025', 7.68::numeric, 'JR003REOT025'),
    ('Babat', 'REOT026', 5.115::numeric, 'JR003REOT026'),
    ('Babat', 'REOT027', 12.675::numeric, 'JR004REOT027'),
    ('Babat Handuk', 'AMF004', 5.325::numeric, 'JR003AMF004'),
    ('Buntut', 'AMF007', 0.035::numeric, 'JR017AMF007'),
    ('Buntut', 'AMF011', 0.665::numeric, 'JR015AMF011'),
    ('Buntut', 'RPH001', 11.721::numeric, 'TL001RPH001'),
    ('Gandik', 'NUR001', 10.845::numeric, 'DG005NUR001'),
    ('Gandik', 'NUR002', 9.995::numeric, 'DG005NUR002'),
    ('Ginjal', 'AMF002', 0.705::numeric, 'JR008AMF002'),
    ('Ginjal', 'AMF010', 0.73::numeric, 'JR024AMF010'),
    ('Ginjal', 'AMF012', 0.84::numeric, 'JR008AMF012'),
    ('Ginjal', 'NUR001', 0.765::numeric, 'JR018NUR001'),
    ('Has Dalam', 'AMF014', 2.635::numeric, 'DG001AMF014'),
    ('Has Dalam', 'NUR001', 1.155::numeric, 'DG001NUR001'),
    ('Has Dalam', 'NUR002', 8.71::numeric, 'DG001NUR002'),
    ('Has Luar', 'AMF002', 6.35::numeric, 'DG002AMF002'),
    ('Has Luar', 'AMF005', 5.84::numeric, 'DG002AMF005'),
    ('Has Luar', 'AMF012', 5.885::numeric, 'DG002AMF012'),
    ('Has Luar', 'AMF013', 2.15::numeric, 'DG1AMF013'),
    ('Has Luar', 'NUR001', 12.01::numeric, 'DG002NUR001'),
    ('Has Luar', 'NUR002', 14.62::numeric, 'DG002NUR002'),
    ('Hati', null::text, 23.755::numeric, 'JR002'),
    ('Hati', 'AINUL001', 3.415::numeric, 'JR002AINUL001'),
    ('Hati', 'AMF002', 11.88::numeric, 'JRAMF002, JR002AMF002'),
    ('Hati', 'AMF003', 0.815::numeric, 'JR004AMF003'),
    ('Hati', 'AMF005', 0.675::numeric, 'JR002AMF005'),
    ('Hati', 'AMF008', 2.383::numeric, 'JR012AMF008'),
    ('Hati', 'AMF012', 4.555::numeric, 'JR002AMF012'),
    ('Hati', 'NUR002', 4.935::numeric, 'JR015NUR002'),
    ('Hati', 'OKA001', 5.395::numeric, 'JR003OKA001'),
    ('Hati', 'REOT008', 2.705::numeric, 'JR002REOT008'),
    ('Hati', 'REOT016', 3.48::numeric, 'JR004REOT016'),
    ('Hati', 'REOT017', 2.63::numeric, 'JR004REOT017'),
    ('Hati', 'REOT018', 3.575::numeric, 'JR004REOT018'),
    ('Hati', 'REOT019', 1.245::numeric, 'JR004REOT019'),
    ('Hati', 'REOT020', 1.305::numeric, 'JR002REOT020'),
    ('Hati', 'REOT021', 2.315::numeric, 'JR004REOT021'),
    ('Hati', 'REOT023', 2.921::numeric, 'JR002REOT023'),
    ('Hati', 'REOT024', 3.865::numeric, 'JR002REOT024'),
    ('Hati', 'REOT025', 3.56::numeric, 'JR001REOT025'),
    ('Hati', 'REOT027', 4.69::numeric, 'JR002REOT027'),
    ('Jantung', null::text, 10.87::numeric, 'JR005'),
    ('Jantung', 'AMF002', 1.415::numeric, 'JR004AMF002'),
    ('Jantung', 'AMF010', 1.06::numeric, 'JR017AMF010'),
    ('Jantung', 'AMF011', 1.335::numeric, 'JR018AMF011'),
    ('Jantung', 'AMF012', 1.47::numeric, 'JR006AMF012'),
    ('Jantung', 'NUR001', 1.26::numeric, 'JR017NUR001'),
    ('Jantung', 'NUR002', 1.73::numeric, 'JR020NUR002'),
    ('Jantung', 'REOT008', 1.785::numeric, 'JR004REOT008'),
    ('Knuckle', 'NUR002', 6.385::numeric, 'DG003NUR002'),
    ('Knuckle', 'REOT008', 0.485::numeric, 'DG011REOT008'),
    ('Lamusir', 'REOT001', 0.07::numeric, 'DG005REOT001'),
    ('Limpa', null::text, 6.12::numeric, 'JR003'),
    ('Limpa', 'AMF002', 1.08::numeric, 'JR003AMF002'),
    ('Limpa', 'AMF010', 1.075::numeric, 'JR023AMF010'),
    ('Limpa', 'AMF012', 0.83::numeric, 'JR007AMF012'),
    ('Limpa', 'NUR001', 0.64::numeric, 'JR019NUR001'),
    ('Limpa', 'NUR002', 1.03::numeric, 'JR019NUR002'),
    ('Otak', 'AMF002', 395::numeric, 'JR005AMF002'),
    ('Otak', 'AMF004', 375::numeric, 'JR006AMF004'),
    ('Otak', 'AMF006', 360::numeric, 'DG014AMF006'),
    ('Otak', 'AMF008', 275::numeric, 'JR014AMF008'),
    ('Otak', 'AMF011', 360::numeric, 'JR017AMF011'),
    ('Otak', 'NUR001', 410::numeric, 'JR016NUR001'),
    ('Otak', 'REOT008', 495::numeric, 'JR005REOT008'),
    ('Paru', 'AMF008', 4.63::numeric, 'JR013AMF008'),
    ('Paru', 'NUR002', 1.73::numeric, 'JR016NUR002'),
    ('Punuk', 'AINUL001', 1.39::numeric, 'DG012AINUL001'),
    ('Punuk', 'AMF005', 13.65::numeric, 'DG012AMF005'),
    ('Punuk', 'AMF008', 4.905::numeric, 'DG011AMF008'),
    ('Punuk', 'AMF009', 12.79::numeric, 'DG012AMF009'),
    ('Punuk', 'AMF010', 5.775::numeric, 'DG010AMF010'),
    ('Punuk', 'AMF012', 4.575::numeric, 'DG011AMF012'),
    ('Punuk', 'NUR002', 5.915::numeric, 'DG010NUR002'),
    ('Punuk', 'REOT027', 8.28::numeric, 'DG012REOT027'),
    ('Sampil', 'AMF011', 0.04::numeric, 'DG006AMF011'),
    ('Sampil', 'REOT007', 0.155::numeric, 'DG003REOT007'),
    ('Sancan', 'NUR002', 14.175::numeric, 'DG008NUR002'),
    ('Sandung Lamur', 'AMF005', 14.185::numeric, 'DG010AMF005'),
    ('Sandung Lamur', 'NUR002', 12.15::numeric, 'DG009NUR002'),
    ('Sandung Lamur', 'REOT027', 2.745::numeric, 'DG010REOT027'),
    ('Short Ribs', null::text, 49.435::numeric, 'Tulang IGA Kr jati'),
    ('Short Ribs', 'NUR002', 0.97::numeric, 'TL012NUR002'),
    ('Topside', 'AMF011', 0.125::numeric, 'DG004AMF011'),
    ('Topside', 'NUR001', 4.065::numeric, 'DG004NUR001'),
    ('Topside', 'NUR002', 13.125::numeric, 'DG004NUR002'),
    ('Topside', 'REOT026', 0.045::numeric, 'DG003REOT026'),
    ('Tulang Sop', null::text, 81.675::numeric, 'Tlkr01'),
    ('Tulang Sop', 'AMF002', 7.15::numeric, 'TL002AMF002'),
    ('Tulang Sop', 'AMF007', 2.24::numeric, 'TL021AMF007'),
    ('Tulang Sop', 'AMF011', 7.525::numeric, 'TL013AMF011'),
    ('Tulang Sop', 'AMF012', 6.51::numeric, 'TL002AMF012'),
    ('Tulang Sop', 'AMF013', 8.435::numeric, 'TL2AMF013'),
    ('Tulang Sop', 'NUR001', 3.54::numeric, 'TL013NUR001'),
    ('Tulang Sop', 'NUR002', 11.225::numeric, 'TL013NUR002'),
    ('Tulang Sop', 'REOT007', 10.115::numeric, 'TL002REOT007'),
    ('Tulang Sumsum', 'AMF007', 14.32::numeric, 'TL020AMF007'),
    ('Usus', 'AINUL001', 11.08::numeric, 'JR004AINUL001'),
    ('Usus', 'AMF002', 10.615::numeric, 'JR007AMF002'),
    ('Usus', 'AMF003', 8.19::numeric, 'JR003AMF003'),
    ('Usus', 'AMF004', 6.55::numeric, 'JR004AMF004'),
    ('Usus', 'AMF005', 13.055::numeric, 'JR005AMF005'),
    ('Usus', 'AMF007', 7::numeric, 'JR016AMF007'),
    ('Usus', 'AMF008', 10.925::numeric, 'JR017AMF008'),
    ('Usus', 'NUR001', 13.27::numeric, 'JR024NUR001'),
    ('Usus', 'NUR002', 13.595::numeric, 'JR018NUR002'),
    ('Usus', 'OKA001', 9.25::numeric, 'JR004OKA001'),
    ('Usus', 'REOT008', 11.905::numeric, 'JR007REOT008'),
    ('Usus', 'REOT016', 9.87::numeric, 'JR003REOT016'),
    ('Usus', 'REOT017', 8.785::numeric, 'JR003REOT017'),
    ('Usus', 'REOT018', 10.335::numeric, 'JR002REOT018'),
    ('Usus', 'REOT019', 7.135::numeric, 'JR003REOT019'),
    ('Usus', 'REOT020', 9.12::numeric, 'JR004REOT020'),
    ('Usus', 'REOT021', 8.995::numeric, 'JR003REOT021'),
    ('Usus', 'REOT022', 11.845::numeric, 'JR003REOT022'),
    ('Usus', 'REOT023', 7.68::numeric, 'JR004REOT023'),
    ('Usus', 'REOT024', 7.455::numeric, 'JR004REOT024'),
    ('Usus', 'REOT025', 7.455::numeric, 'JR004REOT025'),
    ('Usus', 'REOT026', 3.53::numeric, 'JR004REOT026'),
    ('Usus', 'REOT027', 11.2::numeric, 'JR005REOT027')
  ) as t(name, lot, qty, codes) loop
    select id into v_pid from public.products where lower(name) = lower(r.name);
    perform public.post_stock(v_pid, v_whid, 'OPENING', case when r.name = 'Otak' and v_otak_kg then round(r.qty / 1000, 3) else r.qty end, null, 'MANUAL', null,
      c_marker || ' (kode lama: ' || r.codes || ')', v_date, r.lot);
    n_mov := n_mov + 1;
  end loop;

  raise notice 'Selesai: % item baru, % item sudah ada di master, % baris stok awal.', n_new, n_old, n_mov;
end
$mig$;

-- Cek hasil (jalankan terpisah):
-- select p.name, sum(m.qty) as total from public.stock_movements m join public.products p on p.id = m.product_id
--  where m.note like 'Migrasi stok awal La Mitra%' group by p.name order by p.name;
