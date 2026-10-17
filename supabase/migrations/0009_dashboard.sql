-- HMI Internal System - Phase 16: ringkasan dashboard.
-- Fungsi berjalan dengan hak pemanggil (RLS tetap berlaku). Angka yang tidak boleh
-- dilihat user dikembalikan null, bukan 0, supaya tidak menyesatkan.
create or replace function public.dashboard_summary()
returns jsonb
language plpgsql stable
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_month date := date_trunc('month', now() at time zone 'Asia/Jakarta')::date;
  out jsonb := '{}'::jsonb;
  v_n numeric; v_m numeric;
begin
  if public.has_permission('stock','view') then
    select count(*) into v_n from public.v_stock_summary where is_low;
    out := out || jsonb_build_object('low_stock', v_n);
  end if;
  if public.has_permission('purchase_request','approve') then
    select count(*) into v_n from public.purchase_requests where status in ('SUBMITTED','UNDER_REVIEW') and deleted_at is null;
    out := out || jsonb_build_object('pr_waiting', v_n);
  end if;
  if public.has_permission('production_order','approve') then
    select count(*) into v_n from public.production_orders where status = 'SUBMITTED' and deleted_at is null;
    out := out || jsonb_build_object('prod_waiting', v_n);
  end if;
  if public.has_permission('ro','view') then
    select count(*) into v_n from public.request_orders where status = 'CONFIRMED' and deleted_at is null;
    out := out || jsonb_build_object('ro_open', v_n);
  end if;
  if public.has_permission('packing_list','view') then
    select count(*) into v_n from public.packing_lists where status = 'PACKED' and deleted_at is null;
    out := out || jsonb_build_object('pl_on_the_way', v_n);
  end if;
  if public.has_permission('invoice','view') then
    select coalesce(sum(outstanding),0), coalesce(sum(outstanding) filter (where days_overdue > 0),0)
      into v_n, v_m from public.v_receivables;
    out := out || jsonb_build_object('receivable_total', v_n, 'receivable_overdue', v_m);
  end if;
  if public.has_permission('crj','view') then
    select coalesce(sum(amount),0) into v_n from public.cash_receipts
     where status = 'POSTED' and deleted_at is null and receipt_date >= v_month and receipt_date <= v_today;
    out := out || jsonb_build_object('cash_in_month', v_n);
  end if;
  if public.has_permission('cpj','view') then
    select coalesce(sum(amount),0) into v_n from public.cash_payments
     where status = 'POSTED' and deleted_at is null and pay_date >= v_month and pay_date <= v_today;
    out := out || jsonb_build_object('cash_out_month', v_n);
  end if;
  return out;
end;
$$;
revoke all on function public.dashboard_summary() from public, anon;
grant execute on function public.dashboard_summary() to authenticated;
