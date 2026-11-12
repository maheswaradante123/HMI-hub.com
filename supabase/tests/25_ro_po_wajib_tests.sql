-- Pengujian migrasi 0038: RO wajib punya lampiran PO customer.
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;
create function pg_temp.su() returns void language plpgsql as $$ begin reset role; end $$;

do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  v_hotel uuid; v_p uuid; v_ro uuid; v_msg text; v_items jsonb;
begin
  select id into v_hotel from public.customers where code='HOTEL-A';
  select id into v_p from public.products where code='MF-TULANG-SOP';
  v_items := jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_p, 'qty', 2, 'unit_price', 1000)));
  perform pg_temp.u(own);

  -- tanpa lampiran: ditolak
  begin
    perform public.save_doc('RO', null, jsonb_build_object('customer_id', v_hotel), v_items);
    assert false, 'RO tanpa lampiran PO harus ditolak';
  exception when sqlstate '22023' then
    get stacked diagnostics v_msg = message_text;
    assert v_msg like 'Lampiran PO customer wajib%', 'pesan jelas: ' || v_msg;
  end;
  -- lampiran kosong atau spasi: ditolak
  begin
    perform public.save_doc('RO', null, jsonb_build_object('customer_id', v_hotel, 'customer_po_url', '   '), v_items);
    assert false, 'lampiran spasi harus ditolak';
  exception when sqlstate '22023' then null;
  end;
  -- dengan lampiran (nomor PO boleh kosong, mis. screenshot WhatsApp): lolos
  v_ro := public.save_doc('RO', null, jsonb_build_object('customer_id', v_hotel, 'customer_po_url', 'https://drive.google.com/file/d/ABCDEFGHIJK/view'), v_items);
  assert (select customer_po_url from public.request_orders where id = v_ro) like 'https://drive.google.com/%', 'lampiran tersimpan';
  assert (select customer_po_no from public.request_orders where id = v_ro) is null, 'nomor PO boleh kosong';
  perform public.doc_change_status('RO', v_ro, 'CONFIRMED', null);

  -- draf lama tanpa lampiran tidak bisa dikonfirmasi, tapi bisa dibatalkan
  perform pg_temp.su();
  perform set_config('hmi.po_optional', 'on', true);
  insert into public.request_orders (customer_id, status) values (v_hotel, 'DRAFT') returning id into v_ro;
  perform set_config('hmi.po_optional', 'off', true);
  perform pg_temp.u(own);
  begin
    perform public.doc_change_status('RO', v_ro, 'CONFIRMED', null);
    assert false, 'draf lama tanpa PO tidak boleh dikonfirmasi';
  exception when sqlstate '22023' then
    get stacked diagnostics v_msg = message_text;
    assert v_msg like 'RO belum bisa dikonfirmasi%', 'pesan konfirmasi: ' || v_msg;
  end;
  perform public.doc_change_status('RO', v_ro, 'CANCELLED', 'uji dibatalkan');
end $$;
