-- Pengujian Delivery Order (Surat Jalan): dari Packing List, nomor, syarat tiap tahap, PL otomatis terkirim, tautan GDrive.
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlstate; end $$;
do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  mkt constant text := '00000000-0000-0000-0000-000000000002';
  pur constant text := '00000000-0000-0000-0000-000000000003';
  prd constant text := '00000000-0000-0000-0000-000000000005';
  v_hotel uuid; v_top uuid; v_wh uuid; v_pl uuid; v_pl2 uuid; v_do uuid; r record;
begin
  select id into v_hotel from public.customers where code='HOTEL-A';
  select id into v_top from public.products where code='MF-TOPSIDE';
  select id into v_wh  from public.warehouses where code='GD-TOKO';
  delete from public.user_permission_overrides;

  perform pg_temp.u(own);
  v_pl2 := public.save_doc('PL', null, jsonb_build_object('customer_id', v_hotel, 'warehouse_id', v_wh),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'qty', 1))));
  v_pl := public.save_doc('PL', null, jsonb_build_object('customer_id', v_hotel, 'warehouse_id', v_wh, 'driver_name', 'Budi', 'vehicle_plate', 'B 1 X'),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'qty', 1))));

  -- belum dikemas: tidak boleh dibuatkan surat jalan
  assert pg_temp.err(format($q$select public.save_doc('DO', null, jsonb_build_object('pl_id', %L))$q$, v_pl)) = '22023', 'PL draf ditolak';
  perform public.doc_change_status('PL', v_pl, 'PACKED');

  -- Owner/Produksi boleh; Purchasing tidak punya izin
  perform pg_temp.u(pur);
  assert pg_temp.err(format($q$select public.save_doc('DO', null, jsonb_build_object('pl_id', %L))$q$, v_pl)) = '42501', 'purchasing tidak boleh';
  perform pg_temp.u(prd);
  v_do := public.save_doc('DO', null, jsonb_build_object('pl_id', v_pl, 'driver_name', 'Budi', 'vehicle_plate', 'B 1 X', 'delivery_address', 'Jl. Rasuna', 'scan_url', ''));
  select * into r from public.delivery_orders where id = v_do;
  assert r.doc_number ~ '^DO-[0-9]{3}-[IVX]+-[0-9]{2}$', 'nomor DO: ' || r.doc_number;
  assert r.customer_id = v_hotel and r.status = 'DRAFT' and r.scan_url is null, 'customer dari PL, scan kosong jadi null';
  assert pg_temp.err(format($q$select public.save_doc('DO', null, jsonb_build_object('pl_id', %L))$q$, v_pl)) = '23505', 'satu PL satu surat jalan aktif';
  assert pg_temp.err(format($q$select public.save_doc('DO', %L, jsonb_build_object('pl_id', %L))$q$, v_do, v_pl2)) = '22023', 'PL tidak bisa diganti';

  -- tahap demi tahap
  assert pg_temp.err(format($q$select public.doc_change_status('DO', %L, 'RECEIVED')$q$, v_do)) = '55000', 'tidak boleh loncat tahap';
  perform public.doc_change_status('DO', v_do, 'SENT');
  assert pg_temp.err(format($q$select public.doc_change_status('DO', %L, 'RECEIVED')$q$, v_do)) = '22023', 'penerima wajib';
  perform public.save_doc('DO', v_do, jsonb_build_object('pl_id', v_pl, 'receiver_name', 'Pak Adim', 'received_on', '2026-10-19'));
  perform public.doc_change_status('DO', v_do, 'RECEIVED');
  assert (select status from public.packing_lists where id = v_pl) = 'DELIVERED', 'PL otomatis terkirim';
  assert exists (select 1 from public.doc_status_history where doc_type = 'PL' and doc_id = v_pl and to_status = 'DELIVERED'), 'riwayat PL tercatat';
  assert pg_temp.err(format($q$select public.doc_change_status('DO', %L, 'ARCHIVED')$q$, v_do)) = '22023', 'tautan GDrive wajib';
  assert pg_temp.err(format($q$select public.save_doc('DO', %L, jsonb_build_object('pl_id', %L, 'scan_url', 'https://contoh.com/x'))$q$, v_do, v_pl)) = '23514', 'hanya tautan Google Drive';
  perform public.save_doc('DO', v_do, jsonb_build_object('pl_id', v_pl, 'receiver_name', 'Pak Adim', 'received_on', '2026-10-19', 'scan_url', 'https://drive.google.com/file/d/abc/view'));
  perform public.doc_change_status('DO', v_do, 'ARCHIVED');
  assert pg_temp.err(format($q$select public.save_doc('DO', %L, jsonb_build_object('pl_id', %L, 'notes', 'x'))$q$, v_do, v_pl)) = '55000', 'arsip terkunci';

  -- batal butuh alasan dan izin hapus; setelah batal PL boleh dibuatkan surat jalan baru
  assert pg_temp.err(format($q$select public.doc_change_status('DO', %L, 'VOID', 'salah')$q$, v_do)) = '42501', 'produksi tidak boleh batalkan arsip';
  perform pg_temp.u(own);
  assert pg_temp.err(format($q$select public.doc_change_status('DO', %L, 'VOID')$q$, v_do)) = '22023', 'alasan wajib';
  perform public.doc_change_status('DO', v_do, 'VOID', 'salah input');
  perform public.save_doc('DO', null, jsonb_build_object('pl_id', v_pl));

  -- Marketing hanya lihat, tidak ada izin ubah modul lain
  perform pg_temp.u(mkt);
  assert (select count(*) from public.delivery_orders) = 2, 'marketing bisa melihat';
end $$;
