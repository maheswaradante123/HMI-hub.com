-- Pengujian Phase 8-10: harga Horeka, RO, Production Order, Packing List.
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
  v_hotel uuid; v_jagal uuid; v_top uuid; v_sk uuid; v_wh uuid; v_ro uuid; v_po uuid; v_pl uuid; v_cp uuid;
  v_n numeric; v_no text; v_st text; v_bal numeric; v_before numeric;
begin
  select id into v_hotel from public.customers where code='HOTEL-A';
  select id into v_jagal from public.customers where code='JAGAL-A';
  select id into v_top from public.products where code='MF-TOPSIDE';
  select id into v_sk  from public.products where code='MF-SENGKEL';
  select id into v_wh  from public.warehouses where code='GD-TOKO';

  -- sisa override dari tes 01 dibersihkan agar tes ini memakai izin bawaan role
  delete from public.user_permission_overrides;

  -- harga Horeka
  perform pg_temp.u(prd);
  assert pg_temp.err(format('select public.set_customer_price(%L,%L,100,current_date)', v_hotel, v_top)) = '42501', 'produksi tidak boleh set harga customer';
  perform pg_temp.u(mkt);
  assert pg_temp.err(format('select public.set_customer_price(%L,%L,100,current_date)', v_jagal, v_top)) = '22023', 'hanya Horeka';
  assert pg_temp.err(format('select public.set_customer_price(%L,%L,-5,current_date)', v_hotel, v_top)) = '22023', 'harga negatif';
  v_cp := public.set_customer_price(v_hotel, v_top, 135000, current_date - 10, 'kontrak');
  assert pg_temp.err(format('select public.set_customer_price(%L,%L,140000,current_date-10)', v_hotel, v_top)) = '22023', 'tanggal harus lebih baru';
  perform public.set_customer_price(v_hotel, v_top, 140000, current_date + 5);
  v_n := public.price_for(v_hotel, v_top);
  assert v_n = 135000, 'harga hotel hari ini 135000, dapat ' || v_n;
  v_n := public.price_for(v_hotel, v_sk);
  assert v_n is not null, 'jatuh ke harga toko jika tidak ada harga khusus';
  assert pg_temp.err('delete from public.customer_prices') is not null, 'harga customer tidak bisa dihapus';
  perform pg_temp.su();
  assert pg_temp.err('delete from public.customer_prices') is not null, 'bahkan superuser';

  -- RO oleh Marketing
  perform pg_temp.u(mkt);
  v_ro := public.save_doc('RO', null, jsonb_build_object('customer_id', v_hotel, 'delivery_date', current_date + 2),
     jsonb_build_object('items', jsonb_build_array(
        jsonb_build_object('product_id', v_top, 'qty', 12.5, 'unit_price', 0),
        jsonb_build_object('product_id', v_sk, 'qty', 4, 'unit_price', 90000))));
  select doc_number, total_amount into v_no, v_n from public.request_orders where id = v_ro;
  assert v_no ~ '^RO-[0-9]{4}-[0-9]{4}$', 'nomor RO';
  assert v_n = 12.5 * 135000 + 4 * 90000, 'total RO memakai harga Horeka otomatis, dapat ' || v_n;
  assert pg_temp.err(format('select public.save_doc(''RO'',null,%L::jsonb,''{"items":[{"product_id":"%s","qty":0}]}'')', jsonb_build_object('customer_id', v_hotel), v_top)) is not null, 'qty 0 ditolak';
  assert pg_temp.err(format('select public.doc_change_status(''PROD'',%L,''SUBMITTED'')', v_ro)) = 'P0002', 'jenis dokumen salah';

  -- PO tidak bisa dari RO yang belum dikonfirmasi
  assert pg_temp.err(format('select public.save_doc(''PROD'',null,jsonb_build_object(''ro_id'',%L),''{}'')', v_ro)) = '22023', 'RO belum konfirmasi';
  perform public.doc_change_status('RO', v_ro, 'CONFIRMED');
  assert pg_temp.err(format('select public.save_doc(''RO'',%L,''{"notes":"x"}'')', v_ro)) = '55000', 'RO terkonfirmasi terkunci';
  v_po := public.save_doc('PROD', null, jsonb_build_object('ro_id', v_ro, 'needed_date', current_date + 1),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'qty', 12.5), jsonb_build_object('product_id', v_sk, 'qty', 4))));
  perform public.doc_change_status('PROD', v_po, 'SUBMITTED');
  assert pg_temp.err(format('select public.doc_change_status(''PROD'',%L,''APPROVED'')', v_po)) = '42501', 'marketing tidak boleh menyetujui PO';
  perform pg_temp.u(prd);
  assert pg_temp.err(format('select public.save_doc(''PL'',null,jsonb_build_object(''po_id'',%L,''customer_id'',%L,''warehouse_id'',%L),''{}'')', v_po, v_hotel, v_wh)) = '22023', 'PO belum disetujui';
  perform pg_temp.u(own);
  assert pg_temp.err(format('select public.doc_change_status(''PROD'',%L,''REJECTED'')', v_po)) = '22023', 'tolak wajib alasan';
  perform public.doc_change_status('PROD', v_po, 'APPROVED');
  -- Marketing tidak bisa mengubah PO yang sudah disetujui; Owner bisa (keputusan Owner)
  perform pg_temp.u(mkt);
  assert pg_temp.err(format('select public.save_doc(''PROD'',%L,''{"notes":"x"}'')', v_po)) = '55000', 'marketing tidak boleh ubah PO disetujui';
  perform pg_temp.u(own);
  perform public.save_doc('PROD', v_po, '{"notes":"diubah Owner"}');
  assert (select notes from public.production_orders where id = v_po) = 'diubah Owner', 'Owner mengubah PO disetujui';

  -- Packing list oleh Produksi
  perform pg_temp.u(prd);
  select coalesce(sum(qty),0) into v_before from public.v_stock_balance where product_id = v_top;
  v_pl := public.save_doc('PL', null, jsonb_build_object('po_id', v_po, 'ro_id', v_ro, 'customer_id', v_hotel, 'warehouse_id', v_wh, 'driver_name', 'Budi', 'vehicle_plate', 'B 1234 XY'),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'qty', 12.5), jsonb_build_object('product_id', v_sk, 'qty', 4))));
  select doc_number into v_no from public.packing_lists where id = v_pl;
  assert v_no ~ '^PL-[0-9]{4}-[0-9]{4}$', 'nomor PL';
  -- stok sengkel 7 cukup, tapi minta 4; naikkan jadi 50 harus gagal tanpa mengubah apa pun
  perform public.save_doc('PL', v_pl, jsonb_build_object('po_id', v_po, 'ro_id', v_ro, 'customer_id', v_hotel, 'warehouse_id', v_wh),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'qty', 12.5), jsonb_build_object('product_id', v_sk, 'qty', 50))));
  assert pg_temp.err(format('select public.doc_change_status(''PL'',%L,''PACKED'')', v_pl)) = '22023', 'stok tidak cukup menggagalkan PACKED';
  select status into v_st from public.packing_lists where id = v_pl; assert v_st = 'DRAFT', 'status tetap DRAFT';
  select coalesce(sum(qty),0) into v_bal from public.v_stock_balance where product_id = v_top; assert v_bal = v_before, 'stok tidak berubah saat gagal';
  perform public.save_doc('PL', v_pl, jsonb_build_object('po_id', v_po, 'ro_id', v_ro, 'customer_id', v_hotel, 'warehouse_id', v_wh),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'qty', 12.5), jsonb_build_object('product_id', v_sk, 'qty', 4))));
  perform public.doc_change_status('PL', v_pl, 'PACKED');
  select coalesce(sum(qty),0) into v_bal from public.v_stock_balance where product_id = v_top; assert v_bal = v_before - 12.5, 'stok topside berkurang 12.5';
  assert pg_temp.err(format('select public.doc_change_status(''PL'',%L,''CANCELLED'',''salah'')', v_pl)) = '42501', 'produksi tidak boleh batalkan PL yang sudah dikemas';
  perform public.doc_change_status('PL', v_pl, 'DELIVERED');
  select delivered_at is not null into v_st from public.packing_lists where id = v_pl; assert v_st::boolean, 'delivered_at terisi';

  -- batal PL yang sudah dikemas oleh Owner mengembalikan stok
  perform pg_temp.u(own);
  v_pl := public.save_doc('PL', null, jsonb_build_object('customer_id', v_hotel, 'warehouse_id', v_wh),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'qty', 1))));
  select coalesce(sum(qty),0) into v_before from public.v_stock_balance where product_id = v_top;
  perform public.doc_change_status('PL', v_pl, 'PACKED');
  perform public.doc_change_status('PL', v_pl, 'CANCELLED', 'salah kirim');
  select coalesce(sum(qty),0) into v_bal from public.v_stock_balance where product_id = v_top; assert v_bal = v_before, 'stok kembali setelah batal';

  -- visibilitas
  perform pg_temp.u(pur);
  assert (select count(*) from public.request_orders) = 0, 'purchasing tidak melihat RO';
  -- Purchasing kini boleh melihat Invoice (matriks Owner), sehingga harga customer ikut terlihat.
  raise notice 'SEMUA PENGUJIAN PHASE 8-10 LULUS';
end $$;
