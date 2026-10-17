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
  v_cow uuid; v_wh uuid; v_sup uuid; v_top uuid; v_sk uuid; v_jeroan uuid; v_jagal uuid; v_potong uuid;
  v_cw uuid; v_cw2 uuid; v_ap uuid; v_ncs uuid; v_before numeric; v_after numeric; v_no text; r record; v_cnt int;
begin
  select id into v_cow from public.cow_types where code='BX';
  select id into v_wh from public.warehouses where code='GD-TOKO';
  select id into v_sup from public.suppliers where code='SUP-SAPI-A';
  select id into v_top from public.products where code='MF-TOPSIDE';
  select id into v_sk from public.products where code='MF-SENGKEL';
  select id into v_jeroan from public.non_carcass_types where code='JEROHAN';
  select id into v_jagal from public.customers where code='JAGAL-A';
  select id into v_potong from public.cost_types where code='POTONG';
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
  assert v_no ~ '^CW-[0-9]{4}-[0-9]{4}$', 'nomor CW';
  assert pg_temp.err(format('select public.save_doc(''CW'',null,%L::jsonb,''{}'')', jsonb_build_object('cow_type_id', v_cow, 'cow_number', ' bx-001', 'warehouse_id', v_wh, 'live_weight', 300, 'carcass_weight', 150))) = '23505', 'nomor sapi unik';
  assert pg_temp.err(format('select public.save_doc(''CW'',%L,''{"notes":"x"}'',%L::jsonb)', v_cw, '{"items":[{"product_id":null,"non_carcass_type_id":null,"weight":1}]}')) = '23514', 'item harus produk atau non-karkas';
  -- analisa sebelum final ditolak
  perform pg_temp.u(pur);
  assert pg_temp.err(format('select public.save_doc(''AP'',null,jsonb_build_object(''cw_id'',%L,''total_purchase'',1000),''{}'')', v_cw)) = '22023', 'analisa butuh penimbangan final';
  perform pg_temp.u(mkt);
  assert pg_temp.err(format('select public.doc_change_status(''CW'',%L,''FINAL'')', v_cw)) = '42501', 'marketing tidak boleh finalkan';
  perform pg_temp.u(prd);
  perform public.doc_change_status('CW', v_cw, 'FINAL');
  select coalesce(sum(qty),0) into v_after from public.v_stock_balance where product_id = v_top;
  assert v_after = v_before + 20, 'stok topside bertambah 20, selisih ' || (v_after - v_before);
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

  -- analisa
  perform pg_temp.u(pur);
  v_ap := public.save_doc('AP', null, jsonb_build_object('cw_id', v_cw, 'total_purchase', 25000000),
     jsonb_build_object('items', jsonb_build_array(
        jsonb_build_object('product_id', v_top, 'weight', 20, 'unit_price', 140000, 'price_source', 'PRICING'),
        jsonb_build_object('product_id', v_sk, 'weight', 160, 'unit_price', 100000, 'price_source', 'TYPED')),
       'costs', jsonb_build_array(jsonb_build_object('cost_type_id', v_potong, 'amount', 500000))));
  select * into r from public.v_purchase_analysis where id = v_ap;
  assert r.carcass_pct = 54.35, 'karkas % = 250/460, dapat ' || r.carcass_pct;
  assert r.meat_pct = 72.00, 'daging % = 180/250, dapat ' || r.meat_pct;
  assert r.carcass_price_per_kg = 100000, 'harga karkas per kg';
  assert r.revenue = 18800000 and r.noncarcass_amount = 1200000 and r.cost_total = 500000, 'angka analisa';
  assert r.profit = 18800000 + 1200000 - 25000000 - 500000, 'laba analisa, dapat ' || r.profit;
  assert pg_temp.err(format('select public.save_doc(''AP'',null,jsonb_build_object(''cw_id'',%L,''total_purchase'',1),''{}'')', v_cw)) = '23505', 'satu analisa aktif per penimbangan';

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
  select count(*) into v_cnt from public.v_purchase_analysis; assert v_cnt = 0, 'produksi tidak melihat analisa';
  perform pg_temp.u(mkt);
  select count(*) into v_cnt from public.carcass_weighings; assert v_cnt = 0, 'marketing tidak melihat penimbangan';
  raise notice 'SEMUA PENGUJIAN PHASE 11-12 LULUS';
end $$;
