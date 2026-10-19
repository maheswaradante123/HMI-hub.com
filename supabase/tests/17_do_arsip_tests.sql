-- Pengujian migrasi 0028: surat jalan arsip tanpa Packing List. Jalankan setelah 01 sampai 16.
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;
create function pg_temp.su() returns void language plpgsql as $$ begin reset role; end $$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlstate; end $$;

do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  v_hotel uuid; v_do uuid;
begin
  select id into v_hotel from public.customers where code='HOTEL-A';

  -- dokumen baru dari aplikasi tetap wajib punya Packing List
  perform pg_temp.u(own);
  assert pg_temp.err(format('select public.save_doc(''DO'', null, jsonb_build_object(''do_date'', current_date), ''{}'')')) is not null, 'DO baru tanpa PL ditolak';
  perform pg_temp.su();
  assert pg_temp.err(format('insert into public.delivery_orders (doc_number, customer_id, do_date) values (''DO-UJI-1'', %L, current_date)', v_hotel)) = '22023', 'insert tanpa PL dan bukan arsip ditolak';

  -- dokumen arsip boleh tanpa PL dan punya daftar barang sendiri
  insert into public.delivery_orders (doc_number, customer_id, do_date, receiver_name, received_on, status, is_legacy)
  values ('DO-UJI-2', v_hotel, current_date, 'Bu Uji', current_date, 'RECEIVED', true) returning id into v_do;
  insert into public.do_legacy_items (do_id, line_no, description, item_type, qty_text) values (v_do, 1, 'Daging Sengkel', 'Daging', '2 kg');
  assert (select count(*) from public.do_legacy_items where do_id = v_do) = 1, 'barang arsip tersimpan';
  assert pg_temp.err(format('update public.delivery_orders set is_legacy = false where id = %L', v_do)) = '22023', 'status arsip tidak bisa diubah';
  assert pg_temp.err(format('update public.delivery_orders set pl_id = gen_random_uuid() where id = %L', v_do)) is not null, 'PL tidak bisa dipasang belakangan';
  assert pg_temp.err(format('insert into public.do_legacy_items (do_id, line_no) values (%L, 1)', v_do)) is not null, 'nomor baris unik';

  -- pengguna biasa bisa melihat tetapi tidak bisa mengubah barang arsip
  perform pg_temp.u(own);
  assert (select count(*) from public.do_legacy_items where do_id = v_do) = 1, 'pengguna berizin melihat barang arsip';
  assert pg_temp.err(format('delete from public.do_legacy_items where do_id = %L', v_do)) is not null, 'pengguna tidak bisa menghapus barang arsip';
end $$;
