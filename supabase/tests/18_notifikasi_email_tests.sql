-- Pengujian migrasi 0029: notifikasi email mengikuti izin, tanpa pengirim sendiri, opt-out, override, kotak keluar.
-- Jalankan setelah 01 sampai 17.
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;
create function pg_temp.su() returns void language plpgsql as $$ begin reset role; end $$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlstate; end $$;
-- penerima email untuk satu dokumen dan status, urut dan digabung
create function pg_temp.rcpt(p_doc uuid, p_status text) returns text language sql as $$
  select coalesce(string_agg(split_part(to_email, '@', 1), ',' order by to_email), '-')
    from public.notification_outbox where doc_id = p_doc and to_status = p_status $$;

do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  mkt constant text := '00000000-0000-0000-0000-000000000002';
  pur constant text := '00000000-0000-0000-0000-000000000003';
  prd constant text := '00000000-0000-0000-0000-000000000005';
  v_hotel uuid; v_top uuid; v_ro uuid; v_po uuid; v_n integer; v_id bigint; r record;
begin
  select id into v_hotel from public.customers where code='HOTEL-A';
  select id into v_top from public.products where code='MF-TOPSIDE';
  delete from public.user_permission_overrides;
  delete from public.notification_outbox;   -- email dari tes sebelumnya

  -- Marketing membuat RO: dokumen baru (DRAFT) tidak mengirim apa pun
  perform pg_temp.u(mkt);
  v_ro := public.save_doc('RO', null, jsonb_build_object('customer_id', v_hotel, 'delivery_date', current_date + 2),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'qty', 5, 'unit_price', 0))));
  perform pg_temp.su();
  assert (select count(*) from public.notification_outbox) = 0, 'dokumen baru tidak memicu email';

  -- RO dikonfirmasi: penerima = yang boleh membuat Production Order, kecuali pengirimnya (Marketing)
  perform pg_temp.u(mkt);
  perform public.doc_change_status('RO', v_ro, 'CONFIRMED');
  perform pg_temp.su();
  assert pg_temp.rcpt(v_ro, 'CONFIRMED') = 'owner', 'RO dikonfirmasi: hanya owner (pengirim dan yang tak berizin tidak): ' || pg_temp.rcpt(v_ro, 'CONFIRMED');
  select * into r from public.notification_outbox where doc_id = v_ro;
  assert r.subject like 'RO baru dikonfirmasi: RO-%', 'subjek memuat nomor: ' || r.subject;
  assert r.message like '%Customer:%' and r.message like '%Buat Production Order%', 'isi memuat customer dan tindakan';
  assert r.actor_id = mkt::uuid and r.status = 'pending', 'dicatat atas nama pemicu';

  -- Production Order diajukan: hanya yang boleh menyetujui (owner)
  perform pg_temp.u(mkt);
  v_po := public.save_doc('PROD', null, jsonb_build_object('ro_id', v_ro, 'needed_date', current_date + 1),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'qty', 5))));
  perform public.doc_change_status('PROD', v_po, 'SUBMITTED');
  perform pg_temp.su();
  assert pg_temp.rcpt(v_po, 'SUBMITTED') = 'owner', 'PO diajukan ke owner: ' || pg_temp.rcpt(v_po, 'SUBMITTED');

  -- Override izin: Purchasing diberi izin menyetujui PO, jadi ikut menerima
  insert into public.user_permission_overrides (user_id, permission_id, is_granted)
  select pur::uuid, id, true from public.permissions where module = 'production_order' and action = 'approve';
  perform pg_temp.u(mkt);
  perform public.doc_change_status('PROD', v_po, 'CANCELLED', 'uji');   -- batal: tidak ada aturan, tidak ada email
  perform pg_temp.su();
  assert pg_temp.rcpt(v_po, 'CANCELLED') = '-', 'status tanpa aturan tidak mengirim';
  perform pg_temp.u(mkt);
  v_po := public.save_doc('PROD', null, jsonb_build_object('ro_id', v_ro, 'needed_date', current_date + 1),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'qty', 5))));
  perform public.doc_change_status('PROD', v_po, 'SUBMITTED');
  perform pg_temp.su();
  assert pg_temp.rcpt(v_po, 'SUBMITTED') = 'owner,purchasing', 'override izin ikut menerima: ' || pg_temp.rcpt(v_po, 'SUBMITTED');

  -- Izin dicabut lewat override: tidak menerima
  update public.user_permission_overrides set is_granted = false where user_id = pur::uuid;
  perform pg_temp.u(prd);
  perform pg_temp.su();
  update public.notification_outbox set status = 'sent';   -- bersihkan antrean sebelumnya
  perform pg_temp.u(mkt);
  perform public.doc_change_status('PROD', v_po, 'CANCELLED', 'uji 2');
  perform pg_temp.su();

  -- Opt-out: owner mematikan email, user lain tidak bisa mematikan milik orang lain
  perform pg_temp.u(own);
  perform public.set_my_email_notif(false);
  assert (select email_enabled from public.notification_prefs where user_id = own::uuid) = false, 'pilihan tersimpan';
  assert (select count(*) from public.notification_prefs) = 1, 'user hanya melihat pilihannya sendiri';
  perform pg_temp.u(mkt);
  assert (select count(*) from public.notification_prefs) = 0, 'pilihan orang lain tidak terlihat';
  v_po := public.save_doc('PROD', null, jsonb_build_object('ro_id', v_ro, 'needed_date', current_date + 1),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'qty', 5))));
  perform public.doc_change_status('PROD', v_po, 'SUBMITTED');
  perform pg_temp.su();
  assert pg_temp.rcpt(v_po, 'SUBMITTED') = '-', 'owner yang opt-out tidak menerima, penerima lain tidak ada: ' || pg_temp.rcpt(v_po, 'SUBMITTED');
  perform pg_temp.u(own);
  perform public.set_my_email_notif(true);

  -- User nonaktif tidak menerima
  perform pg_temp.su();
  update public.user_profiles set is_active = false where id = own::uuid;
  perform pg_temp.u(mkt);
  perform public.doc_change_status('PROD', v_po, 'CANCELLED', 'uji 3');
  v_po := public.save_doc('PROD', null, jsonb_build_object('ro_id', v_ro, 'needed_date', current_date + 1),
     jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', v_top, 'qty', 5))));
  perform public.doc_change_status('PROD', v_po, 'SUBMITTED');
  perform pg_temp.su();
  assert pg_temp.rcpt(v_po, 'SUBMITTED') = '-', 'user nonaktif tidak menerima: ' || pg_temp.rcpt(v_po, 'SUBMITTED');
  update public.user_profiles set is_active = true where id = own::uuid;

  -- Kotak keluar tidak bisa dibaca atau diubah langsung
  perform pg_temp.u(own);
  assert pg_temp.err('select * from public.notification_outbox') is not null, 'kotak keluar tertutup';
  assert pg_temp.err('delete from public.notification_outbox') is not null, 'kotak keluar tidak bisa dihapus';

  -- Pengambilan: hanya milik pemicu sendiri; hasil dilaporkan; gagal 3 kali menjadi failed
  perform pg_temp.su();
  update public.notification_outbox set status = 'sent';
  insert into public.notification_outbox (actor_id, recipient_id, to_email, subject, message) values (mkt::uuid, own::uuid, 'owner@test', 's', 'm') returning id into v_id;
  perform pg_temp.u(own);
  assert (select count(*) from public.notif_claim()) = 0, 'orang lain tidak bisa mengambil antrean';
  perform pg_temp.u(mkt);
  assert (select count(*) from public.notif_claim()) = 1, 'pemicu mengambil antreannya';
  assert (select count(*) from public.notif_claim()) = 0, 'tidak diambil dua kali';
  perform public.notif_finish(v_id, false, 'SMTP down');
  perform pg_temp.su();
  assert (select status || attempts from public.notification_outbox where id = v_id) = 'pending1', 'gagal pertama kembali antre';
  perform pg_temp.u(mkt);
  perform public.notif_claim(); perform public.notif_finish(v_id, false, 'SMTP down');
  perform public.notif_claim(); perform public.notif_finish(v_id, false, 'SMTP down');
  perform pg_temp.su();
  assert (select status from public.notification_outbox where id = v_id) = 'failed', 'gagal 3 kali menjadi failed';
  perform pg_temp.u(mkt);
  assert (select count(*) from public.notif_claim()) = 0, 'failed tidak diambil lagi';
  perform pg_temp.su();
  update public.notification_outbox set status = 'pending', attempts = 0 where id = v_id;
  perform pg_temp.u(mkt);
  perform public.notif_claim();
  perform public.notif_finish(v_id, true);
  perform pg_temp.su();
  assert (select status from public.notification_outbox where id = v_id) = 'sent', 'berhasil terkirim';
  perform pg_temp.u(own);
  perform public.notif_finish(v_id, false, 'x');   -- bukan miliknya / bukan sending: tidak berpengaruh
  assert (select my_email from (select public.my_email() as my_email) s) = 'owner@test', 'my_email';
end $$;

-- Purchase Request: satu email per lembar per status, ke yang berizin
do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  pur constant text := '00000000-0000-0000-0000-000000000003';
  v_ids uuid[]; v_cnt integer;
begin
  perform pg_temp.su();
  delete from public.notification_outbox;
  delete from public.user_permission_overrides;
  perform pg_temp.u(pur);
  perform public.pr_add_items('[{"item_name":"Garam uji","qty":2,"price":1000,"unit":"kg","pay_method":"CASH"},{"item_name":"Gula uji","qty":1,"price":2000,"unit":"kg","pay_method":"CASH"}]'::jsonb, null);
  select array_agg(id) into v_ids from public.pr_items where item_name in ('Garam uji','Gula uji');
  perform public.pr_move_items(v_ids, 'SUBMITTED', null);
  perform pg_temp.su();
  select count(*) into v_cnt from public.notification_outbox where doc_type = 'PR' and to_status = 'SUBMITTED';
  assert v_cnt = 1, 'dua barang satu lembar: satu email (owner), dapat ' || v_cnt;
  assert (select message from public.notification_outbox where doc_type = 'PR') like '%2 barang%', 'jumlah barang tercantum';
  assert (select to_email from public.notification_outbox where doc_type = 'PR') = 'owner@test', 'ke yang berizin menyetujui';
  perform pg_temp.u(own);
  perform public.pr_move_items(v_ids, 'APPROVED', null);
  perform pg_temp.su();
  assert (select string_agg(split_part(to_email,'@',1), ',' order by to_email) from public.notification_outbox where doc_type = 'PR' and to_status = 'APPROVED') = 'purchasing', 'disetujui: Purchasing (yang memproses), pemroses owner tidak ikut';
end $$;
