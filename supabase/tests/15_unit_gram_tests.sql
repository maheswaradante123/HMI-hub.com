-- Pengujian satuan Gram (migrasi 0026). Jalankan setelah 01 sampai 14.
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;

do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  v_wh uuid; v_g uuid; v_kg uuid; v_hotel uuid; v_cw uuid; v_pl uuid; v_bal numeric; v_kg0 numeric;
begin
  select id into v_wh from public.warehouses where code='GD-TOKO';
  select id into v_kg from public.products where code='MF-TULANG-SOP';   -- seed: bersatuan KG
  select id into v_hotel from public.customers where code='HOTEL-A';
  perform pg_temp.u(own);

  -- item baru dari penimbangan otomatis bersatuan Gram; pengali 1000 untuk Gram dan 1 untuk KG
  v_g := (public.cw_resolve_items('[{"name":"Item Uji Gram","cat":"Daging"}]'::jsonb)->0->>'product_id')::uuid;
  assert (select u.code from public.products p join public.units u on u.id = p.unit_id where p.id = v_g) = 'GRAM', 'item baru bersatuan GRAM';
  assert public.stock_factor(v_g) = 1000 and public.stock_factor(v_kg) = 1, 'pengali 1000 untuk gram, 1 untuk kg';
  select coalesce(sum(qty),0) into v_kg0 from public.v_stock_balance where product_id = v_kg;

  -- penimbangan 12,5 kg masuk sebagai 12.500 gram; item KG tetap kg
  v_cw := public.save_doc('CW', null, jsonb_build_object('cow_number', 'GR-001', 'warehouse_id', v_wh, 'carcass_weight', 100),
    jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_g, 'weight', 12.5), jsonb_build_object('product_id', v_kg, 'weight', 3))));
  perform public.doc_change_status('CW', v_cw, 'FINAL');
  select coalesce(sum(qty),0) into v_bal from public.v_stock_balance where product_id = v_g; assert v_bal = 12500, 'CW 12,5 kg = 12500 gram, dapat ' || v_bal;
  select coalesce(sum(qty),0) into v_bal from public.v_stock_balance where product_id = v_kg; assert v_bal = v_kg0 + 3, 'item KG bertambah 3';

  -- packing list 2,5 kg mengurangi 2.500 gram; batal mengembalikan
  v_pl := public.save_doc('PL', null, jsonb_build_object('customer_id', v_hotel, 'warehouse_id', v_wh),
    jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_g, 'qty', 2.5))));
  perform public.doc_change_status('PL', v_pl, 'PACKED');
  select coalesce(sum(qty),0) into v_bal from public.v_stock_balance where product_id = v_g; assert v_bal = 10000, 'PL 2,5 kg = -2500 gram, dapat ' || v_bal;
  perform public.doc_change_status('PL', v_pl, 'CANCELLED', 'uji');
  select coalesce(sum(qty),0) into v_bal from public.v_stock_balance where product_id = v_g; assert v_bal = 12500, 'batal PL mengembalikan 2500 gram, dapat ' || v_bal;

  -- batal penimbangan menarik kembali 12.500 gram
  perform public.doc_change_status('CW', v_cw, 'VOID', 'uji');
  select coalesce(sum(qty),0) into v_bal from public.v_stock_balance where product_id = v_g; assert v_bal = 0, 'void CW menarik 12500 gram, dapat ' || v_bal;

  -- catat stok manual langsung dalam gram (tanpa pengali)
  perform public.record_stock_movement(v_g, v_wh, 'OPENING', 14620, null, null, current_date, 'NUR002');
  select coalesce(sum(qty),0) into v_bal from public.v_stock_balance where product_id = v_g; assert v_bal = 14620, 'catat stok langsung gram';
end $$;
