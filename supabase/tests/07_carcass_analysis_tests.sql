-- Pengujian Phase 11-12: Penimbangan karkas, penjualan non-karkas, analisa pembelian.
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;
create function pg_temp.su() returns void language plpgsql as $$ begin reset role; end $$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlstate; end $$;

do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  mkt constant text := '00000000-0000-0000-0000-000000000002';
  pur constant text := '00000000-0000-0000-0000-000000000003';
  acc constant text := '00000000-0000-0000-0000-000000000004';
  prd constant text := '00000000-0000-0000-0000-000000000005';
  v_cow uuid; v_wh uuid; v_sup uuid; v_top uuid; v_sk uuid; v_jeroan uuid; v_jagal uuid; v_potong uuid; v_jeroan_p uuid;
  v_cw uuid; v_cw2 uuid; v_cw3 uuid; v_cw4 uuid; v_ap uuid; v_ap2 uuid; v_j jsonb; v_j2 jsonb; v_cw5 uuid; v_no2 text; v_ncs uuid; v_before numeric; v_after numeric; v_no text; r record; v_cnt int;
begin
  select id into v_cow from public.cow_types where code='BX';
  select id into v_wh from public.warehouses where code='GD-TOKO';
  select id into v_sup from public.suppliers where code='SUP-SAPI-A';
  select id into v_top from public.products where code='MF-TOPSIDE';
  select id into v_sk from public.products where code='MF-SENGKEL';
  select id into v_jeroan from public.non_carcass_types where code='JEROHAN';
  select id into v_jagal from public.customers where code='JAGAL-A';
  select id into v_potong from public.cost_types where code='POTONG';
  v_jeroan_p := v_top;
  select coalesce(sum(qty),0) into v_before from public.v_stock_balance where product_id = v_top;

  -- Penimbangan oleh Produksi (matriks Owner); tidak ada CPJ otomatis (tabel CPJ belum ada pun tidak masalah)
  perform pg_temp.u(prd);
  assert pg_temp.err(format('select public.save_doc(''CW'',null,%L::jsonb,''{}'')', jsonb_build_object('weigh_date', current_date, 'cow_type_id', v_cow, 'cow_number','BX-001','warehouse_id', v_wh,'live_weight',100,'carcass_weight',200))) = '23514', 'karkas > hidup ditolak';
  v_cw := public.save_doc('CW', null, jsonb_build_object('cow_type_id', v_cow, 'cow_number', 'BX-001', 'supplier_id', v_sup, 'warehouse_id', v_wh, 'live_weight', 460, 'carcass_weight', 250),
    jsonb_build_object('items', jsonb_build_array(
       jsonb_build_object('product_id', v_top, 'weight', 20),
       jsonb_build_object('product_id', v_sk, 'weight', 160),
       jsonb_build_object('non_carcass_type_id', v_jeroan, 'weight', 30))));
  select doc_number into v_no from public.carcass_weighings where id = v_cw;
  assert v_no ~ '^CW-[0-9]{3,}-BX001-[IVX]+-[0-9]{2}$', 'nomor CW CW-001-KODESAPI-BULAN-TAHUN, dapat ' || v_no;
  assert pg_temp.err(format('select public.save_doc(''CW'',null,%L::jsonb,''{}'')', jsonb_build_object('cow_type_id', v_cow, 'cow_number', ' bx-001', 'warehouse_id', v_wh, 'live_weight', 300, 'carcass_weight', 150))) = '23505', 'nomor sapi unik';
  assert pg_temp.err(format('select public.save_doc(''CW'',%L,''{"notes":"x"}'',%L::jsonb)', v_cw, '{"items":[{"product_id":null,"non_carcass_type_id":null,"weight":1}]}')) = '23514', 'item harus produk atau non-karkas';
  -- berat hidup dan jenis sapi opsional; nomor berurut; item baru dibuat otomatis di master
  v_j := public.cw_resolve_items('[{"name":"Sengkel","cat":"Tulang"},{"name":"Lidah Baru","cat":"Jeroan"},{"name":"Babat X","cat":"Non-Karkas"},{"name":"Daging Baru","cat":"Daging"}]'::jsonb);
  assert (v_j->0->>'product_id') = v_sk::text, 'nama yang sudah ada memakai produk lama walau kategori beda';
  assert (select pc.code from public.products p join public.product_categories pc on pc.id = p.category_id where p.id = (v_j->1->>'product_id')::uuid) = 'JEROHAN', 'produk baru berkategori Jeroan';
  assert (select pc.code from public.products p join public.product_categories pc on pc.id = p.category_id where p.id = (v_j->3->>'product_id')::uuid) = 'DAGING', 'produk baru berkategori Daging';
  assert (v_j->2->>'non_carcass_type_id') is not null and (v_j->2->>'product_id') is null, 'non-karkas baru masuk master non-karkas';
  v_j2 := public.cw_resolve_items('[{"name":"lidah baru","cat":"Jeroan"},{"name":"BABAT x","cat":"Non-Karkas"}]'::jsonb);
  assert (v_j2->0->>'product_id') = (v_j->1->>'product_id') and (v_j2->1->>'non_carcass_type_id') = (v_j->2->>'non_carcass_type_id'), 'resolusi nama tidak membuat dobel';
  assert pg_temp.err('select public.cw_resolve_items(''[{"name":"X","cat":"Sayur"}]''::jsonb)') = '22023', 'kategori tidak dikenal ditolak';
  v_cw5 := public.save_doc('CW', null, jsonb_build_object('cow_number', 'AMF014', 'warehouse_id', v_wh, 'carcass_weight', 356),
    jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_jeroan_p, 'weight', 5))));
  select doc_number into v_no2 from public.carcass_weighings where id = v_cw5;
  assert v_no2 ~ '^CW-[0-9]{3,}-AMF014-[IVX]+-[0-9]{2}$', 'CW tanpa berat hidup dan jenis sapi, nomor ' || v_no2;
  assert substr(v_no2, 4, 3)::int = substr(v_no, 4, 3)::int + 1, 'urutan CW naik satu';
  assert public.cw_next_seq() = substr(v_no2, 4, 3)::int + 1, 'cw_next_seq = urutan berikutnya';
  perform public.save_doc('CW', v_cw5, jsonb_build_object('notes', 'x'));
  perform pg_temp.u(mkt);
  assert pg_temp.err('select public.cw_resolve_items(''[{"name":"Y","cat":"Daging"}]''::jsonb)') = '42501', 'marketing tidak boleh membuat item';
  perform pg_temp.u(prd);
  perform public.doc_change_status('CW', v_cw5, 'VOID', 'uji');

  -- analisa sebelum final ditolak
  perform pg_temp.u(pur);
  assert pg_temp.err(format('select public.save_doc(''AP'',null,jsonb_build_object(''supplier_id'',%L,''cow_type_id'',%L,''total_purchase'',1000),jsonb_build_object(''cows'',jsonb_build_array(jsonb_build_object(''cw_id'',%L))))', v_sup, v_cow, v_cw)) = '22023', 'analisa butuh penimbangan final';
  perform pg_temp.u(mkt);
  assert pg_temp.err(format('select public.doc_change_status(''CW'',%L,''FINAL'')', v_cw)) = '42501', 'marketing tidak boleh finalkan';
  perform pg_temp.u(prd);
  perform public.doc_change_status('CW', v_cw, 'FINAL');
  select coalesce(sum(qty),0) into v_after from public.v_stock_balance where product_id = v_top;
  assert v_after = v_before + 20, 'stok topside bertambah 20, selisih ' || (v_after - v_before);
  assert (select qty_in from public.v_stock_lots where product_id = v_top and lot = 'BX-001') = 20, 'stok CW tercatat atas nama kode sapi BX-001';
  assert pg_temp.err(format('select public.save_doc(''CW'',%L,''{"notes":"x"}'')', v_cw)) = '55000', 'CW final terkunci';

  -- daging melebihi karkas
  v_cw2 := public.save_doc('CW', null, jsonb_build_object('cow_type_id', v_cow, 'cow_number', 'BX-002', 'warehouse_id', v_wh, 'live_weight', 400, 'carcass_weight', 200),
    jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'weight', 250))));
  assert pg_temp.err(format('select public.doc_change_status(''CW'',%L,''FINAL'')', v_cw2)) = '22023', 'daging > karkas ditolak';
  perform public.doc_change_status('CW', v_cw2, 'VOID', 'salah timbang');

  -- penjualan non-karkas (Kasir, matriks Owner)
  perform pg_temp.u('00000000-0000-0000-0000-000000000006');
  assert pg_temp.err(format('select public.save_doc(''NCS'',null,jsonb_build_object(''customer_id'',%L,''cw_id'',%L),''{}'')',
         (select id from public.customers where code='HOTEL-A'), v_cw)) = '22023', 'pembeli harus tipe non-karkas';
  v_ncs := public.save_doc('NCS', null, jsonb_build_object('customer_id', v_jagal, 'cw_id', v_cw),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('non_carcass_type_id', v_jeroan, 'weight', 30, 'unit_price', 40000))));
  assert (select total_amount from public.noncarcass_sales where id = v_ncs) = 1200000, 'total non-karkas 1.2jt';
  perform public.doc_change_status('NCS', v_ncs, 'CONFIRMED');
  assert pg_temp.err(format('select public.save_doc(''NCS'',null,jsonb_build_object(''customer_id'',%L,''cw_id'',%L),jsonb_build_object(''items'',jsonb_build_array(jsonb_build_object(''non_carcass_type_id'',%L,''weight'',1,''unit_price'',1000))))', v_jagal, v_cw, v_jeroan)) = '23505', 'satu nota aktif per sapi';

  -- analisa: supplier, jenis sapi, banyak sapi, non-karkas diketik, Total Biaya otomatis atau manual
  perform pg_temp.u(pur);
  assert pg_temp.err(format('select public.save_doc(''AP'',null,jsonb_build_object(''cow_type_id'',%L,''total_purchase'',1),jsonb_build_object(''cows'',jsonb_build_array(jsonb_build_object(''cw_id'',%L))))', v_cow, v_cw)) = '22023', 'supplier wajib';
  v_ap := public.save_doc('AP', null, jsonb_build_object('supplier_id', v_sup, 'cow_type_id', v_cow, 'analysis_date', date '2026-04-21', 'total_purchase', 25000000, 'top_date', date '2026-05-21', 'supplier_invoice', 'INV-77'),
     jsonb_build_object('cows', jsonb_build_array(jsonb_build_object('cw_id', v_cw)),
       'items', jsonb_build_array(
        jsonb_build_object('product_id', v_top, 'weight', 20, 'unit_price', 140000, 'price_source', 'PRICING'),
        jsonb_build_object('product_id', v_sk, 'weight', 160, 'unit_price', 100000, 'price_source', 'TYPED')),
       'nonk', jsonb_build_array(jsonb_build_object('name', 'Jeroan', 'weight', 30, 'unit_price', 40000), jsonb_build_object('name', 'Babat', 'weight', null, 'unit_price', 20000)),
       'costs', jsonb_build_array(jsonb_build_object('cost_type_id', v_potong, 'amount', 500000))));
  select doc_number into v_no from public.purchase_analyses where id = v_ap;
  assert v_no ~ '^[0-9]{3}-[A-Z0-9]+-BX-IV-26$', 'nomor AP format 001-SUPPLIER-BX-IV-26, dapat ' || v_no;
  select * into r from public.v_purchase_analysis where id = v_ap;
  assert r.carcass_pct = 54.35, 'karkas % = 250/460, dapat ' || r.carcass_pct;
  assert r.meat_weight = 180 and r.meat_pct = 72.00, 'daging % = 180/250, dapat ' || r.meat_pct;
  assert r.carcass_price_per_kg = 100000, 'harga karkas per kg';
  assert r.revenue = 18800000 and r.noncarcass_amount = 1200000 and r.cost_total = 500000, 'angka analisa';
  assert r.total_cost = 25500000, 'total biaya = harga sapi + operasional, dapat ' || r.total_cost;
  assert r.profit = 18800000 + 1200000 - 25500000, 'laba analisa, dapat ' || r.profit;
  -- Total Biaya manual menggantikan penjumlahan otomatis
  perform public.save_doc('AP', v_ap, jsonb_build_object('supplier_id', v_sup, 'cow_type_id', v_cow, 'analysis_date', date '2026-04-21', 'total_purchase', 25000000, 'manual_total_cost', 26000000, 'lower_side', 100, 'upper_side', 80));
  select * into r from public.v_purchase_analysis where id = v_ap;
  assert r.total_cost = 26000000 and r.profit = 20000000 - 26000000, 'total biaya manual, dapat ' || r.total_cost || ' / ' || r.profit;
  assert r.lower_side = 100 and r.upper_side = 80, 'lower dan upper side tersimpan';
  -- nomor berikutnya naik satu pada tahun yang sama
  assert pg_temp.err(format('select public.save_doc(''AP'',null,jsonb_build_object(''supplier_id'',%L,''cow_type_id'',%L,''total_purchase'',1),jsonb_build_object(''cows'',jsonb_build_array(jsonb_build_object(''cw_id'',%L))))', v_sup, v_cow, v_cw)) = '23505', 'satu sapi hanya di satu analisa aktif';
  -- banyak sapi dalam satu analisa
  perform pg_temp.u(prd);
  v_cw3 := public.save_doc('CW', null, jsonb_build_object('cow_type_id', v_cow, 'cow_number', 'BX-003', 'supplier_id', v_sup, 'warehouse_id', v_wh, 'live_weight', 400, 'carcass_weight', 200),
    jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'weight', 50))));
  v_cw4 := public.save_doc('CW', null, jsonb_build_object('cow_type_id', v_cow, 'cow_number', 'BX-004', 'supplier_id', v_sup, 'warehouse_id', v_wh, 'live_weight', 300, 'carcass_weight', 150),
    jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'weight', 30))));
  perform public.doc_change_status('CW', v_cw3, 'FINAL'); perform public.doc_change_status('CW', v_cw4, 'FINAL');
  perform pg_temp.u(pur);
  v_ap2 := public.save_doc('AP', null, jsonb_build_object('supplier_id', v_sup, 'cow_type_id', v_cow, 'analysis_date', date '2026-05-02', 'total_purchase', 35000000),
     jsonb_build_object('cows', jsonb_build_array(jsonb_build_object('cw_id', v_cw3), jsonb_build_object('cw_id', v_cw4)),
       'items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'weight', 80, 'unit_price', 140000, 'price_source', 'TYPED'))));
  select * into r from public.v_purchase_analysis where id = v_ap2;
  assert r.carcass_weight = 350 and r.live_weight = 700 and r.cow_number = 'BX-003, BX-004', 'dua sapi dijumlah, dapat ' || r.carcass_weight || ' ' || r.cow_number;
  assert r.carcass_price_per_kg = 100000 and r.meat_pct = round(80.0 / 350 * 100, 2), 'harga karkas dan daging % dua sapi';
  select doc_number into v_no from public.purchase_analyses where id = v_ap2;
  assert v_no ~ '^[0-9]{3}-[A-Z0-9]+-BX-V-26$', 'nomor bulan romawi V, dapat ' || v_no;
  assert (select substr(doc_number, 1, 3)::int from public.purchase_analyses where id = v_ap2) = (select substr(doc_number, 1, 3)::int from public.purchase_analyses where id = v_ap) + 1, 'urut naik per tahun';
  assert public.ap_next_seq('26') = (select max(substr(doc_number, 1, 3)::int) from public.purchase_analyses where doc_number ~ '-26$') + 1, 'ap_next_seq = urut berikutnya';
  assert public.ap_next_seq('99') = 1, 'tahun baru mulai dari 1';
  -- analisa final butuh sapi dan item; analisa batal membebaskan sapi
  assert pg_temp.err(format('select public.doc_change_status(''AP'',%L,''FINAL'')', (select public.save_doc('AP', null, jsonb_build_object('supplier_id', v_sup, 'cow_type_id', v_cow, 'total_purchase', 1), '{}'::jsonb)))) = '22023', 'final butuh sapi';
  perform public.doc_change_status('AP', v_ap2, 'VOID', 'salah input');
  perform public.save_doc('AP', null, jsonb_build_object('supplier_id', v_sup, 'cow_type_id', v_cow, 'total_purchase', 1), jsonb_build_object('cows', jsonb_build_array(jsonb_build_object('cw_id', v_cw3))));

  -- perubahan harga master setelah analisa tidak mengubah angka analisa (harga disimpan)
  perform pg_temp.su();
  update public.ap_items set unit_price = unit_price where ap_id = v_ap;
  perform pg_temp.u(pur);
  perform public.doc_change_status('AP', v_ap, 'FINAL');
  assert pg_temp.err(format('select public.doc_change_status(''CW'',%L,''VOID'',''x'')', v_cw)) = '42501', 'purchasing tidak boleh batalkan CW final';
  perform pg_temp.u(own);
  assert pg_temp.err(format('select public.doc_change_status(''CW'',%L,''VOID'',''x'')', v_cw)) = '55000', 'analisa aktif menghalangi pembatalan CW';

  -- visibilitas
  perform pg_temp.u(prd);
  assert public.ap_next_seq('26') is null, 'produksi tidak boleh membaca urutan analisa';
  select count(*) into v_cnt from public.v_purchase_analysis; assert v_cnt = 0, 'produksi tidak melihat analisa';
  perform pg_temp.u(mkt);
  select count(*) into v_cnt from public.carcass_weighings; assert v_cnt = 0, 'marketing tidak melihat penimbangan';
  raise notice 'SEMUA PENGUJIAN PHASE 11-12 LULUS';
end $$;
