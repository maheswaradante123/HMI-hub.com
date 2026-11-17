-- Pengujian migrasi 0043: akhir masa perawatan per pesanan (pedet jogrok dirawat sampai 2028).
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;
create function pg_temp.fails(p_sql text, p_code text) returns boolean language plpgsql as $$
begin execute p_sql; return false;
exception when others then return sqlstate = p_code; end $$;
do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  v_id uuid; v_w uuid; o record; v_last text; v_glob text; b record; v_cnt integer;
begin
  perform pg_temp.u(own);
  -- jogrok dengan akhir perawatan 2028: baris perawatan berlanjut sampai bulan itu
  v_id := public.qurban_create_orders('Pak Pedet', public.qurban_today(), 'FULL',
    jsonb_build_array(jsonb_build_object('cow', 'P-01', 'head_price', 12000000, 'care_price', 30000, 'buyback_price', 0, 'care_end', '2028-05-05')));
  select * into o from public.v_qurban_orders where id = v_id;
  assert o.care_end = date '2028-05-05', 'akhir perawatan khusus tersimpan';
  select max(descr) into v_last from public.qurban_order_lines(v_id) where line_no > 1 and descr like '%2028';
  assert v_last is not null, 'ada baris perawatan tahun 2028';
  assert (select sum(qty) from public.qurban_order_lines(v_id) where line_no > 1) =
         (date '2028-05-05' - public.qurban_today() + 1), 'jumlah hari perawatan = sampai 5 Mei 2028';

  -- tanpa care_end: tetap ikut pengaturan umum
  v_id := public.qurban_create_orders('Pak Umum', public.qurban_today(), 'FULL',
    jsonb_build_array(jsonb_build_object('cow', 'P-02', 'head_price', 12000000, 'care_price', 30000, 'buyback_price', 0)));
  select * into o from public.v_qurban_orders where id = v_id;
  assert o.care_end is null, 'care_end kosong = ikut pengaturan umum';
  assert (select sum(qty) from public.qurban_order_lines(v_id) where line_no > 1) =
         (public.qurban_setting('care_end')::date - public.qurban_today() + 1), 'jumlah hari ikut pengaturan umum';

  -- validasi
  assert pg_temp.fails($q$select public.qurban_create_orders('X', public.qurban_today(), 'FULL', '[{"cow":"E1","head_price":1000000,"care_price":30000,"buyback_price":0,"care_end":"bukan-tanggal"}]'::jsonb)$q$, '22023'), 'tanggal rusak ditolak';
  assert pg_temp.fails($q$select public.qurban_create_orders('X', public.qurban_today(), 'FULL', '[{"cow":"E2","head_price":1000000,"care_price":30000,"buyback_price":0,"care_end":"2020-01-01"}]'::jsonb)$q$, '22023'), 'akhir sebelum mulai ditolak';
  -- mulai setelah pengaturan umum tetap boleh bila akhir khusus lebih jauh
  v_id := public.qurban_create_orders('Pak Jauh', public.qurban_setting('care_end')::date + 30, 'FULL',
    jsonb_build_array(jsonb_build_object('cow', 'P-03', 'head_price', 12000000, 'care_price', 30000, 'buyback_price', 0, 'care_end', '2028-05-05')));
  assert v_id is not null, 'mulai setelah akhir umum boleh bila care_end khusus lebih jauh';
  assert pg_temp.fails($q$select public.qurban_create_orders('X', public.qurban_setting('care_end')::date + 30, 'FULL', '[{"cow":"E3","head_price":1000000,"care_price":30000,"buyback_price":0}]'::jsonb)$q$, '22023'), 'tanpa care_end khusus tetap ditolak';

  -- tagihan bulanan mengikuti akhir khusus
  reset role;
  select id into v_w from public.qurban_orders where cow_no = 'P-03';
  update public.qurban_orders set pay_mode = 'MONTHLY', status = 'PAID', inv_no = 'INV-929-X-26', inv_date = public.qurban_today(), due_date = public.qurban_today(), paid_at = now() where id = v_w;
  perform pg_temp.u(own);
  perform public.qurban_create_bill(v_w);
  select * into b from public.qurban_bills where order_id = v_w;
  assert b.rate = 30000, 'tagihan bulan pertama memakai tarif tetap';
  reset role;
  v_cnt := 0;
  delete from public.qurban_bills where order_id in (select id from public.qurban_orders where cow_no in ('P-01','P-02','P-03'));
  delete from public.qurban_weighings where order_id in (select id from public.qurban_orders where cow_no in ('P-01','P-02','P-03'));
  delete from public.qurban_orders where cow_no in ('P-01','P-02','P-03');
end $$;
