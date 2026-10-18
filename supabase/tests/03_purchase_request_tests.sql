-- Pengujian Purchase Request per barang (lembar mingguan, status per barang). Jalankan setelah 01 dan 02.
\set ON_ERROR_STOP on

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
  v_sheet uuid; v_sheet2 uuid; v_n int; v_no text; v_a uuid; v_b uuid; v_c uuid; v_ids uuid[]; v_st text;
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_items jsonb;
begin
  v_items := jsonb_build_array(
    jsonb_build_object('ac','OPR','code','BP','item_name','Rumput Prio','price',750,'qty',3080,'unit','kg','pay_method','tf'),
    jsonb_build_object('ac','MKT','code','BM','item_name','Materai 10.000','price',12000,'qty',10,'unit','pcs','pay_method','cash'));

  -- Marketing menambah barang: lembar minggu ini dibuat otomatis
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', mkt, true);
  v_sheet := public.pr_add_items(v_items);
  select doc_number into v_no from public.purchase_requests where id = v_sheet;
  assert v_no = public.pr_sheet_number(v_today) and v_no ~ '^PR-[0-9]{3}-[IVX]+-[0-9]{2}$', 'format nomor lembar: ' || v_no;
  select count(*) into v_n from public.pr_items where pr_id = v_sheet and status = 'DRAFT' and requester_id = mkt::uuid;
  assert v_n = 2, 'barang tersimpan sebagai Draft milik pemohon';
  select id into v_a from public.pr_items where pr_id = v_sheet and line_no = 1;
  select id into v_b from public.pr_items where pr_id = v_sheet and line_no = 2;

  -- Barang dari user lain masuk lembar yang sama (satu lembar per minggu)
  perform pg_temp.as_user(prod);
  v_sheet2 := public.pr_add_items(jsonb_build_array(jsonb_build_object('ac','TOKO','code','BP','item_name','Plastik wrap','price',125000,'qty',6,'unit','roll')));
  assert v_sheet2 = v_sheet, 'minggu yang sama memakai lembar yang sama';
  select id into v_c from public.pr_items where pr_id = v_sheet and requester_id = prod::uuid;
  select count(*) into v_n from public.pr_items; assert v_n = 1, 'produksi hanya melihat barangnya sendiri';
  select count(*) into v_n from public.purchase_requests; assert v_n = 1, 'produksi melihat lembar yang memuat barangnya';

  -- Tulis langsung ditolak
  begin update public.pr_items set status = 'APPROVED' where id = v_c;
    raise exception 'update langsung seharusnya ditolak';
  exception when insufficient_privilege then null; end;
  begin perform public.next_doc_number('PR','PR');
    raise exception 'next_doc_number tidak boleh dipanggil user';
  exception when insufficient_privilege then null; end;

  -- Validasi isi
  begin perform public.pr_add_items('[]'::jsonb); raise exception 'kosong seharusnya ditolak';
  exception when invalid_parameter_value then null; end;
  begin perform public.pr_add_items(jsonb_build_array(jsonb_build_object('item_name','A','qty',0,'unit','pcs'))); raise exception 'qty 0 seharusnya ditolak';
  exception when invalid_parameter_value then null; end;
  begin perform public.pr_add_items(jsonb_build_array(jsonb_build_object('item_name','','qty',1,'unit','pcs'))); raise exception 'deskripsi kosong seharusnya ditolak';
  exception when invalid_parameter_value then null; end;
  begin perform public.pr_add_items(jsonb_build_array(jsonb_build_object('item_name','A','qty',1,'unit','pcs','ac','XYZ'))); raise exception 'A/C tidak dikenal seharusnya ditolak';
  exception when check_violation then null; end;
  begin perform public.pr_add_items(jsonb_build_array(jsonb_build_object('item_name','A','qty',1,'unit','pcs')), v_today - 40);
    raise exception 'tanggal lain hanya untuk Purchasing/Owner';
  exception when insufficient_privilege then null; end;

  -- Visibilitas
  perform pg_temp.as_user(mkt);
  select count(*) into v_n from public.pr_items; assert v_n = 2, 'marketing hanya barang sendiri';
  perform pg_temp.as_user(pur);
  select count(*) into v_n from public.pr_items; assert v_n = 3, 'purchasing lihat semua';
  perform pg_temp.as_user(acc);
  select count(*) into v_n from public.pr_items; assert v_n = 3, 'accounting lihat semua';

  -- Ubah barang Draft: pembuat boleh, orang lain (tanpa izin edit) tidak
  perform pg_temp.as_user(mkt);
  perform public.pr_update_item(v_a, jsonb_build_object('qty', 3100, 'item_name', 'Rumput Prio (21 April)'));
  assert (select qty from public.pr_items where id = v_a) = 3100, 'draft bisa diubah pembuat';
  perform pg_temp.as_user(prod);
  begin perform public.pr_update_item(v_a, jsonb_build_object('qty', 1));
    raise exception 'ubah barang orang lain seharusnya ditolak';
  exception when insufficient_privilege or no_data_found then null; end;

  -- Pengajuan hanya oleh Purchasing; Marketing tidak
  perform pg_temp.as_user(mkt);
  begin perform public.pr_move_items(array[v_a], 'SUBMITTED'); raise exception 'marketing tidak boleh mengajukan';
  exception when insufficient_privilege then null; end;
  perform pg_temp.as_user(pur);
  assert public.pr_move_items(array[v_a, v_b, v_c], 'SUBMITTED') = 3, 'purchasing mengajukan 3 barang';
  assert public.pr_move_items(array[v_a], 'SUBMITTED') = 0, 'barang yang sudah diajukan dilewati';
  begin perform public.pr_update_item(v_a, jsonb_build_object('qty', 1)); raise exception 'ubah setelah diajukan seharusnya ditolak';
  exception when object_not_in_prerequisite_state then null; end;

  -- Persetujuan hanya Owner
  begin perform public.pr_move_items(array[v_a], 'APPROVED'); raise exception 'purchasing tidak boleh menyetujui';
  exception when insufficient_privilege then null; end;
  perform pg_temp.as_user(acc);
  begin perform public.pr_move_items(array[v_a], 'APPROVED'); raise exception 'accounting tidak boleh menyetujui';
  exception when insufficient_privilege then null; end;
  perform pg_temp.as_user(own);
  begin perform public.pr_move_items(array[v_b], 'REJECTED', '  '); raise exception 'tolak tanpa alasan seharusnya ditolak';
  exception when invalid_parameter_value then null; end;
  assert public.pr_move_items(array[v_a, v_c], 'APPROVED') = 2, 'owner menyetujui';
  assert public.pr_move_items(array[v_b], 'REJECTED', 'Anggaran belum ada') = 1, 'owner menolak per barang';
  assert (select review_note from public.pr_items where id = v_b) = 'Anggaran belum ada', 'alasan penolakan tersimpan';
  assert (select decided_by from public.pr_items where id = v_a) = own::uuid, 'penyetuju tercatat';
  assert public.pr_move_items(array[v_b], 'APPROVED') = 0, 'barang ditolak tidak bisa disetujui';

  -- Order / Received: Purchasing; lompat status dilewati
  perform pg_temp.as_user(mkt);
  begin perform public.pr_move_items(array[v_a], 'ORDERED'); raise exception 'marketing tidak boleh memesan';
  exception when insufficient_privilege then null; end;
  perform pg_temp.as_user(pur);
  assert public.pr_move_items(array[v_a], 'ORDERED') = 1, 'order';
  assert public.pr_move_items(array[v_a, v_c], 'RECEIVED') = 2, 'received (dari Order dan dari Approved)';
  assert public.pr_move_items(array[v_a], 'ORDERED') = 0, 'mundur ke Order tidak boleh';
  perform public.pr_update_item(v_a, jsonb_build_object('pay_method', 'tf arfan', 'proof', 'BP RUMPUT.jpg'));
  assert (select proof from public.pr_items where id = v_a) = 'BP RUMPUT.jpg', 'bukti diisi Purchasing';
  perform pg_temp.as_user(mkt);
  begin perform public.pr_update_item(v_a, jsonb_build_object('proof', 'x')); raise exception 'marketing tidak boleh isi bukti';
  exception when insufficient_privilege then null; end;

  -- Batal: pembuat hanya Draft miliknya; selain itu perlu izin hapus (Owner)
  perform pg_temp.as_user(prod);
  v_ids := array[public.pr_add_items(jsonb_build_array(jsonb_build_object('item_name','Sarung tangan','qty',2,'unit','pcs')))];
  select id into v_a from public.pr_items where requester_id = prod::uuid and item_name = 'Sarung tangan';
  assert public.pr_move_items(array[v_c], 'CANCELLED') = 0, 'produksi tidak boleh batalkan barang yang sudah Received';
  assert public.pr_move_items(array[v_a], 'CANCELLED') = 1, 'pembuat membatalkan Draft sendiri';

  -- Riwayat lengkap per barang
  perform pg_temp.as_user(own);
  select count(*) into v_n from public.pr_status_history where item_id = v_c;
  assert v_n = 4, 'riwayat barang C: DRAFT, SUBMITTED, APPROVED, RECEIVED, dapat ' || v_n;

  -- Riwayat tidak bisa diubah
  reset role;
  begin update public.pr_status_history set note='x'; raise exception 'riwayat seharusnya tidak bisa diubah';
  exception when raise_exception then
    if sqlerrm not like 'riwayat tidak boleh%' then raise; end if;
  end;

  -- Audit trail mencatat perubahan status barang oleh pelaku
  select count(*) into v_n from public.audit_logs
   where table_name='pr_items' and action='UPDATE' and new_values->>'status'='APPROVED' and user_id = own::uuid;
  assert v_n = 2, 'audit persetujuan tercatat, dapat ' || v_n;

  -- Dashboard: barang yang menunggu persetujuan
  perform pg_temp.as_user(pur);
  perform public.pr_add_items(jsonb_build_array(jsonb_build_object('item_name','Kabel','qty',1,'unit','pcs')));
  perform public.pr_move_items(array(select id from public.pr_items where item_name = 'Kabel'), 'SUBMITTED');
  set local role authenticated;
  perform pg_temp.as_user(own);
  assert (public.dashboard_summary()->>'pr_waiting')::int = 1, 'dashboard menghitung barang Diajukan';
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
