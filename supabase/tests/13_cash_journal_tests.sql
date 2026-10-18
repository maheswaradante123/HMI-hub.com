-- Pengujian Cash Payment Journal: nomor mingguan, alur ACC, kunci rencana, tarik item PR, PR menjadi PAID saat realisasi.
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlstate; end $$;
do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  mkt constant text := '00000000-0000-0000-0000-000000000002';
  pur constant text := '00000000-0000-0000-0000-000000000003';
  acc constant text := '00000000-0000-0000-0000-000000000004';
  v_unit uuid; v_pr uuid; v_item uuid; v_j uuid; v_j2 uuid; v_j3 uuid; v_n text; r record; v_cnt int;
begin
  delete from public.user_permission_overrides;
  select id into v_unit from public.units limit 1;
  insert into public.purchase_requests (requester_id, reason, status) values (own::uuid, 'pakan', 'APPROVED') returning id into v_pr;
  insert into public.pr_items (pr_id, line_no, item_name, qty, unit_id, estimated_price) values (v_pr, 1, 'Konsentrat', 140, v_unit, 200000) returning id into v_item;

  -- nomor mingguan: 6 April 2026 (Senin) = minggu ke-2 April; 1 April 2026 = minggu ke-1
  perform pg_temp.u(acc);
  v_j := public.save_doc('JCP', null, jsonb_build_object('journal_date', '2026-04-06', 'initiator_name', 'Muhamad Arfan', 'initiator_title', 'Operator'),
    jsonb_build_object('lines', jsonb_build_array(
      jsonb_build_object('trans_date', '2026-04-04', 'ac', 'OPR', 'code', 'BP', 'description', 'Konsentrat', 'price', 200000, 'qty', 140, 'unit', 'sak', 'pr_item_id', v_item),
      jsonb_build_object('trans_date', '2026-04-05', 'ac', 'OPR', 'code', 'BO', 'description', 'Bensin', 'price', 30000, 'qty', 1, 'unit', 'pcs'))));
  select doc_number into v_n from public.cash_journals where id = v_j;
  assert v_n = 'CPJ-002-IV-26', 'nomor minggu: ' || v_n;
  v_j2 := public.save_doc('JCP', null, jsonb_build_object('journal_date', '2026-04-08'),
    jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('description', 'Isi ulang', 'price', 1000, 'qty', 1))));
  assert (select doc_number from public.cash_journals where id = v_j2) = 'CPJ-002-IV-26-2', 'minggu sama diberi akhiran';
  v_j3 := public.save_doc('JCP', null, jsonb_build_object('journal_date', '2026-04-01'),
    jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('description', 'x', 'price', 1, 'qty', 1))));
  assert (select doc_number from public.cash_journals where id = v_j3) = 'CPJ-001-IV-26', 'minggu pertama';

  -- item PR yang sama tidak boleh dipakai di dua jurnal aktif
  assert pg_temp.err(format($q$select public.save_doc('JCP', %L, jsonb_build_object('journal_date','2026-04-08'),
    jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('description','Konsentrat','price',1,'qty',1,'pr_item_id',%L))))$q$, v_j2, v_item)) = '23505', 'item PR ganda ditolak';
  select count(*) into v_cnt from public.cpj_pullable_pr_items() where pr_item_id = v_item;
  assert v_cnt = 0, 'item PR yang sudah dipakai tidak bisa ditarik lagi';

  -- Purchasing hanya lihat, Marketing tidak punya akses
  perform pg_temp.u(pur);
  assert (select count(*) from public.cash_journals) = 3, 'purchasing bisa lihat';
  assert pg_temp.err(format($q$select public.save_doc('JCP', %L, jsonb_build_object('notes','x'))$q$, v_j)) = '42501', 'purchasing tidak boleh ubah';
  perform pg_temp.u(mkt);
  assert (select count(*) from public.cash_journals) = 0, 'marketing tidak melihat';

  -- alur: accounting mengajukan; hanya Owner yang ACC
  perform pg_temp.u(acc);
  perform public.doc_change_status('JCP', v_j, 'WAITING');
  assert pg_temp.err(format($q$select public.doc_change_status('JCP', %L, 'ACC')$q$, v_j)) = '42501', 'accounting tidak boleh ACC';
  assert pg_temp.err(format($q$select public.save_doc('JCP', %L, jsonb_build_object('notes','x'))$q$, v_j)) = '55000', 'menunggu ACC: terkunci';
  perform pg_temp.u(own);
  perform public.doc_change_status('JCP', v_j, 'ACC');
  assert (select approved_on from public.cash_journals where id = v_j) is not null, 'tanggal ACC tercatat';

  -- setelah ACC: rencana terkunci, realisasi boleh
  perform pg_temp.u(acc);
  assert pg_temp.err(format($q$select public.save_doc('JCP', %L, jsonb_build_object('journal_date','2026-04-06'),
    jsonb_build_object('lines', jsonb_build_array(
      jsonb_build_object('trans_date','2026-04-04','ac','OPR','code','BP','description','Konsentrat','price',999999,'qty',140,'unit','sak','pr_item_id',%L),
      jsonb_build_object('trans_date','2026-04-05','ac','OPR','code','BO','description','Bensin','price',30000,'qty',1,'unit','pcs'))))$q$, v_j, v_item)) = '55000', 'rencana tidak boleh berubah setelah ACC';
  perform public.save_doc('JCP', v_j, jsonb_build_object('journal_date', '2026-04-06'),
    jsonb_build_object('lines', jsonb_build_array(
      jsonb_build_object('trans_date','2026-04-04','ac','OPR','code','BP','description','Konsentrat','price',200000,'qty',140,'unit','sak','pr_item_id',v_item,'real_price',198500,'real_qty',140,'proof','BP KONSENTRAT.jpg'),
      jsonb_build_object('trans_date','2026-04-05','ac','OPR','code','BO','description','Bensin','price',30000,'qty',1,'unit','pcs','real_price',20000,'real_qty',1))));
  assert (select real_price from public.cash_journal_lines where journal_id = v_j and line_no = 1) = 198500, 'realisasi tersimpan';

  -- realisasi: PR RECEIVED menjadi PAID
  reset role; update public.purchase_requests set status = 'RECEIVED' where id = v_pr; perform pg_temp.u(acc);
  perform public.doc_change_status('JCP', v_j, 'REALIZED');
  assert (select realized_on from public.cash_journals where id = v_j) is not null, 'tanggal realisasi tercatat';
  assert (select status from public.purchase_requests where id = v_pr) = 'PAID', 'PR menjadi PAID';
  assert pg_temp.err(format($q$select public.save_doc('JCP', %L, jsonb_build_object('notes','x'))$q$, v_j)) = '55000', 'direalisasi: terkunci';

  -- batal memerlukan alasan dan izin hapus; PR kembali RECEIVED
  assert pg_temp.err(format($q$select public.doc_change_status('JCP', %L, 'VOID')$q$, v_j)) = '22023', 'alasan wajib';
  perform public.doc_change_status('JCP', v_j, 'VOID', 'salah');
  assert (select status from public.purchase_requests where id = v_pr) = 'RECEIVED', 'PR kembali RECEIVED';
  select count(*) into v_cnt from public.cpj_pullable_pr_items() where pr_item_id = v_item;
  assert v_cnt = 1, 'item PR bisa ditarik lagi setelah jurnal batal';

  -- jurnal kosong tidak bisa diajukan
  perform pg_temp.u(own);
  v_j := public.save_doc('JCP', null, jsonb_build_object('journal_date', '2026-04-20'));
  assert pg_temp.err(format($q$select public.doc_change_status('JCP', %L, 'WAITING')$q$, v_j)) = '22023', 'jurnal kosong';
end $$;
