-- Pengujian migrasi 0042: sapi jogrok (harga per ekor, bobot opsional, perawatan tetap, beli kembali per ekor).
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;
create function pg_temp.fails(p_sql text, p_code text) returns boolean language plpgsql as $$
begin execute p_sql; return false;
exception when others then return sqlstate = p_code; end $$;
do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  v_id uuid; o record; l record; v_n integer; b record; v_w uuid;
begin
  perform pg_temp.u(own);
  -- jogrok tanpa bobot: harga = 1 Ekor x harga jogrok, perawatan tarif tetap, tidak ada penimbangan awal
  v_id := public.qurban_create_orders('Pak Jogrok', public.qurban_today(), 'FULL',
    jsonb_build_array(jsonb_build_object('cow', 'J-01', 'head_price', 25000000, 'care_price', 30000, 'buyback_price', 24000000)));
  select * into o from public.v_qurban_orders where id = v_id;
  assert o.sale_mode = 'HEAD' and o.initial_weight is null and o.care_fixed, 'pesanan jogrok tersimpan';
  assert o.buy_price = 25000000 and o.buyback_price = 24000000 and o.care_price = 30000, 'harga manual tersimpan';
  select * into l from public.qurban_order_lines(v_id) where line_no = 1;
  assert l.qty = 1 and l.unit = 'Ekor' and l.price = 25000000, 'baris pertama 1 Ekor x harga jogrok';
  assert o.total >= 25000000 + 30000, 'total memuat perawatan';
  assert (select count(*) from public.qurban_weighings where order_id = v_id) = 0, 'tanpa bobot tidak ada penimbangan awal';
  assert o.last_weight is null, 'bobot terakhir kosong';

  -- jogrok dengan bobot: bobot dicatat tetapi tidak memengaruhi harga
  v_id := public.qurban_create_orders('Bu Jogrok', public.qurban_today(), 'MONTHLY',
    jsonb_build_array(jsonb_build_object('cow', 'J-02', 'head_price', 18000000, 'care_price', 30000, 'buyback_price', 0, 'weight', 280)));
  select * into o from public.v_qurban_orders where id = v_id;
  assert o.initial_weight = 280 and o.last_weight = 280, 'bobot opsional tercatat';
  select * into l from public.qurban_order_lines(v_id) where line_no = 1;
  assert l.price = 18000000 and l.qty = 1, 'bobot kecil (di bawah 350) tidak menghalangi harga jogrok';

  -- campuran: satu per timbangan dan satu jogrok dalam satu proforma
  v_id := public.qurban_create_orders('Pak Campur', public.qurban_today(), 'FULL',
    jsonb_build_array(jsonb_build_object('cow', 'C-1', 'weight', 650),
                      jsonb_build_object('cow', 'C-2', 'head_price', 20000000, 'care_price', 30000, 'buyback_price', 19000000)));
  select count(*) into v_n from public.qurban_orders where pro_no = (select pro_no from public.qurban_orders where id = v_id);
  assert v_n = 2, 'dua sapi satu proforma';
  assert (select sale_mode from public.qurban_orders where cow_no = 'C-1') = 'WEIGHT', 'sapi timbangan tetap per Kg';

  -- validasi
  assert pg_temp.fails($q$select public.qurban_create_orders('X', public.qurban_today(), 'FULL', '[{"cow":"E1","head_price":0,"care_price":30000,"buyback_price":0}]'::jsonb)$q$, '22023'), 'harga jogrok wajib > 0';
  assert pg_temp.fails($q$select public.qurban_create_orders('X', public.qurban_today(), 'FULL', '[{"cow":"E2","head_price":1000000,"buyback_price":0}]'::jsonb)$q$, '22023'), 'tarif perawatan wajib';
  assert pg_temp.fails($q$select public.qurban_create_orders('X', public.qurban_today(), 'FULL', '[{"cow":"E3","weight":200}]'::jsonb)$q$, '22023'), 'per timbangan di bawah 350 Kg tetap ditolak';

  -- tagihan bulanan jogrok tanpa bobot memakai tarif tetap
  reset role;
  select id into v_w from public.qurban_orders where cow_no = 'J-02';
  update public.qurban_orders set status = 'PAID', inv_no = 'INV-928-X-26', inv_date = public.qurban_today(), due_date = public.qurban_today(), paid_at = now() where id = v_w;
  delete from public.qurban_weighings where order_id = v_w;
  update public.qurban_orders set initial_weight = null where id = v_w;
  perform pg_temp.u(own);
  perform public.qurban_create_bill(v_w);
  select * into b from public.qurban_bills where order_id = v_w;
  assert b.rate = 30000 and b.basis_weight = 0, 'tagihan jogrok tanpa bobot: tarif tetap, basis 0';

  reset role;
  delete from public.qurban_bills where order_id = v_w;
  delete from public.qurban_weighings where order_id in (select id from public.qurban_orders where cow_no in ('J-01','J-02','C-1','C-2'));
  delete from public.qurban_orders where cow_no in ('J-01','J-02','C-1','C-2');
end $$;
