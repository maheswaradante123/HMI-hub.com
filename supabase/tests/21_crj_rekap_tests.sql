-- Pengujian migrasi 0033: CRJ rekap per periode (nomor mingguan, tarik lima sumber, posting, anti dobel) dan QRIS per bank.
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
  acc constant text := '00000000-0000-0000-0000-000000000004';
  v_cust uuid; v_mandiri uuid; v_bri uuid; v_kas uuid; v_inv uuid; v_ord uuid; v_ord2 uuid; v_bill uuid; v_rep uuid;
  v_j uuid; v_j2 uuid; v_n text; r record; v_cnt integer; v_due numeric;
  v_from date := '2026-04-06'; v_to date := '2026-04-12';
begin
  -- data dasar (sebagai superuser)
  select id into v_cust from public.customers limit 1;
  insert into public.accounts (code, name, type) values ('T-MANDIRI','Bank Mandiri Uji','BANK'), ('T-BRI','Bank BRI Uji','BANK');
  select id into v_mandiri from public.accounts where code = 'T-MANDIRI';
  select id into v_bri from public.accounts where code = 'T-BRI';
  select id into v_kas from public.accounts where code = 'KAS-TOKO';
  insert into public.invoices (customer_id, invoice_date, due_date, total, status) values (v_cust, '2026-03-30', '2026-04-13', 5000000, 'ISSUED') returning id into v_inv;

  insert into public.qurban_orders (cow_no, customer_nick, start_date, initial_weight, pay_mode, class_min, class_max, buy_price, care_price, buyback_price, status, inv_no, inv_date, due_date, paid_at)
  values ('#R1', 'Pak Closing', '2026-04-01', 700, 'FULL', 700, 799, 68000, 58000, 73000, 'PAID', 'INV-R01-IV-26', '2026-04-01', '2026-04-02', '2026-04-08 10:00+07') returning id into v_ord;
  insert into public.qurban_orders (cow_no, customer_nick, start_date, initial_weight, pay_mode, class_min, class_max, buy_price, care_price, buyback_price, status, inv_no, inv_date, due_date)
  values ('#R2', 'Pak Belum', '2026-04-01', 700, 'FULL', 700, 799, 68000, 58000, 73000, 'INVOICE', 'INV-R02-IV-26', '2026-04-01', '2026-04-02') returning id into v_ord2;
  insert into public.qurban_bills (order_id, bill_no, ym, days, rate, basis_weight, bill_date, due_date, status, paid_at)
  values (v_ord, 'INV-R03-IV-26', '2026-05', 31, 58000, 700, '2026-04-07', '2026-04-14', 'PAID', '2026-04-09 09:00+07') returning id into v_bill;

  insert into public.store_income_reports (period_from, period_to, status) values ('2026-04-06', '2026-04-12', 'FINAL') returning id into v_rep;
  insert into public.store_income_lines (report_id, line_no, entry_date, description, qris_mandiri, qris_bri, deposited)
  values (v_rep, 1, '2026-04-07', 'Penjualan', 300000, 200000, 1000000),
         (v_rep, 2, '2026-04-07', 'Penjualan sore', 100000, null, null),
         (v_rep, 3, '2026-04-20', 'Di luar periode', 999, 999, 999);
  assert (select qris from public.store_income_lines where line_no = 1 and report_id = v_rep) = 500000, 'qris = total Mandiri + BRI';
  assert (select qris from public.store_income_lines where line_no = 2 and report_id = v_rep) = 100000, 'qris total tanpa BRI';

  -- Pemasukan Toko lewat save_doc: QRIS Mandiri dan BRI tersimpan dan total qris dihitung otomatis
  perform pg_temp.u(own);
  declare v_p uuid; begin
    v_p := public.save_doc('PMT', null, '{"period_from":"2026-05-04","period_to":"2026-05-10"}'::jsonb,
      '{"lines":[{"entry_date":"2026-05-05","description":"Pemasukan","qris_mandiri":120000,"qris_bri":80000},{"entry_date":"2026-05-06","description":"Lama","qris":70000}]}'::jsonb);
    assert (select qris from public.store_income_lines where report_id = v_p and line_no = 1) = 200000, 'qris = Mandiri + BRI lewat save_doc';
    assert (select qris from public.store_income_lines where report_id = v_p and line_no = 2) = 70000, 'qris lama tanpa pecahan tetap';
    reset role;
    delete from public.store_income_lines where report_id = v_p; delete from public.store_income_reports where id = v_p;
  end;
  -- hanya yang berizin yang boleh menarik
  perform pg_temp.u(mkt);
  assert pg_temp.fails($q$select * from public.crj_pull('QRIS', '2026-04-06', '2026-04-12')$q$, '42501'), 'marketing tidak boleh menarik';
  perform pg_temp.u(acc);

  -- tarik lima sumber
  select count(*), min(amount) into v_cnt, v_due from public.crj_pull('QURBAN_CLOSING', v_from, v_to);
  assert v_cnt = 1, 'closing: hanya pesanan lunas dalam periode, dapat ' || v_cnt;
  assert (select amount from public.crj_pull('QURBAN_CLOSING', v_from, v_to)) = (select due_amount from public.v_qurban_orders where id = v_ord), 'jumlah closing = sisa bayar invoice';
  assert (select amount from public.crj_pull('QURBAN_CARE', v_from, v_to)) = 31 * 58000, 'jumlah pemeliharaan = hari x tarif';
  assert (select count(*) from public.crj_pull('QRIS', v_from, v_to)) = 2, 'QRIS: dua baris (Mandiri dan BRI) per tanggal, di luar periode tidak ikut';
  assert (select amount from public.crj_pull('QRIS', v_from, v_to) where description like '%Mandiri%') = 400000, 'QRIS Mandiri dijumlah per tanggal';
  assert (select account_id from public.crj_pull('QRIS', v_from, v_to) where description like '%Mandiri%') = v_mandiri, 'rekening bawaan Mandiri dari nama';
  assert (select account_id from public.crj_pull('QRIS', v_from, v_to) where description like '%BRI%') = v_bri, 'rekening bawaan BRI dari nama';
  assert (select amount from public.crj_pull('CASH_DEPOSIT', v_from, v_to)) = 1000000, 'setoran cash';
  assert (select amount from public.crj_pull('HOREKA', v_from, v_to) where ref_id = v_inv) = 5000000, 'sisa invoice tempo';

  -- buat jurnal dari hasil tarikan
  v_j := public.save_doc('JCR', null, jsonb_build_object('period_from', v_from, 'period_to', v_to), jsonb_build_object('lines', jsonb_build_array(
    jsonb_build_object('source','QURBAN_CLOSING','trans_date','2026-04-08','description','Closing','account_id',v_bri,'amount',(select due_amount from public.v_qurban_orders where id = v_ord),'qurban_order_id',v_ord),
    jsonb_build_object('source','QURBAN_CARE','trans_date','2026-04-09','description','Pemeliharaan','account_id',v_mandiri,'amount',31*58000,'qurban_bill_id',v_bill),
    jsonb_build_object('source','QRIS','trans_date','2026-04-07','description','QRIS Mandiri','account_id',v_mandiri,'amount',400000,'src_ref', (select src_ref from public.crj_pull('QRIS', v_from, v_to) where description like '%Mandiri%')),
    jsonb_build_object('source','CASH_DEPOSIT','trans_date','2026-04-07','description','Setor','account_id',v_bri,'amount',1000000,'src_ref', (select src_ref from public.crj_pull('CASH_DEPOSIT', v_from, v_to))),
    jsonb_build_object('source','HOREKA','trans_date','2026-04-10','description','Bayar sebagian','account_id',v_mandiri,'amount',2000000,'invoice_id',v_inv))));
  select doc_number into v_n from public.cash_receipt_journals where id = v_j;
  assert v_n = 'CRJ-002-IV-26', 'nomor CRJ mingguan dari akhir periode: ' || v_n;

  -- yang sudah dipakai jurnal lain tidak muncul lagi (QRIS, Qurban); invoice sudah di jurnal DRAFT juga disembunyikan
  assert (select count(*) from public.crj_pull('QURBAN_CLOSING', v_from, v_to)) = 0, 'closing tidak ditarik dua kali';
  assert (select count(*) from public.crj_pull('QRIS', v_from, v_to)) = 1, 'hanya QRIS BRI yang tersisa';
  assert (select count(*) from public.crj_pull('HOREKA', v_from, v_to) where ref_id = v_inv) = 0, 'invoice di jurnal draf tidak ditarik lagi';

  -- jurnal kedua memakai baris yang sama ditolak
  assert pg_temp.fails(format($q$select public.save_doc('JCR', null, %L::jsonb, %L::jsonb)$q$,
      jsonb_build_object('period_from', v_from, 'period_to', v_to)::text,
      jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('source','QURBAN_CLOSING','trans_date','2026-04-08','description','Closing lagi','account_id',v_bri,'amount',100,'qurban_order_id',v_ord)))::text), '23505'),
    'pesanan Qurban yang sama di dua jurnal ditolak';
  -- baris tanpa rujukan sumbernya ditolak
  assert pg_temp.fails(format($q$select public.save_doc('JCR', null, %L::jsonb, %L::jsonb)$q$,
      jsonb_build_object('period_from', v_from, 'period_to', v_to)::text,
      jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('source','HOREKA','trans_date','2026-04-08','description','Tanpa invoice','account_id',v_bri,'amount',100)))::text), '22023'),
    'baris Horeka tanpa invoice ditolak';

  -- nomor kedua pada minggu sama bersama CRJ lama
  v_j2 := public.save_doc('JCR', null, jsonb_build_object('period_from', v_from, 'period_to', '2026-04-09'), jsonb_build_object('lines', jsonb_build_array(
    jsonb_build_object('source','OTHER','trans_date','2026-04-09','description','Penerimaan lain','account_id',v_kas,'amount',50000))));
  assert (select doc_number from public.cash_receipt_journals where id = v_j2) = 'CRJ-002-IV-26-2', 'minggu sama diberi akhiran';
  reset role;
  insert into public.cash_receipts (receipt_date, account_id, payment_method_id, amount)
    select '2026-04-08', v_kas, (select id from public.payment_methods limit 1), 1000 returning doc_number into v_n;
  assert v_n = 'CRJ-002-IV-26-3', 'CRJ lama ikut penghitung bersama: ' || v_n;
  delete from public.cash_receipts where doc_number = v_n;
  perform pg_temp.u(acc);

  -- posting: invoice terbayar sebagian
  perform public.doc_change_status('JCR', v_j, 'POSTED');
  assert (select paid_amount from public.invoices where id = v_inv) = 2000000 and (select status from public.invoices where id = v_inv) = 'PARTIAL', 'invoice sebagian setelah posting';
  assert (select count(*) from public.store_income_invoice_lines('2026-04-01', '2026-04-30') where invoice_id = v_inv) = 1, 'Pemasukan Toko menarik pembayaran dari CRJ baru';
  assert pg_temp.fails(format($q$select public.save_doc('JCR', %L, '{"notes":"x"}'::jsonb, '{}'::jsonb)$q$, v_j), '55000'), 'jurnal terposting tidak bisa diubah';
  assert public.dashboard_summary() ? 'cash_in_month', 'dashboard tetap berjalan dengan CRJ baru';

  assert (select count(*) from public.v_cash_receipt_lines where doc_number = (select doc_number from public.cash_receipt_journals where id = v_j)) = 5, 'laporan kas masuk memuat lima baris';
  assert (select sum(amount) from public.v_cash_receipt_lines where account_name = 'Bank Mandiri Uji') = 400000 + 31 * 58000 + 2000000, 'laporan per rekening';

  -- batal posting mengembalikan invoice
  perform public.doc_change_status('JCR', v_j, 'VOID', 'salah input');
  assert (select paid_amount from public.invoices where id = v_inv) = 0 and (select status from public.invoices where id = v_inv) = 'ISSUED', 'batal posting mengembalikan invoice';
  -- setelah batal, baris Qurban dan QRIS bisa ditarik lagi
  assert (select count(*) from public.crj_pull('QURBAN_CLOSING', v_from, v_to)) = 1, 'setelah batal, closing bisa ditarik lagi';

  -- posting pesanan Qurban yang belum lunas ditolak
  v_j := public.save_doc('JCR', null, jsonb_build_object('period_from', v_from, 'period_to', v_to), jsonb_build_object('lines', jsonb_build_array(
    jsonb_build_object('source','QURBAN_CLOSING','trans_date','2026-04-08','description','Closing belum lunas','account_id',v_bri,'amount',100,'qurban_order_id',v_ord2))));
  assert pg_temp.fails(format($q$select public.doc_change_status('JCR', %L, 'POSTED')$q$, v_j), '22023'), 'Qurban belum lunas tidak bisa diposting';
  -- jurnal kosong tidak bisa diposting
  reset role;
  insert into public.cash_receipt_journals (period_from, period_to) values (v_from, v_to) returning id into v_j;
  perform pg_temp.u(acc);
  assert pg_temp.fails(format($q$select public.doc_change_status('JCR', %L, 'POSTED')$q$, v_j), '22023'), 'jurnal kosong tidak bisa diposting';

  -- bersih-bersih
  reset role;
  delete from public.cash_receipt_lines;
  delete from public.cash_receipt_journals;
  delete from public.store_income_lines where report_id = v_rep;
  delete from public.store_income_reports where id = v_rep;
  delete from public.qurban_bills where id = v_bill;
  delete from public.qurban_orders where id in (v_ord, v_ord2);
  delete from public.invoices where id = v_inv;
end $$;
