-- Pengujian migrasi 0035: Debit dipecah per bank, dan CRJ pertokoan menarik QRIS, Debit, TF Rek HMI, dan Disetor dari Pemasukan Toko.
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;
create function pg_temp.fails(p_sql text, p_code text) returns boolean language plpgsql as $$
begin execute p_sql; return false;
exception when others then return sqlstate = p_code; end $$;
do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  acc constant text := '00000000-0000-0000-0000-000000000004';
  v_mandiri uuid; v_bri uuid; v_cust uuid; v_inv uuid; v_p uuid; v_j uuid; v_from date := '2026-06-01'; v_to date := '2026-06-07';
  v_cnt integer;
begin
  select id into v_cust from public.customers limit 1;
  insert into public.accounts (code, name, type) values ('T2-MANDIRI','Bank Mandiri Uji 2','BANK'), ('T2-BRI','Bank BRI Uji 2','BANK');
  select id into v_mandiri from public.accounts where code = 'T2-MANDIRI';
  select id into v_bri from public.accounts where code = 'T2-BRI';
  insert into public.invoices (customer_id, invoice_date, due_date, total, status) values (v_cust, '2026-06-01', '2026-06-10', 100000, 'ISSUED') returning id into v_inv;

  -- Pemasukan Toko lewat save_doc: Debit Mandiri + BRI menjadi total debit; baris lama tanpa pecahan tetap
  perform pg_temp.u(own);
  v_p := public.save_doc('PMT', null, '{"period_from":"2026-06-01","period_to":"2026-06-07"}'::jsonb,
    jsonb_build_object('lines', jsonb_build_array(
      jsonb_build_object('entry_date','2026-06-02','description','Penjualan','cash',500000,'qris_mandiri',100000,'qris_bri',50000,'debit_mandiri',70000,'debit_bri',30000,'tf',200000,'deposited',400000),
      jsonb_build_object('entry_date','2026-06-02','description','Sore','debit_mandiri',10000),
      jsonb_build_object('entry_date','2026-06-03','description','Lama','debit',90000),
      jsonb_build_object('entry_date','2026-06-03','description','Pemasukan INV','tf',100000,'invoice_id',v_inv)
    )));
  assert (select debit from public.store_income_lines where report_id = v_p and line_no = 1) = 100000, 'debit = Mandiri + BRI';
  assert (select debit from public.store_income_lines where report_id = v_p and line_no = 2) = 10000, 'debit hanya Mandiri';
  assert (select debit from public.store_income_lines where report_id = v_p and line_no = 3) = 90000, 'debit lama tanpa pecahan tetap';
  reset role;
  assert (select count(*) from information_schema.columns where table_name = 'store_income_lines' and column_name = 'grab') = 1, 'kolom grab tetap ada untuk data lama';
  update public.store_income_reports set status = 'FINAL' where id = v_p;

  -- CRJ menarik semua kolom bank dari Pemasukan Toko
  perform pg_temp.u(acc);
  assert (select amount from public.crj_pull('DEBIT', v_from, v_to) where description like '%Mandiri%') = 80000, 'debit Mandiri dijumlah per tanggal';
  assert (select amount from public.crj_pull('DEBIT', v_from, v_to) where description like '%BRI%') = 30000, 'debit BRI';
  assert (select count(*) from public.crj_pull('DEBIT', v_from, v_to)) = 2, 'debit lama tanpa pecahan tidak ditarik';
  assert (select amount from public.crj_pull('TF', v_from, v_to)) = 200000, 'TF hanya baris tanpa invoice';
  assert (select count(*) from public.crj_pull('TF', v_from, v_to)) = 1, 'baris pembayaran invoice tidak ikut TF';
  assert (select amount from public.crj_pull('QRIS', v_from, v_to) where description like '%Mandiri%') = 100000, 'QRIS tetap bisa ditarik';
  assert (select amount from public.crj_pull('CASH_DEPOSIT', v_from, v_to)) = 400000, 'setoran tetap bisa ditarik';

  -- simpan jurnal dari tarikan, sumber baru tidak bisa tanpa rujukan
  v_j := public.save_doc('JCR', null, jsonb_build_object('period_from', v_from, 'period_to', v_to), jsonb_build_object('lines', jsonb_build_array(
    jsonb_build_object('source','DEBIT','trans_date','2026-06-02','description','Debit Mandiri','account_id',v_mandiri,'amount',80000,'src_ref',(select src_ref from public.crj_pull('DEBIT', v_from, v_to) where description like '%Mandiri%')),
    jsonb_build_object('source','TF','trans_date','2026-06-02','description','Transfer','account_id',v_bri,'amount',200000,'src_ref',(select src_ref from public.crj_pull('TF', v_from, v_to))))));
  assert (select count(*) from public.crj_pull('DEBIT', v_from, v_to)) = 1, 'debit yang sudah di jurnal tidak ditarik lagi';
  assert (select count(*) from public.crj_pull('TF', v_from, v_to)) = 0, 'TF yang sudah di jurnal tidak ditarik lagi';
  assert pg_temp.fails(format($q$select public.save_doc('JCR', null, %L::jsonb, %L::jsonb)$q$,
      jsonb_build_object('period_from', v_from, 'period_to', v_to)::text,
      jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('source','TF','trans_date','2026-06-02','description','Tanpa rujukan','account_id',v_bri,'amount',1)))::text), '22023'),
    'baris TF tanpa rujukan ditolak';
  perform public.doc_change_status('JCR', v_j, 'POSTED');
  assert (select sum(amount) from public.v_cash_receipt_lines where source_label in ('Debit toko','Transfer toko')) = 280000, 'laporan kas masuk memuat debit dan transfer toko';

  reset role;
  delete from public.cash_receipt_lines; delete from public.cash_receipt_journals;
  delete from public.store_income_lines where report_id = v_p; delete from public.store_income_reports where id = v_p;
  delete from public.invoices where id = v_inv;
end $$;
