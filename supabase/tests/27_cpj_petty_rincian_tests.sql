-- Pengujian rincian Petty Cash di CPJ: tersimpan sebagai larik, dan total rincian wajib sama dengan realisasi saat realisasi diselesaikan.
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlstate; end $$;
do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  acc constant text := '00000000-0000-0000-0000-000000000004';
  v_j uuid; v_j2 uuid; v_d jsonb;
  dt text := '[{"no":1,"date":"2026-10-31","text":"Bensin","amount":50000,"proof":"https://drive.google.com/drive/folders/abc"},{"no":2,"date":"2026-10-31","text":"Parkir","amount":71000,"proof":""}]';
begin
  delete from public.user_permission_overrides;
  perform pg_temp.u(acc);
  v_j := public.save_doc('JCP', null, jsonb_build_object('journal_date', '2026-10-31'),
    jsonb_build_object('lines', jsonb_build_array(
      jsonb_build_object('trans_date','2026-10-31','ac','OPR','code','BP','description','Petty Cash','price',500000,'qty',1,'unit','paket','real_price',121000,'real_qty',1,'details',dt),
      jsonb_build_object('trans_date','2026-10-31','ac','OPR','code','BO','description','Bensin','price',30000,'qty',1,'unit','pcs'))));
  select details into v_d from public.cash_journal_lines where journal_id = v_j and line_no = 1;
  assert jsonb_typeof(v_d) = 'array' and jsonb_array_length(v_d) = 2, 'rincian tersimpan sebagai larik';
  assert (select details from public.cash_journal_lines where journal_id = v_j and line_no = 2) = '[]'::jsonb, 'baris biasa: rincian kosong';
  perform public.doc_change_status('JCP', v_j, 'WAITING');
  perform pg_temp.u(own);
  perform public.doc_change_status('JCP', v_j, 'ACC');

  -- total rincian (121.000) sama dengan realisasi -> boleh
  perform pg_temp.u(acc);
  perform public.doc_change_status('JCP', v_j, 'REALIZED');
  assert (select status from public.cash_journals where id = v_j) = 'REALIZED', 'realisasi selesai bila total rincian sama';

  -- total rincian berbeda -> ditolak; setelah rincian diperbaiki -> boleh
  v_j2 := public.save_doc('JCP', null, jsonb_build_object('journal_date', '2026-11-02'),
    jsonb_build_object('lines', jsonb_build_array(
      jsonb_build_object('trans_date','2026-11-02','ac','OPR','code','BP','description','petty cash minggu 2','price',500000,'qty',1,'unit','paket','real_price',121000,'real_qty',1,
        'details','[{"no":1,"date":"2026-11-02","text":"Bensin","amount":50000,"proof":""}]'))));
  perform public.doc_change_status('JCP', v_j2, 'WAITING');
  perform pg_temp.u(own);
  perform public.doc_change_status('JCP', v_j2, 'ACC');
  perform pg_temp.u(acc);
  assert pg_temp.err(format($q$select public.doc_change_status('JCP', %L, 'REALIZED')$q$, v_j2)) = '22023', 'total rincian kurang ditolak';
  perform public.save_doc('JCP', v_j2, jsonb_build_object('journal_date', '2026-11-02'),
    jsonb_build_object('lines', jsonb_build_array(
      jsonb_build_object('trans_date','2026-11-02','ac','OPR','code','BP','description','petty cash minggu 2','price',500000,'qty',1,'unit','paket','real_price',121000,'real_qty',1,
        'details','[{"no":1,"date":"2026-11-02","text":"Bensin","amount":50000,"proof":""},{"no":2,"date":"2026-11-02","text":"ATK","amount":71000,"proof":""}]'))));
  perform public.doc_change_status('JCP', v_j2, 'REALIZED');
  assert (select status from public.cash_journals where id = v_j2) = 'REALIZED', 'realisasi selesai setelah rincian dilengkapi';

  -- rincian bukan bagian rencana: boleh diubah setelah ACC (sudah terbukti di atas lewat save_doc pada status ACC)
end $$;
