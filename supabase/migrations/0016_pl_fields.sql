-- Packing List: satu baris = satu kemasan (berat net dan gross), seperti contoh Packing_List.pdf.
alter table public.pl_items drop constraint pl_items_pl_id_product_id_key;
alter table public.pl_items
  add column gross_weight numeric(14,3),
  add constraint pl_items_gross_chk check (gross_weight is null or gross_weight >= qty);
alter table public.packing_lists
  add column phone      text,
  add column supervisor text;

update public.doc_registry set
  header_cols = '{po_id,ro_id,customer_id,warehouse_id,pack_date,driver_name,vehicle_plate,notes,phone,supervisor}',
  children = '[{"key":"items","table":"pl_items","fk":"pl_id","cols":["product_id","qty","notes","gross_weight"]}]'
where doc_type = 'PL';

-- Nomor: PL-{urut 3 angka}-{bulan romawi}-{YY}, urut per bulan (tanggal kemas).
create table public.pl_sequences (
  ym          text primary key,
  last_number integer not null default 0
);
alter table public.pl_sequences enable row level security;

create or replace function public.pl_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_ym text; v_n integer;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
begin
  if new.doc_number is not null then return new; end if;
  v_ym := to_char(new.pack_date, 'YYYYMM');
  insert into public.pl_sequences as s (ym, last_number) values (v_ym, 1)
  on conflict (ym) do update set last_number = s.last_number + 1
  returning last_number into v_n;
  new.doc_number := format('PL-%s-%s-%s', lpad(v_n::text, 3, '0'), v_roman[extract(month from new.pack_date)::int], to_char(new.pack_date, 'YY'));
  return new;
end $$;
revoke all on function public.pl_assign_number() from public, anon, authenticated;
drop trigger packing_lists_docno on public.packing_lists;
create trigger packing_lists_docno before insert on public.packing_lists
  for each row execute function public.pl_assign_number();
