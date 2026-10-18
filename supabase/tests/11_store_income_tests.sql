-- Pengujian Pemasukan Toko: simpan dokumen, nomor, saldo negatif, izin, tarik data invoice dan piutang.
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;
create function pg_temp.fails(p_sql text, p_code text) returns boolean language plpgsql as $$
begin execute p_sql; return false;
exception when others then return sqlstate = p_code; end $$;
do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  mkt constant text := '00000000-0000-0000-0000-000000000002';
  acc constant text := '00000000-0000-0000-0000-000000000004';
  v_id uuid; r record; n integer;
begin
  perform pg_temp.u(mkt);
  assert pg_temp.fails($q$select public.save_doc('PMT', null, '{"period_from":"2026-02-27","period_to":"2026-03-05"}', '{"lines":[],"recv":[]}')$q$, '42501'), 'marketing tidak boleh membuat';

  perform pg_temp.u(acc);
  v_id := public.save_doc('PMT', null, '{"period_from":"2026-02-27","period_to":"2026-03-05"}',
    jsonb_build_object(
      'lines', jsonb_build_array(
        jsonb_build_object('entry_date','2026-02-27','description','Pemasukan','cash',1064000,'qris',854500),
        jsonb_build_object('entry_date','2026-02-27','description','Prive Mas Khrisna','cash',-50000),
        jsonb_build_object('entry_date','2026-03-06','description','Penyetoran','deposited',1000000)),
      'recv', jsonb_build_array(jsonb_build_object('name','Habitare','amount',20812500))));
  select * into r from public.store_income_reports where id = v_id;
  assert r.doc_number ~ '^PMT-[0-9]{3}-[IVX]+-[0-9]{2}$', 'nomor PMT: ' || r.doc_number;
  assert (select sum(cash) from public.store_income_lines where report_id = v_id) = 1014000, 'kas boleh negatif';
  assert pg_temp.fails(format($q$select public.save_doc('PMT', null, '{"period_from":"2026-03-05","period_to":"2026-02-27"}', '{"lines":[],"recv":[]}')$q$), '23514'), 'periode terbalik ditolak';
  assert pg_temp.fails($q$select public.save_doc('PMT', null, '{"period_from":"2026-02-27","period_to":"2026-03-05"}', '{"lines":[{"entry_date":"2026-02-27","description":" "}],"recv":[]}')$q$, '23514'), 'uraian kosong ditolak';

  perform public.doc_change_status('PMT', v_id, 'FINAL');
  assert pg_temp.fails(format($q$select public.save_doc('PMT', %L, '{"notes":"x"}')$q$, v_id), '55000'), 'laporan final terkunci';

  -- tarik data otomatis (fungsi hanya boleh dipakai pemegang izin)
  select count(*) into n from public.store_income_invoice_lines('2020-01-01','2099-01-01');
  select count(*) into n from public.store_income_receivables_now();
  perform pg_temp.u(mkt);
  assert pg_temp.fails($q$select * from public.store_income_receivables_now()$q$, '42501'), 'tarik piutang butuh izin';
end $$;
