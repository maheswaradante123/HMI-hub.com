-- Invoice: kolom sesuai contoh (surat jalan, uang muka, bank, penandatangan), nomor INV-URUT-BULAN-TAHUN.
alter table public.invoices
  add column down_payment     numeric(18,2) not null default 0 check (down_payment >= 0),
  add column delivery_note_no text,
  add column buyer_name       text,
  add column phone            text,
  add column bank_info        text,
  add column signer           text,
  add column use_signature    boolean not null default true;
alter table public.inv_items
  add column description text;

update public.doc_registry set
  header_cols = '{customer_id,pl_id,ro_id,invoice_date,due_date,notes,down_payment,delivery_note_no,buyer_name,phone,bank_info,signer,use_signature}',
  children = '[{"key":"items","table":"inv_items","fk":"inv_id","cols":["product_id","qty","unit_price","description"]}]'
where doc_type = 'INV';

-- Nomor: INV-{urut 3 angka}-{bulan romawi}-{YY}, urut per bulan (tanggal invoice).
create table public.inv_sequences (
  ym          text primary key,
  last_number integer not null default 0
);
alter table public.inv_sequences enable row level security;

create or replace function public.inv_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_n integer;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
begin
  if new.doc_number is not null then return new; end if;
  insert into public.inv_sequences as s (ym, last_number) values (to_char(new.invoice_date, 'YYYYMM'), 1)
  on conflict (ym) do update set last_number = s.last_number + 1
  returning last_number into v_n;
  new.doc_number := format('INV-%s-%s-%s', lpad(v_n::text, 3, '0'), v_roman[extract(month from new.invoice_date)::int], to_char(new.invoice_date, 'YY'));
  return new;
end $$;
revoke all on function public.inv_assign_number() from public, anon, authenticated;
drop trigger invoices_docno on public.invoices;
create trigger invoices_docno before insert on public.invoices
  for each row execute function public.inv_assign_number();

-- Pratinjau nomor berikutnya (tidak menambah urutan).
create or replace function public.inv_next_number(p_date date) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v_n integer;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
begin
  if not public.has_permission('invoice','create') then
    raise exception 'Tidak berhak' using errcode = '42501';
  end if;
  select coalesce(max(last_number), 0) + 1 into v_n from public.inv_sequences where ym = to_char(p_date, 'YYYYMM');
  return format('INV-%s-%s-%s', lpad(v_n::text, 3, '0'), v_roman[extract(month from p_date)::int], to_char(p_date, 'YY'));
end $$;
revoke all on function public.inv_next_number(date) from public, anon;
grant execute on function public.inv_next_number(date) to authenticated;

-- Uang muka dihitung sebagai pembayaran saat invoice diterbitkan.
create or replace function public.inv_before() returns trigger language plpgsql security definer set search_path = public as $$
declare v_term int; v_pl text;
begin
  if tg_op = 'INSERT' or new.pl_id is distinct from old.pl_id then
    if new.pl_id is not null then
      select status into v_pl from public.packing_lists where id = new.pl_id;
      if v_pl is null or v_pl not in ('PACKED','DELIVERED') then
        raise exception 'Invoice hanya bisa dibuat dari Packing List yang sudah dikemas' using errcode = '22023';
      end if;
    end if;
  end if;
  if new.due_date is null then
    select payment_term_days into v_term from public.customers where id = new.customer_id;
    new.due_date := new.invoice_date + coalesce(v_term, 0);
  end if;
  if tg_op = 'UPDATE' and new.status = 'VOID' and old.paid_amount > old.down_payment then
    raise exception 'Invoice sudah ada pembayaran. Batalkan CRJ terkait lebih dulu' using errcode = '55000';
  end if;
  if tg_op = 'UPDATE' and new.status = 'ISSUED' and old.status = 'DRAFT' then
    if not exists (select 1 from public.inv_items where inv_id = new.id) or new.total <= 0 then
      raise exception 'Invoice harus memiliki barang dan total lebih dari 0' using errcode = '22023';
    end if;
    if new.down_payment > new.total then
      raise exception 'Uang muka melebihi total invoice' using errcode = '22023';
    end if;
    new.paid_amount := new.down_payment;
    new.status := case when new.down_payment >= new.total then 'PAID' when new.down_payment > 0 then 'PARTIAL' else 'ISSUED' end;
  end if;
  return new;
end $$;

-- Invoice bersaldo uang muka (PARTIAL) tetap bisa dibatalkan selama belum ada CRJ.
insert into public.doc_rules (doc_type, from_status, to_status, module, action, needs_note, label)
values ('INV','PARTIAL','VOID','invoice','delete',true,'Batalkan invoice');
