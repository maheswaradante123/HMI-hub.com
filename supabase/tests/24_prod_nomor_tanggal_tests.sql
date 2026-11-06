-- Pengujian migrasi 0036: bulan dan tahun nomor Production Order mengikuti tanggal publish.
\set ON_ERROR_STOP on
do $$
declare v_cust uuid; v_ro uuid; v_po uuid;
begin
  select id into v_cust from public.customers limit 1;
  insert into public.request_orders (doc_number, customer_id, order_date, status) values ('RO-TST-901-X-26', v_cust, '2026-10-01', 'CONFIRMED') returning id into v_ro;
  insert into public.production_orders (ro_id, order_date) values (v_ro, '2026-03-15') returning id into v_po;
  assert (select doc_number from public.production_orders where id = v_po) = 'PROD-TST-901-III-26', 'bulan nomor PO mengikuti publish date: ' || (select doc_number from public.production_orders where id = v_po);
  update public.production_orders set status = 'CANCELLED' where id = v_po;
  insert into public.production_orders (ro_id) values (v_ro) returning id into v_po;
  assert (select doc_number from public.production_orders where id = v_po) ~ '^PROD-TST-901-[IVX]+-[0-9]{2}-R2$', 'tanpa publish date: tanggal hari ini, PO pengganti -R2';
  delete from public.po_items where po_id in (select id from public.production_orders where ro_id = v_ro);
  delete from public.production_orders where ro_id = v_ro;
  delete from public.request_orders where id = v_ro;
end $$;
