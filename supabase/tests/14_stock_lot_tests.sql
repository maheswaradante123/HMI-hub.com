-- Pengujian Stok per kode sapi (migrasi 0025). Jalankan setelah 01 sampai 13.
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlstate; end $$;

do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  mkt constant text := '00000000-0000-0000-0000-000000000002';
  v_wh uuid; v_p uuid; v_n numeric; v_in numeric; v_out numeric; v_rest numeric; v_tot numeric;
begin
  select id into v_wh from public.warehouses where code='GD-TOKO';
  perform pg_temp.u(own);
  v_p := (public.cw_resolve_items('[{"name":"Item Uji Lot","cat":"Daging"}]'::jsonb)->0->>'product_id')::uuid;

  -- masuk atas nama dua sapi (kode dinormalkan ke huruf besar)
  perform public.record_stock_movement(v_p, v_wh, 'OPENING', 10, null, null, current_date - 5, ' sa1 ');
  perform public.record_stock_movement(v_p, v_wh, 'OPENING', 20, null, null, current_date - 2, 'SB2');
  select qty_in, qty_out, qty_rest into v_in, v_out, v_rest from public.v_stock_lots where product_id = v_p and lot = 'SA1';
  assert v_in = 10 and v_out = 0 and v_rest = 10, 'SA1 masuk 10';

  -- keluar tanpa kode sapi: dibebankan ke sapi tertua (SA1 habis dulu, sisanya SB2)
  perform public.record_stock_movement(v_p, v_wh, 'ADJUST_OUT', 15, null, 'susut');
  select qty_out, qty_rest into v_out, v_rest from public.v_stock_lots where product_id = v_p and lot = 'SA1';
  assert v_out = 10 and v_rest = 0, 'SA1 habis, keluar ' || v_out;
  select qty_out, qty_rest into v_out, v_rest from public.v_stock_lots where product_id = v_p and lot = 'SB2';
  assert v_out = 5 and v_rest = 15, 'SB2 keluar 5 sisa 15, dapat ' || v_out || '/' || v_rest;
  select sum(qty_rest) into v_tot from public.v_stock_lots where product_id = v_p;
  assert v_tot = (select qty from public.v_stock_summary where product_id = v_p), 'jumlah sisa per sapi = stok total';

  -- keluar atas nama sapi tertentu tidak boleh melebihi sisa sapi itu
  assert pg_temp.err(format('select public.record_stock_movement(%L,%L,''ADJUST_OUT'',20,null,''x'',null,''SB2'')', v_p, v_wh)) = '22023', 'melebihi sisa sapi SB2';
  perform public.record_stock_movement(v_p, v_wh, 'ADJUST_OUT', 5, null, 'rusak', null, 'sb2');
  select qty_rest into v_rest from public.v_stock_lots where product_id = v_p and lot = 'SB2';
  assert v_rest = 10, 'SB2 sisa 10 setelah keluar atas nama sendiri, dapat ' || v_rest;

  -- masuk tanpa kode sapi tampil sebagai baris tanpa kode dan menutup sebagian keluaran tanpa kode
  perform public.record_stock_movement(v_p, v_wh, 'OPENING', 4, null, null);
  select sum(qty_rest) into v_tot from public.v_stock_lots where product_id = v_p;
  assert v_tot = 14, 'total sisa 14, dapat ' || v_tot;
  assert exists (select 1 from public.v_stock_lots where product_id = v_p and lot is null and qty_in = 4), 'baris tanpa kode sapi';
  select qty_rest into v_rest from public.v_stock_lots where product_id = v_p and lot = 'SB2';
  assert v_rest = 14 - 0, 'SB2 menanggung sisa, dapat ' || v_rest;

  -- panjang kode dibatasi; izin tetap
  assert pg_temp.err(format('select public.record_stock_movement(%L,%L,''OPENING'',1,null,null,null,%L)', v_p, v_wh, repeat('A', 41))) = '22023', 'kode sapi terlalu panjang';
  perform pg_temp.u(mkt);
  assert pg_temp.err(format('select public.record_stock_movement(%L,%L,''OPENING'',1,null,null,null,''ZZ'')', v_p, v_wh)) = '42501', 'marketing tidak boleh mencatat stok';
end $$;
