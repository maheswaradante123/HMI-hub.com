-- Pengujian migrasi 0031: tarif perawatan tetap (care_fixed) pada tagihan bulanan Qurban.
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;
create function pg_temp.fails(p_sql text, p_code text) returns boolean language plpgsql as $$
begin execute p_sql; return false;
exception when others then return sqlstate = p_code; end $$;
do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  mkt constant text := '00000000-0000-0000-0000-000000000002';
  v_fix uuid; v_std uuid; r record;
begin
  -- dua pesanan bulanan lunas, bobot awal 539 Kg (kelas perawatan Rp43.000/hari); satu bertarif tetap Rp50.000
  insert into public.qurban_orders (cow_no, customer_nick, start_date, initial_weight, pay_mode, class_min, class_max, buy_price, care_price, buyback_price, status, inv_no, inv_date, due_date, paid_at)
  values ('#F1', 'Pak Tetap', public.qurban_today(), 539, 'MONTHLY', 350, 599, 55000, 50000, 60000, 'PAID', 'INV-901-X-26', public.qurban_today(), public.qurban_today(), now())
  returning id into v_fix;
  insert into public.qurban_orders (cow_no, customer_nick, start_date, initial_weight, pay_mode, class_min, class_max, buy_price, care_price, buyback_price, status, inv_no, inv_date, due_date, paid_at)
  values ('#F2', 'Pak Biasa', public.qurban_today(), 539, 'MONTHLY', 350, 599, 55000, 43000, 60000, 'PAID', 'INV-902-X-26', public.qurban_today(), public.qurban_today(), now())
  returning id into v_std;
  perform pg_temp.u(own);
  assert (select care_fixed from public.v_qurban_orders where id = v_fix) = false, 'bawaan: tarif mengikuti kelas';

  -- hanya Owner yang boleh mengatur
  perform pg_temp.u(mkt);
  assert pg_temp.fails(format($q$select public.qurban_set_care_fixed(%L, true)$q$, v_fix), '42501'), 'marketing tidak boleh mengatur tarif tetap';
  perform pg_temp.u(own);
  perform public.qurban_set_care_fixed(v_fix, true);
  assert (select care_fixed from public.v_qurban_orders where id = v_fix) = true, 'tarif tetap tersimpan dan tampil di view';

  -- timbangan naik ke kelas 800+ (perawatan kelas Rp63.000): tarif tetap tidak ikut naik
  perform public.qurban_add_weighing(v_fix, public.qurban_today(), 820, 'uji');
  perform public.qurban_add_weighing(v_std, public.qurban_today(), 820, 'uji');
  perform public.qurban_create_bill(v_fix);
  perform public.qurban_create_bill(v_std);
  select * into r from public.qurban_bills where order_id = v_fix;
  assert r.rate = 50000, 'tagihan tarif tetap memakai Rp50.000, dapat ' || r.rate;
  select * into r from public.qurban_bills where order_id = v_std;
  assert r.rate = 63000, 'tagihan biasa memakai tarif kelas timbangan terakhir, dapat ' || r.rate;

  -- tidak bisa untuk pesanan batal
  reset role;
  update public.qurban_orders set status = 'CANCELLED' where id = v_std;
  perform pg_temp.u(own);
  assert pg_temp.fails(format($q$select public.qurban_set_care_fixed(%L, true)$q$, v_std), '55000'), 'pesanan batal ditolak';

  reset role;
  delete from public.qurban_bills where order_id in (v_fix, v_std);
  delete from public.qurban_weighings where order_id in (v_fix, v_std);
  delete from public.qurban_orders where id in (v_fix, v_std);
end $$;
