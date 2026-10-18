-- Pengujian Phase 13-15: Invoice, CRJ, CPJ, Gaji.
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;
create function pg_temp.su() returns void language plpgsql as $$ begin reset role; end $$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlstate; end $$;

do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  mkt constant text := '00000000-0000-0000-0000-000000000002';
  pur constant text := '00000000-0000-0000-0000-000000000003';
  acc constant text := '00000000-0000-0000-0000-000000000004';
  prd constant text := '00000000-0000-0000-0000-000000000005';
  v_hotel uuid; v_jagal uuid; v_top uuid; v_sk uuid; v_wh uuid; v_pl uuid; v_pl2 uuid; v_inv uuid; v_inv2 uuid;
  v_kas uuid; v_kopra uuid; v_crj1 uuid; v_crj2 uuid; v_crj3 uuid; v_ncs uuid; v_pr uuid; v_cpj uuid; v_cpj2 uuid; v_sal uuid;
  v_cost uuid; v_sup uuid; r record; v_st text; v_n numeric; v_cnt int;
begin
  select id into v_hotel from public.customers where code='HOTEL-A';
  select id into v_jagal from public.customers where code='JAGAL-A';
  select id into v_top from public.products where code='MF-TOPSIDE';
  select id into v_sk from public.products where code='MF-SENGKEL';
  select id into v_wh from public.warehouses where code='GD-TOKO';
  select id into v_kas from public.accounts where code='KAS-TOKO';
  select id into v_kopra from public.payment_methods where code='KOPRA';
  select id into v_cost from public.cost_types where code='TRANSPORT';
  select id into v_sup from public.suppliers where code='SUP-SAPI-A';
  select id into v_pl from public.packing_lists where status='DELIVERED' and customer_id = v_hotel limit 1;
  select id into v_ncs from public.noncarcass_sales where status='CONFIRMED' limit 1;

  -- pajak
  perform pg_temp.u(mkt);
  assert pg_temp.err('select public.set_tax_rate(''PPN'', 11)') = '42501', 'marketing tidak boleh ubah pajak';
  perform pg_temp.u(acc);
  assert pg_temp.err('select public.set_tax_rate(''PPN'', 150)') = '22023', 'tarif di atas 100';
  perform public.set_tax_rate('PPN', 11);
  -- uang muka dihitung sebagai pembayaran saat terbit
  declare v_dp uuid; v_dp2 uuid;
  begin
    v_dp := public.save_doc('INV', null, jsonb_build_object('customer_id', v_hotel, 'down_payment', 50000, 'delivery_note_no', 'DO-X-001', 'signer', 'Budi', 'use_signature', 'true'),
       jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'qty', 1, 'unit_price', 100000, 'description', 'Daging khusus'))));
    perform public.doc_change_status('INV', v_dp, 'ISSUED');
    assert (select paid_amount from public.invoices where id = v_dp) = 50000 and (select status from public.invoices where id = v_dp) = 'PARTIAL', 'uang muka jadi pembayaran';
    perform public.doc_change_status('INV', v_dp, 'VOID', 'batal');
    v_dp2 := public.save_doc('INV', null, jsonb_build_object('customer_id', v_hotel, 'down_payment', 999999999),
       jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'qty', 1, 'unit_price', 100000))));
    assert pg_temp.err(format('select public.doc_change_status(''INV'',%L,''ISSUED'')', v_dp2)) = '22023', 'uang muka melebihi total ditolak';
    assert public.inv_next_number(current_date) ~ '^INV-[0-9]{3}-[IVX]+-[0-9]{2}$', 'pratinjau nomor';
  end;

  -- invoice
  perform pg_temp.u(own);
  v_pl2 := public.save_doc('PL', null, jsonb_build_object('customer_id', v_hotel, 'warehouse_id', v_wh), jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'qty', 1))));
  perform pg_temp.u(acc);
  assert pg_temp.err(format('select public.save_doc(''INV'',null,jsonb_build_object(''customer_id'',%L,''pl_id'',%L),''{}'')', v_hotel, v_pl2)) = '22023', 'PL draf tidak bisa ditagih';
  v_inv := public.save_doc('INV', null, jsonb_build_object('customer_id', v_hotel, 'pl_id', v_pl),
     jsonb_build_object('items', jsonb_build_array(
        jsonb_build_object('product_id', v_top, 'qty', 12.5, 'unit_price', 0),
        jsonb_build_object('product_id', v_sk, 'qty', 4, 'unit_price', 90000))));
  select * into r from public.invoices where id = v_inv;
  assert r.doc_number ~ '^INV-[0-9]{3}-[IVX]+-[0-9]{2}$', 'nomor INV: ' || r.doc_number;
  assert r.due_date = r.invoice_date + 14, 'jatuh tempo mengikuti termin customer';
  assert r.subtotal = 2047500 and r.tax_rate = 11 and r.tax_amount = 225225 and r.total = 2272725, 'total invoice, dapat ' || r.total;
  assert pg_temp.err(format('select public.save_doc(''INV'',null,jsonb_build_object(''customer_id'',%L,''pl_id'',%L),''{}'')', v_hotel, v_pl)) = '23505', 'satu invoice aktif per PL';
  perform public.doc_change_status('INV', v_inv, 'ISSUED');
  assert pg_temp.err(format('select public.save_doc(''INV'',%L,''{"notes":"x"}'')', v_inv)) = '55000', 'invoice terbit terkunci';
  -- perubahan tarif pajak tidak mengubah invoice yang sudah terbit
  perform public.set_tax_rate('PPN', 12);
  assert (select total from public.invoices where id = v_inv) = 2272725, 'invoice terbit tidak berubah';
  perform public.set_tax_rate('PPN', 11);

  -- CRJ bertahap
  v_crj1 := public.save_doc('CRJ', null, jsonb_build_object('customer_id', v_hotel, 'account_id', v_kas, 'payment_method_id', v_kopra, 'amount', 1000000),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('invoice_id', v_inv, 'amount', 1000000))));
  assert (select doc_number from public.cash_receipts where id = v_crj1) ~ '^CRJ-[0-9]{4}-[0-9]{4}$', 'nomor CRJ';
  perform public.doc_change_status('CRJ', v_crj1, 'POSTED');
  select status, paid_amount into v_st, v_n from public.invoices where id = v_inv;
  assert v_st = 'PARTIAL' and v_n = 1000000, 'invoice sebagian';
  select outstanding into v_n from public.v_receivables where id = v_inv; assert v_n = 1272725, 'sisa piutang';
  v_crj2 := public.save_doc('CRJ', null, jsonb_build_object('customer_id', v_hotel, 'account_id', v_kas, 'payment_method_id', v_kopra, 'amount', 2000000),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('invoice_id', v_inv, 'amount', 2000000))));
  assert pg_temp.err(format('select public.doc_change_status(''CRJ'',%L,''POSTED'')', v_crj2)) = '22023', 'tidak boleh lebih bayar';
  assert (select status from public.cash_receipts where id = v_crj2) = 'DRAFT', 'CRJ gagal tetap draf';
  perform public.save_doc('CRJ', v_crj2, jsonb_build_object('customer_id', v_hotel, 'account_id', v_kas, 'payment_method_id', v_kopra, 'amount', 1272725),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('invoice_id', v_inv, 'amount', 1272725))));
  perform public.doc_change_status('CRJ', v_crj2, 'POSTED');
  assert (select status from public.invoices where id = v_inv) = 'PAID', 'invoice lunas';
  assert pg_temp.err(format('select public.doc_change_status(''INV'',%L,''VOID'',''x'')', v_inv)) = '55000', 'invoice lunas tidak bisa void';
  perform public.doc_change_status('CRJ', v_crj2, 'VOID', 'salah input');
  assert (select status from public.invoices where id = v_inv) = 'PARTIAL', 'kembali sebagian setelah void CRJ';
  -- alokasi melebihi jumlah CRJ
  v_crj3 := public.save_doc('CRJ', null, jsonb_build_object('customer_id', v_hotel, 'account_id', v_kas, 'payment_method_id', v_kopra, 'amount', 100),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('invoice_id', v_inv, 'amount', 500))));
  assert pg_temp.err(format('select public.doc_change_status(''CRJ'',%L,''POSTED'')', v_crj3)) = '22023', 'alokasi > jumlah';
  -- customer salah
  perform public.save_doc('CRJ', v_crj3, jsonb_build_object('customer_id', v_jagal, 'account_id', v_kas, 'payment_method_id', v_kopra, 'amount', 500),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('invoice_id', v_inv, 'amount', 500))));
  assert pg_temp.err(format('select public.doc_change_status(''CRJ'',%L,''POSTED'')', v_crj3)) = '22023', 'invoice customer lain';

  -- CRJ untuk penjualan non-karkas
  v_crj3 := public.save_doc('CRJ', null, jsonb_build_object('customer_id', v_jagal, 'account_id', v_kas, 'payment_method_id', v_kopra, 'amount', 1200000),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('ncs_id', v_ncs, 'amount', 1200000))));
  perform public.doc_change_status('CRJ', v_crj3, 'POSTED');
  assert (select status from public.noncarcass_sales where id = v_ncs) = 'PAID', 'non-karkas lunas';
  perform public.doc_change_status('CRJ', v_crj3, 'VOID', 'batal');
  assert (select status from public.noncarcass_sales where id = v_ncs) = 'CONFIRMED', 'non-karkas kembali';

  -- CPJ untuk PR
  perform pg_temp.su();
  insert into public.purchase_requests (requester_id, reason, status) values (own::uuid, 'beli pisau', 'DRAFT') returning id into v_pr;
  perform pg_temp.u(acc);
  v_cpj := public.save_doc('CPJ', null, jsonb_build_object('pr_id', v_pr, 'supplier_id', v_sup, 'cost_type_id', v_cost, 'account_id', v_kas, 'payment_method_id', v_kopra, 'amount', 350000), '{}');
  assert (select kind from public.cash_payments where id = v_cpj) = 'PR', 'kind otomatis PR';
  assert pg_temp.err(format('select public.doc_change_status(''CPJ'',%L,''POSTED'')', v_cpj)) = '22023', 'PR belum diterima';
  perform pg_temp.su();
  update public.purchase_requests set status = 'RECEIVED' where id = v_pr;
  perform pg_temp.u(acc);
  perform public.doc_change_status('CPJ', v_cpj, 'POSTED');
  assert (select status from public.purchase_requests where id = v_pr) = 'PAID', 'PR menjadi PAID';
  perform public.doc_change_status('CPJ', v_cpj, 'VOID', 'salah rekening');
  assert (select status from public.purchase_requests where id = v_pr) = 'RECEIVED', 'PR kembali RECEIVED';
  v_cpj2 := public.save_doc('CPJ', null, jsonb_build_object('pr_id', v_pr, 'cost_type_id', v_cost, 'account_id', v_kas, 'payment_method_id', v_kopra, 'amount', 350000), '{}');
  perform public.doc_change_status('CPJ', v_cpj2, 'POSTED');
  assert pg_temp.err(format('select public.pr_close(%L)', v_pr::text)) is null, 'tutup PR';
  assert (select status from public.purchase_requests where id = v_pr) = 'CLOSED', 'PR CLOSED';
  assert pg_temp.err(format('select public.doc_change_status(''CPJ'',%L,''VOID'',''x'')', v_cpj2)) = '55000', 'PR ditutup menghalangi void';
  assert (select count(*) from public.pr_status_history where pr_id = v_pr) = 4, 'riwayat PR: PAID, RECEIVED, PAID, CLOSED';
  perform pg_temp.u(mkt);
  assert pg_temp.err(format('select public.pr_close(%L)', v_pr::text)) = '42501', 'marketing tidak boleh tutup PR';

  -- Gaji
  perform pg_temp.u(acc);
  assert pg_temp.err(format('select public.save_doc(''SAL'',null,jsonb_build_object(''cost_type_id'',%L,''account_id'',%L,''payment_method_id'',%L,''amount'',100),''{}'')', v_cost, v_kas, v_kopra)) = '23514', 'gaji wajib nama penerima';
  v_sal := public.save_doc('SAL', null, jsonb_build_object('cost_type_id', (select id from public.cost_types where code='GAJI'), 'account_id', v_kas, 'payment_method_id', v_kopra, 'payee_name', 'Budi', 'amount', 3500000), '{}');
  assert (select kind from public.cash_payments where id = v_sal) = 'SALARY', 'kind SALARY';
  -- kind tidak bisa dipalsukan lewat CPJ
  v_cpj := public.save_doc('CPJ', null, jsonb_build_object('kind', 'SALARY', 'cost_type_id', v_cost, 'account_id', v_kas, 'payment_method_id', v_kopra, 'amount', 5), '{}');
  assert (select kind from public.cash_payments where id = v_cpj) = 'GENERAL', 'CPJ tidak bisa membuat gaji';
  perform pg_temp.u(pur);
  select count(*) into v_cnt from public.cash_payments where kind = 'SALARY'; assert v_cnt = 0, 'purchasing tidak melihat gaji';
  select count(*) into v_cnt from public.cash_payments where kind <> 'SALARY'; assert v_cnt >= 1, 'purchasing melihat CPJ';
  assert pg_temp.err(format('select public.doc_change_status(''SAL'',%L,''POSTED'')', v_sal)) is not null, 'purchasing tidak boleh posting gaji';
  perform pg_temp.u(prd);
  select count(*) into v_cnt from public.invoices; assert v_cnt = 0, 'produksi tidak melihat invoice';
  select count(*) into v_cnt from public.cash_receipts; assert v_cnt = 0, 'produksi tidak melihat CRJ';
  raise notice 'SEMUA PENGUJIAN PHASE 13-15 LULUS';
end $$;
