-- HMI Internal System - RO: kolom tambahan sesuai form baru + penomoran RO-KODE-URUT-BULAN-TAHUN
alter table public.request_orders
  add column orderer_name     text,
  add column phone            text,
  add column delivery_address text,
  add column delivery_time    text,
  add column payment_method   text,
  add column est_pay_date     date,
  add column delivery_method  text,
  add constraint ro_payment_method_chk check (payment_method is null or payment_method in ('Tempo','Transfer','Cash','QRIS')),
  add constraint ro_delivery_method_chk check (delivery_method is null or delivery_method in ('Delivery','Pick Up di Toko')),
  add constraint ro_delivery_time_chk check (delivery_time is null or delivery_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$');

alter table public.ro_items
  add column cut_type  text,
  add column packaging text,
  add constraint ro_items_packaging_chk check (packaging is null or packaging in ('Vacuum 1 Kg','Vacuum 4 Kg','Tray + Wrap','Wrap + Vacuum 4 Kg'));

update public.doc_registry set
  header_cols = '{customer_id,order_date,delivery_date,notes,orderer_name,phone,delivery_address,delivery_time,payment_method,est_pay_date,delivery_method}',
  children = '[{"key":"items","table":"ro_items","fk":"ro_id","cols":["product_id","qty","unit_price","notes","cut_type","packaging"]}]'
where doc_type = 'RO';

-- Nomor RO: RO-{kode customer}-{urut 3 angka}-{bulan romawi}-{2 angka tahun}, urut per customer per bulan.
create table public.ro_sequences (
  customer_id uuid not null references public.customers(id),
  ym          text not null,
  last_number integer not null default 0,
  primary key (customer_id, ym)
);
alter table public.ro_sequences enable row level security;

create or replace function public.ro_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_code text; v_ym text; v_n integer;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
begin
  if new.doc_number is not null then return new; end if;
  select code into v_code from public.customers where id = new.customer_id;
  v_ym := to_char(new.order_date, 'YYYYMM');
  insert into public.ro_sequences as s (customer_id, ym, last_number) values (new.customer_id, v_ym, 1)
  on conflict (customer_id, ym) do update set last_number = s.last_number + 1
  returning last_number into v_n;
  new.doc_number := format('RO-%s-%s-%s-%s', v_code, lpad(v_n::text, 3, '0'),
    v_roman[extract(month from new.order_date)::int], to_char(new.order_date, 'YY'));
  return new;
end $$;
revoke all on function public.ro_assign_number() from public, anon, authenticated;

drop trigger request_orders_docno on public.request_orders;
create trigger request_orders_docno before insert on public.request_orders
  for each row execute function public.ro_assign_number();
