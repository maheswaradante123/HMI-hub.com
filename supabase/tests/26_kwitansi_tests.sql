-- Pengujian migrasi 0039: kwitansi gabungan.
\set ON_ERROR_STOP on
select set_config('hmi.po_optional', 'on', false);
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;
create function pg_temp.su() returns void language plpgsql as $$ begin reset role; end $$;

do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  v_a uuid; v_b uuid; v_i1 uuid; v_i2 uuid; v_i3 uuid; v_i4 uuid; v_kw uuid; v_kw2 uuid; v_msg text;
begin
  select id into v_a from public.customers where code = 'HOTEL-A';
  select id into v_b from public.customers where code <> 'HOTEL-A' and is_active limit 1;
  insert into public.invoices (customer_id, invoice_date, status, subtotal, total, doc_number) values (v_a, '2026-11-02', 'ISSUED', 1000, 1000, 'INV-T01-XI-26') returning id into v_i1;
  insert into public.invoices (customer_id, invoice_date, status, subtotal, total, doc_number) values (v_a, '2026-11-03', 'ISSUED', 2500, 2500, 'INV-T02-XI-26') returning id into v_i2;
  insert into public.invoices (customer_id, invoice_date, status, subtotal, total, paid_amount, doc_number) values (v_a, '2026-11-04', 'PAID', 700, 700, 700, 'INV-T03-XI-26') returning id into v_i3;
  insert into public.invoices (customer_id, invoice_date, status, subtotal, total, doc_number) values (v_b, '2026-11-05', 'ISSUED', 300, 300, 'INV-T04-XI-26') returning id into v_i4;
  perform pg_temp.u(own);

  v_kw := public.save_doc('KW', null, jsonb_build_object('customer_id', v_a, 'receipt_date', '2026-11-12'),
    jsonb_build_object('items', jsonb_build_array(jsonb_build_object('invoice_id', v_i1), jsonb_build_object('invoice_id', v_i2))));
  assert (select doc_number from public.kwitansi where id = v_kw) ~ '^KW-001-XI-26$', 'nomor KW pertama bulan ini: ' || (select doc_number from public.kwitansi where id = v_kw);
  assert (select amount from public.kwitansi where id = v_kw) = 3500, 'jumlah = total sisa kedua invoice';

  -- invoice sudah ada di kwitansi aktif lain
  begin
    perform public.save_doc('KW', null, jsonb_build_object('customer_id', v_a, 'receipt_date', '2026-11-12'),
      jsonb_build_object('items', jsonb_build_array(jsonb_build_object('invoice_id', v_i1))));
    assert false, 'invoice ganda harus ditolak';
  exception when sqlstate '23505' then null; end;
  -- invoice milik customer lain
  begin
    perform public.save_doc('KW', null, jsonb_build_object('customer_id', v_a, 'receipt_date', '2026-11-12'),
      jsonb_build_object('items', jsonb_build_array(jsonb_build_object('invoice_id', v_i4))));
    assert false, 'invoice customer lain harus ditolak';
  exception when sqlstate '22023' then null; end;
  -- invoice sudah lunas
  begin
    perform public.save_doc('KW', null, jsonb_build_object('customer_id', v_a, 'receipt_date', '2026-11-12'),
      jsonb_build_object('items', jsonb_build_array(jsonb_build_object('invoice_id', v_i3))));
    assert false, 'invoice lunas harus ditolak';
  exception when sqlstate '22023' then null; end;
  -- tanpa invoice
  begin
    perform public.save_doc('KW', null, jsonb_build_object('customer_id', v_a, 'receipt_date', '2026-11-12'), jsonb_build_object('items', '[]'::jsonb));
    assert false, 'tanpa invoice harus ditolak';
  exception when sqlstate '22023' then null; end;

  -- terbitkan; kwitansi terbit tidak bisa diubah; batal melepas invoice untuk kwitansi lain
  perform public.doc_change_status('KW', v_kw, 'ISSUED', null);
  begin
    perform public.save_doc('KW', v_kw, jsonb_build_object('customer_id', v_a), jsonb_build_object('items', jsonb_build_array(jsonb_build_object('invoice_id', v_i1))));
    assert false, 'kwitansi terbit tidak boleh diubah';
  exception when sqlstate '55000' then null; end;
  perform public.doc_change_status('KW', v_kw, 'VOID', 'salah customer');
  v_kw2 := public.save_doc('KW', null, jsonb_build_object('customer_id', v_a, 'receipt_date', '2026-11-20'),
    jsonb_build_object('items', jsonb_build_array(jsonb_build_object('invoice_id', v_i1))));
  assert (select doc_number from public.kwitansi where id = v_kw2) = 'KW-002-XI-26', 'urut kedua: ' || (select doc_number from public.kwitansi where id = v_kw2);
  assert (select amount from public.kwitansi where id = v_kw2) = 1000, 'jumlah kwitansi kedua';
end $$;
