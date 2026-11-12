-- HMI Hub - Kwitansi gabungan: satu kwitansi untuk beberapa invoice (pengiriman) satu customer, dipakai saat tukar faktur.
-- Alur: DRAFT -> ISSUED (diterbitkan, daftar invoice terkunci) -> VOID. Nomor: KW-{urut 3 angka}-{bulan romawi}-{YY}, urut per bulan.
-- Jumlah = total sisa tagihan semua invoice yang dipilih (total dikurangi yang sudah dibayar) saat disimpan.

insert into public.permissions (module, action)
select 'kwitansi', a.action from unnest(array['view','create','edit','delete','export']) as a(action)
on conflict (module, action) do nothing;

create or replace function pg_temp.g(p_role text, p_module text, p_actions text[]) returns void language sql as $f$
  insert into public.role_permissions (role_id, permission_id) select r.id, p.id from public.roles r, public.permissions p
   where r.code = p_role and p.module = p_module and p.action = any(p_actions) on conflict do nothing;
$f$;
select pg_temp.g('ACCOUNTING', 'kwitansi', '{view,create,edit,delete,export}');
select pg_temp.g('MARKETING',  'kwitansi', '{view}');

create table public.kwitansi_sequences (
  ym          text primary key,
  last_number integer not null default 0
);
alter table public.kwitansi_sequences enable row level security;

create table public.kwitansi (
  id           uuid primary key default gen_random_uuid(),
  doc_number   text unique,
  customer_id  uuid not null references public.customers(id),
  receipt_date date not null default (now() at time zone 'Asia/Jakarta')::date,
  amount       numeric(18,2) not null default 0 check (amount >= 0),
  signer       text,
  signer_title text,
  notes        text,
  status       text not null default 'DRAFT' check (status in ('DRAFT','ISSUED','VOID')),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id),
  deleted_at timestamptz
);
create index kwitansi_customer_idx on public.kwitansi(customer_id);

create table public.kwitansi_items (
  id          uuid primary key default gen_random_uuid(),
  kwitansi_id uuid not null references public.kwitansi(id),
  line_no     integer not null,
  invoice_id  uuid not null references public.invoices(id),
  unique (kwitansi_id, line_no),
  unique (kwitansi_id, invoice_id)
);
create index kwitansi_items_invoice_idx on public.kwitansi_items(invoice_id);

select public.attach_doc_standard('kwitansi', 'KW', 'KW', 'kwitansi');
select public.attach_child_standard('kwitansi_items', 'kwitansi');

create or replace function public.kw_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_n integer;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
begin
  if new.doc_number is not null then return new; end if;
  insert into public.kwitansi_sequences as s (ym, last_number) values (to_char(new.receipt_date, 'YYYYMM'), 1)
  on conflict (ym) do update set last_number = s.last_number + 1
  returning last_number into v_n;
  new.doc_number := format('KW-%s-%s-%s', lpad(v_n::text, 3, '0'), v_roman[extract(month from new.receipt_date)::int], to_char(new.receipt_date, 'YY'));
  return new;
end $$;
revoke all on function public.kw_assign_number() from public, anon, authenticated;
drop trigger kwitansi_docno on public.kwitansi;
create trigger kwitansi_docno before insert on public.kwitansi
  for each row execute function public.kw_assign_number();

-- Setelah disimpan: invoice harus milik customer yang sama, sudah terbit, belum ada di kwitansi lain; jumlah dihitung ulang.
create or replace function public.kw_after_save(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_cust uuid; v_bad text; v_amount numeric;
begin
  select customer_id into v_cust from public.kwitansi where id = p_id;
  if not exists (select 1 from public.kwitansi_items where kwitansi_id = p_id) then
    raise exception 'Pilih minimal satu invoice untuk kwitansi ini' using errcode = '22023';
  end if;
  select i.doc_number into v_bad
    from public.kwitansi_items k join public.invoices i on i.id = k.invoice_id
   where k.kwitansi_id = p_id and (i.customer_id <> v_cust or i.status in ('DRAFT','VOID') or i.deleted_at is not null)
   limit 1;
  if v_bad is not null then
    raise exception 'Invoice % bukan milik customer ini, belum terbit, atau sudah dibatalkan', v_bad using errcode = '22023';
  end if;
  select i.doc_number into v_bad
    from public.kwitansi_items k
    join public.invoices i on i.id = k.invoice_id
    join public.kwitansi_items o on o.invoice_id = k.invoice_id and o.kwitansi_id <> k.kwitansi_id
    join public.kwitansi w on w.id = o.kwitansi_id and w.status <> 'VOID' and w.deleted_at is null
   where k.kwitansi_id = p_id
   limit 1;
  if v_bad is not null then
    raise exception 'Invoice % sudah tercantum di kwitansi lain', v_bad using errcode = '23505';
  end if;
  select coalesce(sum(i.total - i.paid_amount), 0) into v_amount
    from public.kwitansi_items k join public.invoices i on i.id = k.invoice_id where k.kwitansi_id = p_id;
  if v_amount <= 0 then
    raise exception 'Invoice yang dipilih sudah lunas, tidak ada jumlah yang perlu dikwitansikan' using errcode = '22023';
  end if;
  update public.kwitansi set amount = v_amount where id = p_id;
end $$;
revoke all on function public.kw_after_save(uuid) from public, anon, authenticated;

insert into public.doc_registry (doc_type, table_name, module, header_cols, editable_statuses, children, after_save_fn) values
 ('KW', 'kwitansi', 'kwitansi',
  '{customer_id,receipt_date,signer,signer_title,notes}',
  '{DRAFT}',
  '[{"key":"items","table":"kwitansi_items","fk":"kwitansi_id","cols":["invoice_id"]}]',
  'kw_after_save');
insert into public.doc_rules (doc_type, from_status, to_status, module, action, needs_note, label) values
 ('KW','DRAFT','ISSUED','kwitansi','edit',false,'Terbitkan kwitansi'),
 ('KW','DRAFT','VOID','kwitansi','edit',true,'Batalkan'),
 ('KW','ISSUED','VOID','kwitansi','delete',true,'Batalkan kwitansi');
