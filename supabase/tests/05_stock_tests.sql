-- Pengujian Phase 7 (kerangka dokumen + Stok). Jalankan setelah 01 sampai 04.
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
  prd constant text := '00000000-0000-0000-0000-000000000005';
  v_top uuid; v_sk uuid; v_wh uuid; v_so uuid; v_n numeric; v_no text; v_low boolean; v_cost numeric; v_rows int;
begin
  select id into v_top from public.products where code='MF-TOPSIDE';
  select id into v_sk  from public.products where code='MF-SENGKEL';
  select id into v_wh  from public.warehouses where code='GD-TOKO';

  -- izin
  perform pg_temp.u(mkt);
  assert pg_temp.err(format('select public.record_stock_movement(%L,%L,''OPENING'',10,null,null)', v_top, v_wh)) = '42501', 'marketing tidak boleh mencatat stok';
  assert pg_temp.err(format('insert into public.stock_movements(product_id,warehouse_id,movement_type,qty) values (%L,%L,''OPENING'',5)', v_top, v_wh)) = '42501', 'insert langsung ditolak';

  -- stok awal oleh Produksi
  perform pg_temp.u(prd);
  perform public.record_stock_movement(v_top, v_wh, 'OPENING', 25.5, null, null);
  select qty into v_n from public.v_stock_summary where product_id = v_top;
  assert v_n = 25.5, 'saldo 25.5, dapat ' || v_n;
  assert pg_temp.err(format('select public.record_stock_movement(%L,%L,''ADJUST_OUT'',1,null,null)', v_top, v_wh)) = '22023', 'penyesuaian tanpa alasan';
  assert pg_temp.err(format('select public.record_stock_movement(%L,%L,''ADJUST_OUT'',100,null,''rusak'')', v_top, v_wh)) = '22023', 'stok tidak boleh minus';
  assert pg_temp.err(format('select public.record_stock_movement(%L,%L,''OUT_SALE'',1,null,''x'')', v_top, v_wh)) = '22023', 'jenis tidak diizinkan';
  assert pg_temp.err(format('select public.record_stock_movement(%L,%L,''IN_PURCHASE'',5,1000,null)', v_top, v_wh)) is not null, 'produksi tanpa pricing_cost tidak boleh isi harga';
  perform public.record_stock_movement(v_top, v_wh, 'ADJUST_OUT', 5.5, null, 'rusak');
  select qty, is_low into v_n, v_low from public.v_stock_summary where product_id = v_top;
  assert v_n = 20 and v_low = false, 'saldo 20 setelah koreksi';   -- min_stock topside = 20
  perform public.record_stock_movement(v_top, v_wh, 'ADJUST_OUT', 0.5, null, 'susut');
  select is_low into v_low from public.v_stock_summary where product_id = v_top;
  assert v_low = true, 'di bawah minimum harus ditandai';

  -- nilai stok memakai harga beli terakhir
  select count(*) into v_rows from public.v_stock_value; assert v_rows = 0, 'produksi tidak melihat nilai stok';
  perform pg_temp.u(own);
  perform public.record_stock_movement(v_top, v_wh, 'IN_PURCHASE', 10, 100000, null, current_date - 1);
  perform public.record_stock_movement(v_top, v_wh, 'IN_PURCHASE', 10, 120000, null);
  select last_cost into v_cost from public.v_stock_value where product_id = v_top;
  assert v_cost = 120000, 'harga beli terakhir 120000, dapat ' || coalesce(v_cost::text,'null');
  assert pg_temp.err(format('select public.record_stock_movement(%L,%L,''OPENING'',1,null,null,current_date+3)', v_sk, v_wh)) = '22023', 'tanggal masa depan';

  -- riwayat tidak bisa diubah, bahkan oleh superuser
  perform pg_temp.su();
  assert pg_temp.err('update public.stock_movements set qty = 1') is not null, 'mutasi immutable';
  assert pg_temp.err('delete from public.stock_movements') is not null, 'mutasi tidak bisa dihapus';

  -- opname
  perform pg_temp.u(prd);
  v_so := public.save_doc('SO', null, jsonb_build_object('warehouse_id', v_wh, 'notes', 'cek bulanan'),
     jsonb_build_object('items', jsonb_build_array(
       jsonb_build_object('product_id', v_top, 'counted_qty', 38),
       jsonb_build_object('product_id', v_sk,  'counted_qty', 7))));
  select doc_number into v_no from public.stock_opnames where id = v_so;
  assert v_no ~ '^SO-[0-9]{4}-[0-9]{4}$', 'nomor opname ' || v_no;
  select system_qty into v_n from public.so_items where opname_id = v_so and product_id = v_top;
  assert v_n = 39.5, 'stok sistem 39.5, dapat ' || v_n;
  assert pg_temp.err(format('select public.doc_change_status(''SO'',%L,''APPROVED'')', v_so)) = '42501', 'produksi tidak boleh menyetujui opname';
  perform pg_temp.u(mkt);
  assert pg_temp.err(format('select public.save_doc(''SO'',%L,''{"notes":"x"}'')', v_so)) = '42501', 'marketing tidak boleh ubah opname';
  perform pg_temp.u(own);
  perform public.doc_change_status('SO', v_so, 'APPROVED');
  select qty into v_n from public.v_stock_summary where product_id = v_top; assert v_n = 38, 'topside dikoreksi ke 38, dapat ' || v_n;
  select qty into v_n from public.v_stock_summary where product_id = v_sk;  assert v_n = 7,  'sengkel masuk 7';
  assert pg_temp.err(format('select public.doc_change_status(''SO'',%L,''APPROVED'')', v_so)) = '55000', 'tidak bisa setujui dua kali';
  assert pg_temp.err(format('select public.save_doc(''SO'',%L,''{"notes":"x"}'')', v_so)) = '55000', 'dokumen disetujui terkunci';
  select count(*) into v_rows from public.doc_status_history where doc_type='SO' and doc_id=v_so; assert v_rows = 2, 'riwayat status 2, dapat ' || v_rows;
  raise notice 'SEMUA PENGUJIAN PHASE 7 LULUS';
end $$;
