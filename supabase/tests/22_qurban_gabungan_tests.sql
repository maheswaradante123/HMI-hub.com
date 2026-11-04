-- Pengujian migrasi 0034: proforma dan invoice gabungan Qurban (beberapa sapi satu nomor, gabung/lepas, nomor unik).
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
  prd constant text := '00000000-0000-0000-0000-000000000005';
  a uuid; b uuid; c uuid; d uuid; e uuid; s uuid; v_pro text; v_inv text; n integer; g uuid;
begin
  perform pg_temp.u(mkt);
  -- tiga sapi dalam satu isian: satu nomor proforma, satu kelompok
  a := public.qurban_create_orders('Pak Gabung', '2026-10-04', 'FULL', '[{"cow":"#G1","weight":827},{"cow":"#G2","weight":700.5},{"cow":"#G3","weight":610}]'::jsonb);
  select pro_no, group_id into v_pro, g from public.qurban_orders where id = a;
  assert g is not null, 'tiga sapi = satu kelompok';
  assert (select count(*) from public.qurban_orders where group_id = g) = 3, 'tiga pesanan dalam kelompok';
  assert (select count(distinct pro_no) from public.qurban_orders where group_id = g) = 1, 'satu nomor proforma';
  assert (select buy_price from public.qurban_orders where group_id = g and cow_no = '#G1') = 75000 and (select buy_price from public.qurban_orders where group_id = g and cow_no = '#G3') = 63000, 'tiap sapi memakai harga kelasnya sendiri';
  assert (select count(*) from public.qurban_weighings w join public.qurban_orders o on o.id = w.order_id where o.group_id = g) = 3, 'timbang awal tiap sapi';

  -- satu sapi: seperti biasa, tanpa kelompok
  s := public.qurban_create_orders('Pak Tunggal', '2026-10-04', 'FULL', '[{"cow":"#S1","weight":700}]'::jsonb);
  assert (select group_id from public.qurban_orders where id = s) is null, 'satu sapi tidak berkelompok';
  assert (select pro_no from public.qurban_orders where id = s) <> v_pro, 'nomor proforma berbeda';

  -- validasi
  assert pg_temp.fails($q$select public.qurban_create_orders('X','2026-10-04','FULL','[{"cow":"#A","weight":700},{"cow":"#a","weight":650}]'::jsonb)$q$, '22023'), 'nomor sapi kembar dalam satu proforma ditolak';
  assert pg_temp.fails($q$select public.qurban_create_orders('X','2026-10-04','FULL','[{"cow":"#A","weight":700},{"cow":"#B","weight":300}]'::jsonb)$q$, '22023'), 'satu bobot di bawah 350 menggagalkan semuanya';
  assert (select count(*) from public.qurban_orders where customer_nick = 'X') = 0, 'tidak ada pesanan setengah jadi';
  assert pg_temp.fails($q$select public.qurban_create_orders('X','2026-10-04','FULL','[]'::jsonb)$q$, '22023'), 'daftar sapi kosong ditolak';
  perform pg_temp.u(prd);
  assert pg_temp.fails($q$select public.qurban_create_orders('X','2026-10-04','FULL','[{"cow":"#A","weight":700}]'::jsonb)$q$, '42501'), 'tanpa izin ditolak';
  perform pg_temp.u(own);

  -- diskon per sapi tetap
  perform public.qurban_set_discount((select id from public.qurban_orders where group_id = g and cow_no = '#G1'), 100000);
  assert (select count(*) from public.qurban_orders where group_id = g and discount > 0) = 1, 'diskon hanya pada sapi yang dinego';

  -- invoice terbit untuk seluruh kelompok dengan satu nomor
  perform pg_temp.u(mkt);
  v_inv := public.qurban_issue_invoice(a);
  assert (select count(distinct inv_no) from public.qurban_orders where group_id = g and status = 'INVOICE') = 1 and (select count(*) from public.qurban_orders where group_id = g and status = 'INVOICE') = 3, 'invoice satu nomor untuk tiga sapi';
  assert (select inv_no from public.qurban_orders where group_id = g limit 1) = v_inv, 'nomor invoice dikembalikan';
  assert pg_temp.fails(format($q$select public.qurban_issue_invoice(%L)$q$, a), '55000'), 'invoice tidak terbit dua kali';
  assert pg_temp.fails(format($q$select public.qurban_ungroup(%L)$q$, a), '55000'), 'tidak bisa dilepas setelah invoice terbit';
  perform public.qurban_mark_paid(a);
  assert (select count(*) from public.qurban_orders where group_id = g and status = 'PAID') = 3, 'lunas berlaku untuk semua sapi';
  assert (select inv_no from public.qurban_orders where id = s) is null, 'pesanan lain tidak ikut';

  -- gabung pesanan proforma pelanggan yang sama pada waktu berbeda
  b := public.qurban_create_order('#M1', 'Bu Gabung', 700, '2026-10-04', 'FULL');
  c := public.qurban_create_order('#M2', 'Bu Gabung', 640, '2026-10-05', 'FULL');
  d := public.qurban_create_order('#M3', 'Bu Gabung', 800, '2026-10-05', 'FULL');
  e := public.qurban_create_order('#M4', 'Orang Lain', 800, '2026-10-05', 'FULL');
  assert pg_temp.fails(format($q$select public.qurban_merge_proforma(%L, array[%L]::uuid[])$q$, b, e), '22023'), 'pelanggan beda ditolak';
  assert pg_temp.fails(format($q$select public.qurban_merge_proforma(%L, '{}'::uuid[])$q$, b), '22023'), 'pilihan kosong ditolak';
  perform public.qurban_merge_proforma(b, array[c]);
  assert (select pro_no from public.qurban_orders where id = c) = (select pro_no from public.qurban_orders where id = b), 'nomor proforma disamakan';
  assert (select group_id from public.qurban_orders where id = c) = (select group_id from public.qurban_orders where id = b), 'satu kelompok';
  perform public.qurban_merge_proforma(b, array[d]);
  assert (select count(*) from public.qurban_orders where group_id = (select group_id from public.qurban_orders where id = b)) = 3, 'sapi ketiga menyusul bergabung';
  assert pg_temp.fails(format($q$select public.qurban_merge_proforma(%L, array[%L]::uuid[])$q$, e, c), '55000'), 'sapi yang sudah tergabung tidak bisa digabung lagi';

  -- lepas satu sapi: dapat nomor sendiri; sisa dua sapi tetap berkelompok, lepas lagi -> kelompok bubar
  assert public.qurban_ungroup(d) like 'PRO-INV-%', 'sapi dilepas mendapat nomor proforma baru';
  assert (select group_id from public.qurban_orders where id = d) is null, 'sapi yang dilepas tidak berkelompok';
  assert (select pro_no from public.qurban_orders where id = d) <> (select pro_no from public.qurban_orders where id = b), 'nomor berbeda setelah dilepas';
  perform public.qurban_ungroup(c);
  assert (select group_id from public.qurban_orders where id = b) is null, 'kelompok bubar bila tinggal satu sapi';

  -- nomor tidak boleh dipakai pesanan lain di luar kelompoknya
  reset role;
  assert pg_temp.fails(format($q$update public.qurban_orders set pro_no = %L where id = %L$q$, v_pro, e), '23505'), 'nomor proforma kelompok lain tidak bisa dipakai';
  assert pg_temp.fails(format($q$update public.qurban_orders set inv_no = %L where id = %L$q$, v_inv, e), '23505'), 'nomor invoice kelompok lain tidak bisa dipakai';

  delete from public.qurban_weighings where order_id in (select id from public.qurban_orders where customer_nick in ('Pak Gabung','Pak Tunggal','Bu Gabung','Orang Lain'));
  delete from public.qurban_orders where customer_nick in ('Pak Gabung','Pak Tunggal','Bu Gabung','Orang Lain');
end $$;
