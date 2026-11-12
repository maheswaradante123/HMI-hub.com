-- HMI Internal System - RO: lampiran PO customer wajib (file PO, atau screenshot WhatsApp bila customer tidak menerbitkan PO).
-- RO baru tidak bisa dibuat tanpa lampiran, dan draf lama tidak bisa dikonfirmasi tanpa lampiran. RO yang sudah berjalan tidak terpengaruh.
alter table public.request_orders
  add column customer_po_no  text,
  add column customer_po_url text;

update public.doc_registry set
  header_cols = '{customer_id,order_date,delivery_date,notes,orderer_name,phone,delivery_address,delivery_time,payment_method,est_pay_date,delivery_method,customer_po_no,customer_po_url}'
where doc_type = 'RO';

create or replace function public.ro_require_customer_po() returns trigger
language plpgsql set search_path = public as $$
begin
  -- Skrip impor arsip dan pengujian boleh melewati aturan ini: select set_config('hmi.po_optional', 'on', false);
  if coalesce(current_setting('hmi.po_optional', true), '') = 'on' then return new; end if;
  if coalesce(btrim(new.customer_po_url), '') <> '' then return new; end if;
  if tg_op = 'INSERT' then
    raise exception 'Lampiran PO customer wajib diunggah sebelum RO dibuat (screenshot WhatsApp pun cukup bila customer tidak menerbitkan PO)' using errcode = '22023';
  end if;
  if old.status = 'DRAFT' and new.status not in ('DRAFT', 'CANCELLED') then
    raise exception 'RO belum bisa dikonfirmasi: lampiran PO customer belum diunggah. Ubah RO ini dan unggah PO atau screenshot WhatsApp-nya' using errcode = '22023';
  end if;
  return new;
end $$;

create trigger request_orders_po_required before insert or update on public.request_orders
  for each row execute function public.ro_require_customer_po();
