-- Pengujian migrasi 0027: produk sama boleh di beberapa baris RO/PO, pengemasan baru, satuan baru. Jalankan setelah 01 sampai 15.
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;

create function pg_temp.su() returns void language plpgsql as $$ begin reset role; end $$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlstate; end $$;

do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  v_hotel uuid; v_p uuid; v_ro uuid; v_po uuid;
begin
  select id into v_hotel from public.customers where code='HOTEL-A';
  select id into v_p from public.products where code='MF-TULANG-SOP';
  perform pg_temp.u(own);

  v_ro := public.save_doc('RO', null, jsonb_build_object('customer_id', v_hotel),
    jsonb_build_object('items', jsonb_build_array(
      jsonb_build_object('product_id', v_p, 'qty', 10, 'unit_price', 1000, 'packaging', 'Vacuum 3 Kg', 'notes', 'Kirim: tanggal 1'),
      jsonb_build_object('product_id', v_p, 'qty', 5, 'unit_price', 1000, 'packaging', 'Wrap', 'notes', 'Kirim: tanggal 2'))));
  assert (select count(*) from public.ro_items where ro_id = v_ro and product_id = v_p) = 2, 'produk sama di dua baris RO';
  assert (select total_amount from public.request_orders where id = v_ro) = 15000, 'total RO menjumlah kedua baris';

  v_po := public.save_doc('PROD', null, jsonb_build_object('notes', 'uji'),
    jsonb_build_object('items', jsonb_build_array(
      jsonb_build_object('product_id', v_p, 'qty', 3, 'packaging', 'Wrap + Vacuum 4 Kg'),
      jsonb_build_object('product_id', v_p, 'qty', 4, 'packaging', 'Wrap'))));
  assert (select count(*) from public.po_items where po_id = v_po) = 2, 'produk sama di dua baris PO';

  perform pg_temp.su();
  assert pg_temp.err(format('insert into public.ro_items (ro_id, line_no, product_id, qty, packaging) values (%L, 9, %L, 1, ''Karton'')', v_ro, v_p)) is not null, 'pengemasan di luar daftar ditolak';
  assert (select count(*) from public.units where code in ('EKOR','LS')) = 2, 'satuan Ekor dan Lumpsum ada';
end $$;
