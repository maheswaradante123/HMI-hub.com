-- Pengujian Phase 5 (Purchase Request). Jalankan setelah 01 dan 02.
\set ON_ERROR_STOP on

-- Helper: panggil sebagai user tertentu
create or replace function pg_temp.as_user(p text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p, true);
end $$;

do $$
declare
  mkt  constant text := '00000000-0000-0000-0000-000000000002';
  pur  constant text := '00000000-0000-0000-0000-000000000003';
  acc  constant text := '00000000-0000-0000-0000-000000000004';
  prod constant text := '00000000-0000-0000-0000-000000000005';
  own  constant text := '00000000-0000-0000-0000-000000000001';
  v_unit uuid; v_prod uuid; v_sup uuid; v_id uuid; v_id2 uuid; v_n int; v_no text; v_item uuid;
  v_items jsonb;
begin
  select id into v_unit from public.units where code='KG';
  select id into v_prod from public.products where code='MF-TOPSIDE';
  select id into v_sup  from public.suppliers where code='SUP-SAPI-A';
  v_items := jsonb_build_array(
    jsonb_build_object('product_id', v_prod, 'item_name','Topside','qty','10','unit_id', v_unit,'estimated_price','120000'),
    jsonb_build_object('item_name','Kertas HVS','qty','5','unit_id', v_unit,'estimated_price',''));

  -- Marketing membuat draf
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', mkt, true);
  v_id := public.save_purchase_request(null, 'Stok menipis', 'HIGH', v_items);
  select doc_number into v_no from public.purchase_requests where id = v_id;
  assert v_no ~ '^PR-[0-9]{4}-0001$', 'format nomor PR salah: ' || v_no;
  select count(*) into v_n from public.pr_items where pr_id = v_id; assert v_n = 2, 'item tersimpan';

  -- nomor berikutnya bertambah, dari user lain
  v_id2 := public.save_purchase_request(null, 'PR kedua', 'NORMAL', v_items);
  select doc_number into v_no from public.purchase_requests where id = v_id2;
  assert v_no ~ '-0002$', 'nomor kedua harus 0002: ' || v_no;

  -- tulis langsung ditolak (tidak ada hak tabel)
  begin
    update public.purchase_requests set status = 'APPROVED' where id = v_id;
    raise exception 'update langsung seharusnya ditolak';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.purchase_requests (requester_id, reason) values (mkt::uuid, 'x');
    raise exception 'insert langsung seharusnya ditolak';
  exception when insufficient_privilege then null; end;
  begin
    perform public.next_doc_number('PR','PR');
    raise exception 'next_doc_number tidak boleh dipanggil user';
  exception when insufficient_privilege then null; end;

  -- validasi isi
  begin
    perform public.save_purchase_request(null, 'x', 'NORMAL', '[]'::jsonb);
    raise exception 'item kosong seharusnya ditolak';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.save_purchase_request(null, '  ', 'NORMAL', v_items);
    raise exception 'alasan kosong seharusnya ditolak';
  exception when check_violation then null; end;
  begin
    perform public.save_purchase_request(null, 'x', 'ASAP', v_items);
    raise exception 'prioritas tidak valid seharusnya ditolak';
  exception when check_violation then null; end;
  begin
    perform public.save_purchase_request(null, 'x', 'NORMAL',
      jsonb_build_array(jsonb_build_object('item_name','A','qty','0','unit_id', v_unit)));
    raise exception 'qty 0 seharusnya ditolak';
  exception when check_violation then null; end;

  -- Ubah draf sendiri
  perform public.save_purchase_request(v_id, 'Stok menipis banget', 'HIGH', jsonb_build_array(
    jsonb_build_object('item_name','Topside','qty','12','unit_id', v_unit,'estimated_price','125000')));
  select count(*) into v_n from public.pr_items where pr_id = v_id; assert v_n = 1, 'draf diganti item-nya';

  -- Visibilitas: Produksi tidak melihat PR Marketing; Marketing hanya miliknya
  perform pg_temp.as_user(prod);
  select count(*) into v_n from public.purchase_requests; assert v_n = 0, 'produksi tidak boleh lihat PR orang lain';
  select count(*) into v_n from public.pr_items; assert v_n = 0, 'item PR orang lain tersembunyi';
  perform pg_temp.as_user(mkt);
  select count(*) into v_n from public.purchase_requests; assert v_n = 2, 'marketing lihat PR sendiri';
  perform pg_temp.as_user(pur);
  select count(*) into v_n from public.purchase_requests; assert v_n = 2, 'purchasing lihat semua';
  perform pg_temp.as_user(acc);
  select count(*) into v_n from public.purchase_requests; assert v_n = 2, 'accounting lihat semua';

  -- Orang lain tidak bisa mengubah/mengajukan/menghapus draf
  perform pg_temp.as_user(pur);
  begin perform public.save_purchase_request(v_id, 'curang', 'LOW', v_items);
    raise exception 'ubah draf orang lain seharusnya ditolak';
  exception when insufficient_privilege then null; end;
  begin perform public.pr_change_status(v_id, 'SUBMITTED');
    raise exception 'ajukan PR orang lain seharusnya ditolak';
  exception when insufficient_privilege then null; end;
  begin perform public.pr_discard(v_id);
    raise exception 'hapus draf orang lain seharusnya ditolak';
  exception when insufficient_privilege then null; end;

  -- Alur: ajukan -> (marketing tidak boleh approve)
  perform pg_temp.as_user(mkt);
  perform public.pr_change_status(v_id, 'SUBMITTED');
  begin perform public.pr_change_status(v_id, 'APPROVED');
    raise exception 'marketing tidak boleh menyetujui';
  exception when insufficient_privilege then null; end;
  begin perform public.save_purchase_request(v_id, 'ubah setelah ajukan', 'LOW', v_items);
    raise exception 'ubah setelah diajukan seharusnya ditolak';
  exception when object_not_in_prerequisite_state then null; end;
  begin perform public.pr_discard(v_id);
    raise exception 'hapus setelah diajukan seharusnya ditolak';
  exception when object_not_in_prerequisite_state then null; end;

  -- Purchasing/Accounting tidak boleh menyetujui
  perform pg_temp.as_user(pur);
  begin perform public.pr_change_status(v_id, 'APPROVED');
    raise exception 'purchasing tidak boleh menyetujui';
  exception when insufficient_privilege then null; end;
  perform pg_temp.as_user(acc);
  begin perform public.pr_change_status(v_id, 'APPROVED');
    raise exception 'accounting tidak boleh menyetujui';
  exception when insufficient_privilege then null; end;

  -- Owner: tinjau, tolak butuh alasan, lalu setujui
  perform pg_temp.as_user(own);
  perform public.pr_change_status(v_id, 'UNDER_REVIEW');
  begin perform public.pr_change_status(v_id, 'UNDER_REVIEW');
    raise exception 'tinjau dua kali seharusnya ditolak';
  exception when object_not_in_prerequisite_state then null; end;
  begin perform public.pr_change_status(v_id, 'ORDERED');
    raise exception 'lompat status seharusnya ditolak';
  exception when object_not_in_prerequisite_state then null; end;
  begin perform public.pr_change_status(v_id, 'REJECTED', '   ');
    raise exception 'tolak tanpa alasan seharusnya ditolak';
  exception when invalid_parameter_value then null; end;
  perform public.pr_change_status(v_id, 'APPROVED');
  select count(*) into v_n from public.purchase_requests
   where id = v_id and status='APPROVED' and decided_by = own::uuid and decided_at is not null;
  assert v_n = 1, 'penyetuju tercatat';

  -- Setelah disetujui: supplier hanya oleh pemegang izin edit
  select id into v_item from public.pr_items where pr_id = v_id limit 1;
  perform pg_temp.as_user(mkt);
  begin perform public.pr_set_item_supplier(v_item, v_sup);
    raise exception 'marketing tidak boleh mengisi supplier';
  exception when insufficient_privilege then null; end;
  begin perform public.pr_change_status(v_id, 'ORDERED');
    raise exception 'marketing tidak boleh memesan';
  exception when insufficient_privilege then null; end;
  perform pg_temp.as_user(pur);
  perform public.pr_set_item_supplier(v_item, v_sup);
  perform public.pr_change_status(v_id, 'ORDERED');
  perform public.pr_change_status(v_id, 'RECEIVED');
  begin perform public.pr_change_status(v_id, 'PAID');
    raise exception 'PAID belum boleh lewat jalur manual (menunggu CPJ)';
  exception when object_not_in_prerequisite_state then null; end;
  select count(*) into v_n from public.pr_status_history where pr_id = v_id;
  assert v_n = 6, 'riwayat status lengkap (DRAFT,SUBMITTED,UNDER_REVIEW,APPROVED,ORDERED,RECEIVED), dapat ' || v_n;

  -- Supplier tidak bisa diisi pada PR yang belum disetujui
  perform pg_temp.as_user(mkt);
  select id into v_item from public.pr_items where pr_id = v_id2 limit 1;
  perform pg_temp.as_user(pur);
  begin perform public.pr_set_item_supplier(v_item, v_sup);
    raise exception 'supplier pada draf seharusnya ditolak';
  exception when object_not_in_prerequisite_state then null; end;

  -- Tolak dengan alasan
  perform pg_temp.as_user(mkt);
  perform public.pr_change_status(v_id2, 'SUBMITTED');
  perform pg_temp.as_user(own);
  perform public.pr_change_status(v_id2, 'REJECTED', 'Anggaran belum ada');
  select count(*) into v_n from public.purchase_requests where id = v_id2 and status='REJECTED' and review_note = 'Anggaran belum ada';
  assert v_n = 1, 'alasan penolakan tersimpan';
  begin perform public.pr_change_status(v_id2, 'APPROVED');
    raise exception 'PR ditolak adalah status akhir';
  exception when object_not_in_prerequisite_state then null; end;

  -- Hapus draf sendiri (soft delete) lalu tidak bisa diproses
  perform pg_temp.as_user(prod);
  v_id2 := public.save_purchase_request(null, 'Sarung tangan habis', 'NORMAL', v_items);
  perform public.pr_discard(v_id2);
  select count(*) into v_n from public.purchase_requests where id = v_id2 and deleted_at is not null;
  assert v_n = 1, 'draf soft delete (baris tetap ada)';
  begin perform public.pr_change_status(v_id2, 'SUBMITTED');
    raise exception 'draf terhapus tidak boleh diajukan';
  exception when no_data_found then null; end;

  -- Riwayat tidak bisa diubah
  perform pg_temp.as_user(own);
  reset role;
  begin
    update public.pr_status_history set note='x';
    raise exception 'riwayat seharusnya tidak bisa diubah';
  exception when raise_exception then
    if sqlerrm not like 'riwayat tidak boleh%' then raise; end if;
  end;

  -- Audit trail mencatat perubahan status oleh pelaku
  select count(*) into v_n from public.audit_logs
   where table_name='purchase_requests' and action='UPDATE'
     and new_values->>'status'='APPROVED' and user_id = own::uuid;
  assert v_n = 1, 'audit persetujuan tercatat';
end $$;

\echo SEMUA PENGUJIAN PHASE 5 LULUS

-- Daftar nama staff terbuka untuk semua user login, tanpa membuka user_profiles
do $$
declare n int;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
  select count(*) into n from public.user_directory; assert n = 7, 'direktori nama, dapat ' || n;
  select count(*) into n from public.user_profiles; assert n = 1, 'user_profiles tetap tertutup';
  begin
    perform 1 from public.user_directory where false;
    set local role anon;
    perform 1 from public.user_directory;
    raise exception 'anon tidak boleh membaca direktori';
  exception when insufficient_privilege then null; end;
end $$;
\echo DIREKTORI NAMA LULUS
