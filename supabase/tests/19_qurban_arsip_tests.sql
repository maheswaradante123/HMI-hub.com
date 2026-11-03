-- Pengujian migrasi 0030: pesanan arsip Qurban (nomor boleh sama, penanda arsip tetap, tampilan memuat kolom baru).
\set ON_ERROR_STOP on
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlstate; end $$;
do $$
declare v_a uuid; v_b uuid; v_c uuid; v_n integer;
begin
  -- dua pesanan arsip boleh memakai nomor invoice dan bill yang sama
  insert into public.qurban_orders (cow_no, customer_nick, start_date, initial_weight, pay_mode, class_min, buy_price, care_price, buyback_price,
         status, inv_no, is_legacy, sp_jb_no, sp_pl_no)
  values ('#T1', 'Pak Arsip', '2026-06-07', 700, 'FULL', 700, 55000, 55000, 73000, 'PAID', 'INV-004-VI-26', true, 'SP-JB-001-VI-AMF-26', 'SP-PL-001-VI-AMF-26') returning id into v_a;
  insert into public.qurban_orders (cow_no, customer_nick, start_date, initial_weight, pay_mode, class_min, buy_price, care_price, buyback_price,
         status, inv_no, is_legacy)
  values ('#T2', 'Pak Arsip', '2026-06-07', 650, 'FULL', 600, 50000, 50000, 68000, 'PAID', 'INV-004-VI-26', true) returning id into v_b;
  insert into public.qurban_bills (order_id, bill_no, ym, days, rate, basis_weight, bill_date, due_date, status, is_legacy)
  values (v_a, 'INV-016-VI-26', '2026-07', 31, 55000, 700, '2026-07-01', '2026-07-08', 'PAID', true),
         (v_b, 'INV-016-VI-26', '2026-07', 31, 50000, 650, '2026-07-01', '2026-07-08', 'PAID', true);
  assert (select count(*) from public.v_qurban_orders where inv_no = 'INV-004-VI-26' and is_legacy) = 2, 'nomor arsip sama boleh, tampilan memuat is_legacy';
  assert (select sp_jb_no from public.v_qurban_orders where id = v_a) = 'SP-JB-001-VI-AMF-26', 'nomor kontrak arsip tampil';

  -- dokumen buatan aplikasi tetap unik dan tidak boleh memakai nomor yang sama dengan sesama non-arsip
  insert into public.qurban_orders (cow_no, customer_nick, start_date, initial_weight, pay_mode, class_min, buy_price, care_price, buyback_price, status, inv_no)
  values ('#T3', 'Baru', '2026-10-04', 700, 'FULL', 700, 68000, 58000, 73000, 'INVOICE', 'INV-777-X-26') returning id into v_c;
  assert pg_temp.err($q$insert into public.qurban_orders (cow_no, customer_nick, start_date, initial_weight, pay_mode, class_min, buy_price, care_price, buyback_price, status, inv_no)
    values ('#T4','Baru',  '2026-10-04', 700, 'FULL', 700, 68000, 58000, 73000, 'INVOICE', 'INV-777-X-26')$q$) = '23505', 'nomor non-arsip tetap unik';

  -- penanda arsip tidak bisa dilepas
  assert pg_temp.err(format('update public.qurban_orders set is_legacy = false where id = %L', v_a)) = '22023', 'penanda arsip tetap';

  -- urutan nomor bisa dilanjutkan dari nomor sheet
  insert into public.qurban_sequences (kind, ym, last_number) values ('INV', '2026-10', 12)
    on conflict (kind, ym) do update set last_number = greatest(public.qurban_sequences.last_number, excluded.last_number);
  assert public.qurban_next('INV', '2026-10-20') = 13, 'nomor baru melanjutkan nomor sheet';
  delete from public.qurban_bills where order_id in (v_a, v_b);
  delete from public.qurban_orders where id in (v_a, v_b, v_c);
end $$;
