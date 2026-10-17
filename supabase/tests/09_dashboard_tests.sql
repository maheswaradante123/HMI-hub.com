-- Pengujian Phase 16: dashboard.
\set ON_ERROR_STOP on
create function pg_temp.u(p text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', p, true); set local role authenticated; end $$;
do $$
declare
  own constant text := '00000000-0000-0000-0000-000000000001';
  prd constant text := '00000000-0000-0000-0000-000000000005';
  acc constant text := '00000000-0000-0000-0000-000000000004';
  j jsonb;
begin
  perform pg_temp.u(own);
  j := public.dashboard_summary();
  assert j ? 'low_stock' and j ? 'receivable_total' and j ? 'cash_in_month' and j ? 'cash_out_month', 'owner melihat semua kartu';
  assert (j->>'receivable_total')::numeric = 1272725, 'piutang sisa 1.272.725, dapat ' || (j->>'receivable_total');
  assert (j->>'cash_in_month')::numeric = 1000000, 'kas masuk bulan ini hanya yang diposting dan tidak void';
  perform pg_temp.u(prd);
  j := public.dashboard_summary();
  assert j ? 'low_stock' and not (j ? 'receivable_total') and not (j ? 'cash_out_month'), 'produksi tidak melihat angka keuangan';
  perform pg_temp.u(acc);
  j := public.dashboard_summary();
  assert j ? 'receivable_total' and not (j ? 'pr_waiting'), 'accounting tidak melihat antrean persetujuan';
  raise notice 'SEMUA PENGUJIAN PHASE 16 LULUS';
end $$;
