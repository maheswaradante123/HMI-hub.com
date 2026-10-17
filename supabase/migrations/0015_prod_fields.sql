-- Production Order: kolom tambahan sesuai form baru, nomor dari RO, satu RO hanya satu PO aktif.
alter table public.production_orders
  add column send_note        text,
  add column delivery_address text,
  add column pic              text,
  add column cow_codes        text;
alter table public.po_items
  add column ro_product_id uuid references public.products(id),
  add column cut_type      text,
  add column packaging     text,
  add constraint po_items_packaging_chk check (packaging is null or packaging in ('Vacuum 1 Kg','Vacuum 4 Kg','Tray + Wrap','Wrap + Vacuum 4 Kg'));

update public.doc_registry set
  header_cols = '{ro_id,order_date,needed_date,notes,send_note,delivery_address,pic,cow_codes}',
  children = '[{"key":"items","table":"po_items","fk":"po_id","cols":["product_id","qty","notes","ro_product_id","cut_type","packaging"]}]'
where doc_type = 'PROD';

-- Nomor: PROD-{kode customer}-{urut dari RO}-{bulan romawi hari ini}-{YY}, akhiran -R2, -R3 untuk PO pengganti.
create or replace function public.prod_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_ro text; v_core text; v_n int;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
begin
  if new.doc_number is not null then return new; end if;
  if new.ro_id is not null then
    select doc_number into v_ro from public.request_orders where id = new.ro_id;
    v_core := substring(v_ro from '^RO-(.*-[0-9]{3})-[IVX]+-[0-9]{2}$');
  end if;
  if v_core is null then
    new.doc_number := public.next_doc_number('PROD', 'PROD');
    return new;
  end if;
  select count(*) into v_n from public.production_orders where ro_id = new.ro_id;
  new.doc_number := format('PROD-%s-%s-%s', v_core, v_roman[extract(month from v_today)::int], to_char(v_today, 'YY'))
                    || case when v_n > 0 then '-R' || (v_n + 1) else '' end;
  return new;
end $$;
revoke all on function public.prod_assign_number() from public, anon, authenticated;
drop trigger production_orders_docno on public.production_orders;
create trigger production_orders_docno before insert on public.production_orders
  for each row execute function public.prod_assign_number();

create or replace function public.prod_one_active() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.ro_id is not null and exists (
    select 1 from public.production_orders
    where ro_id = new.ro_id and id <> new.id and deleted_at is null and status not in ('REJECTED','CANCELLED')
  ) then
    raise exception 'RO ini sudah punya Production Order yang aktif' using errcode = '22023';
  end if;
  return new;
end $$;
create trigger production_orders_one_active before insert on public.production_orders
  for each row execute function public.prod_one_active();
