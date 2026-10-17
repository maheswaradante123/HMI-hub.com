-- HMI Internal System - Phase 5: Purchase Request
-- Semua perubahan lewat fungsi (SECURITY DEFINER) yang memeriksa izin dan
-- urutan status. Tabel hanya bisa dibaca langsung oleh user.

-- ---------------------------------------------------------------
-- Penomoran dokumen (dipakai ulang oleh RO, INV, CPJ, dst)
-- ---------------------------------------------------------------
create table public.document_sequences (
  doc_type    text    not null,
  year        integer not null,
  last_number integer not null default 0,
  primary key (doc_type, year)
);
alter table public.document_sequences enable row level security;
-- Tanpa policy dan tanpa grant: hanya fungsi di bawah yang menyentuh tabel ini.

create or replace function public.next_doc_number(p_type text, p_prefix text)
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_year integer := extract(year from (now() at time zone 'Asia/Jakarta'))::integer;
  v_n    integer;
begin
  insert into public.document_sequences as d (doc_type, year, last_number)
  values (p_type, v_year, 1)
  on conflict (doc_type, year) do update set last_number = d.last_number + 1
  returning last_number into v_n;
  return format('%s-%s-%s', p_prefix, v_year, lpad(v_n::text, 4, '0'));
end;
$$;
revoke all on function public.next_doc_number(text, text) from public, anon, authenticated;

create or replace function public.assign_doc_number()
returns trigger
language plpgsql
as $$
begin
  if new.doc_number is null then
    new.doc_number := public.next_doc_number(tg_argv[0], tg_argv[1]);
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------
-- Tabel
-- ---------------------------------------------------------------
create table public.purchase_requests (
  id            uuid primary key default gen_random_uuid(),
  doc_number    text unique,
  request_date  date not null default (now() at time zone 'Asia/Jakarta')::date,
  requester_id  uuid not null references public.user_profiles(id),
  department_id uuid references public.departments(id),
  reason        text not null check (btrim(reason) <> ''),
  priority      text not null default 'NORMAL' check (priority in ('LOW','NORMAL','HIGH')),
  status        text not null default 'DRAFT' check (status in
                 ('DRAFT','SUBMITTED','UNDER_REVIEW','APPROVED','REJECTED','ORDERED','RECEIVED','PAID','CLOSED')),
  decided_by    uuid references public.user_profiles(id),
  decided_at    timestamptz,
  review_note   text,
  created_at    timestamptz not null default now(),
  created_by    uuid references auth.users(id),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references auth.users(id),
  deleted_at    timestamptz
);
create index purchase_requests_status_idx    on public.purchase_requests(status);
create index purchase_requests_requester_idx on public.purchase_requests(requester_id);
create index purchase_requests_date_idx      on public.purchase_requests(request_date);

create table public.pr_items (
  id              uuid primary key default gen_random_uuid(),
  pr_id           uuid not null references public.purchase_requests(id),
  line_no         integer not null,
  product_id      uuid references public.products(id),
  item_name       text not null check (btrim(item_name) <> ''),
  qty             numeric(12,3) not null check (qty > 0),
  unit_id         uuid not null references public.units(id),
  estimated_price numeric(18,2) check (estimated_price >= 0),
  supplier_id     uuid references public.suppliers(id),
  notes           text,
  unique (pr_id, line_no)
);
create index pr_items_pr_idx       on public.pr_items(pr_id);
create index pr_items_product_idx  on public.pr_items(product_id);
create index pr_items_supplier_idx on public.pr_items(supplier_id);

create table public.pr_status_history (
  id          bigint generated always as identity primary key,
  pr_id       uuid not null references public.purchase_requests(id),
  from_status text,
  to_status   text not null,
  note        text,
  changed_by  uuid,
  changed_at  timestamptz not null default now()
);
create index pr_status_history_pr_idx on public.pr_status_history(pr_id);

create trigger purchase_requests_docno before insert on public.purchase_requests
  for each row execute function public.assign_doc_number('PR', 'PR');
create trigger purchase_requests_actor before insert or update on public.purchase_requests
  for each row execute function public.set_actor_columns();

create trigger purchase_requests_audit after insert or update or delete on public.purchase_requests
  for each row execute function public.audit_row_change();
create trigger pr_items_audit after insert or update or delete on public.pr_items
  for each row execute function public.audit_row_change();

-- Riwayat status tidak boleh diubah atau dihapus.
create or replace function public.block_history_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'riwayat tidak boleh diubah atau dihapus';
end;
$$;
create trigger pr_status_history_immutable before update or delete on public.pr_status_history
  for each row execute function public.block_history_mutation();

-- ---------------------------------------------------------------
-- RLS (baca saja; tulis lewat fungsi)
-- ---------------------------------------------------------------
alter table public.purchase_requests  enable row level security;
alter table public.pr_items           enable row level security;
alter table public.pr_status_history  enable row level security;

-- Pemilik PR melihat PR sendiri; yang punya izin purchase_request_all melihat semua.
create policy purchase_requests_select on public.purchase_requests for select to authenticated
  using (
    public.has_permission('purchase_request','view')
    and (requester_id = auth.uid() or public.has_permission('purchase_request_all','view'))
  );

create policy pr_items_select on public.pr_items for select to authenticated
  using (exists (select 1 from public.purchase_requests p where p.id = pr_id));

create policy pr_status_history_select on public.pr_status_history for select to authenticated
  using (exists (select 1 from public.purchase_requests p where p.id = pr_id));

grant select on public.purchase_requests, public.pr_items, public.pr_status_history to authenticated;

-- ---------------------------------------------------------------
-- Fungsi: simpan PR (draft baru atau ubah draft)
-- ---------------------------------------------------------------
create or replace function public.save_purchase_request(
  p_id       uuid,
  p_reason   text,
  p_priority text,
  p_items    jsonb
) returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_id   uuid;
  v_row  public.purchase_requests%rowtype;
  v_item jsonb;
  v_line integer := 0;
begin
  if not public.has_permission('purchase_request','create') then
    raise exception 'Anda tidak memiliki izin membuat Purchase Request' using errcode = '42501';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Isi minimal satu barang' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.purchase_requests (requester_id, department_id, reason, priority)
    select v_uid, up.department_id, p_reason, p_priority
      from public.user_profiles up where up.id = v_uid
    returning id into v_id;
  else
    select * into v_row from public.purchase_requests where id = p_id for update;
    if not found or v_row.deleted_at is not null then
      raise exception 'Purchase Request tidak ditemukan' using errcode = 'P0002';
    end if;
    if v_row.requester_id <> v_uid then
      raise exception 'Hanya pembuat PR yang boleh mengubah drafnya' using errcode = '42501';
    end if;
    if v_row.status <> 'DRAFT' then
      raise exception 'PR yang sudah diajukan tidak bisa diubah' using errcode = '55000';
    end if;
    update public.purchase_requests set reason = p_reason, priority = p_priority where id = p_id;
    v_id := p_id;
    delete from public.pr_items where pr_id = v_id;
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_line := v_line + 1;
    insert into public.pr_items (pr_id, line_no, product_id, item_name, qty, unit_id, estimated_price, notes)
    values (
      v_id, v_line,
      nullif(v_item->>'product_id','')::uuid,
      v_item->>'item_name',
      (v_item->>'qty')::numeric,
      (v_item->>'unit_id')::uuid,
      nullif(v_item->>'estimated_price','')::numeric,
      nullif(v_item->>'notes','')
    );
  end loop;

  if p_id is null then
    insert into public.pr_status_history (pr_id, from_status, to_status, changed_by)
    values (v_id, null, 'DRAFT', v_uid);
  end if;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------
-- Fungsi: ubah status dengan aturan transisi
-- ---------------------------------------------------------------
create or replace function public.pr_change_status(p_id uuid, p_to text, p_note text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_pr  public.purchase_requests%rowtype;
  v_ok  boolean := false;
begin
  select * into v_pr from public.purchase_requests where id = p_id for update;
  if not found or v_pr.deleted_at is not null then
    raise exception 'Purchase Request tidak ditemukan' using errcode = 'P0002';
  end if;

  if v_pr.status = 'DRAFT' and p_to = 'SUBMITTED' then
    if v_pr.requester_id <> v_uid or not public.has_permission('purchase_request','create') then
      raise exception 'Hanya pembuat PR yang boleh mengajukan' using errcode = '42501';
    end if;
    if not exists (select 1 from public.pr_items where pr_id = p_id) then
      raise exception 'PR belum memiliki barang' using errcode = '22023';
    end if;
    v_ok := true;

  elsif v_pr.status in ('SUBMITTED','UNDER_REVIEW') and p_to in ('UNDER_REVIEW','APPROVED','REJECTED')
        and not (v_pr.status = 'UNDER_REVIEW' and p_to = 'UNDER_REVIEW') then
    if not public.has_permission('purchase_request','approve') then
      raise exception 'Anda tidak memiliki izin menyetujui atau menolak PR' using errcode = '42501';
    end if;
    if p_to = 'REJECTED' and btrim(coalesce(p_note,'')) = '' then
      raise exception 'Alasan penolakan wajib diisi' using errcode = '22023';
    end if;
    v_ok := true;

  elsif v_pr.status = 'APPROVED' and p_to = 'ORDERED' then
    if not public.has_permission('purchase_request','edit') then
      raise exception 'Anda tidak memiliki izin memproses pembelian' using errcode = '42501';
    end if;
    v_ok := true;

  elsif v_pr.status = 'ORDERED' and p_to = 'RECEIVED' then
    if not public.has_permission('purchase_request','edit') then
      raise exception 'Anda tidak memiliki izin memproses pembelian' using errcode = '42501';
    end if;
    v_ok := true;
  end if;

  if not v_ok then
    raise exception 'Perpindahan status dari % ke % tidak diizinkan', v_pr.status, p_to using errcode = '55000';
  end if;

  update public.purchase_requests
     set status      = p_to,
         decided_by  = case when p_to in ('APPROVED','REJECTED') then v_uid else decided_by end,
         decided_at  = case when p_to in ('APPROVED','REJECTED') then now() else decided_at end,
         review_note = case when p_to = 'REJECTED' then btrim(p_note) else review_note end
   where id = p_id;

  insert into public.pr_status_history (pr_id, from_status, to_status, note, changed_by)
  values (p_id, v_pr.status, p_to, nullif(btrim(coalesce(p_note,'')), ''), v_uid);
end;
$$;

-- ---------------------------------------------------------------
-- Fungsi: hapus draft (soft delete), hanya pembuat dan hanya DRAFT
-- ---------------------------------------------------------------
create or replace function public.pr_discard(p_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_pr public.purchase_requests%rowtype;
begin
  select * into v_pr from public.purchase_requests where id = p_id for update;
  if not found or v_pr.deleted_at is not null then
    raise exception 'Purchase Request tidak ditemukan' using errcode = 'P0002';
  end if;
  if v_pr.requester_id <> auth.uid() then
    raise exception 'Hanya pembuat PR yang boleh menghapus drafnya' using errcode = '42501';
  end if;
  if v_pr.status <> 'DRAFT' then
    raise exception 'Hanya draf yang bisa dihapus' using errcode = '55000';
  end if;
  update public.purchase_requests set deleted_at = now() where id = p_id;
  insert into public.pr_status_history (pr_id, from_status, to_status, note, changed_by)
  values (p_id, 'DRAFT', 'DRAFT', 'Draf dihapus', auth.uid());
end;
$$;

-- ---------------------------------------------------------------
-- Fungsi: Purchasing mengisi supplier per barang setelah PR disetujui
-- ---------------------------------------------------------------
create or replace function public.pr_set_item_supplier(p_item_id uuid, p_supplier_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_status text;
begin
  if not public.has_permission('purchase_request','edit') then
    raise exception 'Anda tidak memiliki izin memproses pembelian' using errcode = '42501';
  end if;
  select p.status into v_status
    from public.pr_items i join public.purchase_requests p on p.id = i.pr_id
   where i.id = p_item_id and p.deleted_at is null;
  if v_status is null then
    raise exception 'Barang tidak ditemukan' using errcode = 'P0002';
  end if;
  if v_status not in ('APPROVED','ORDERED') then
    raise exception 'Supplier hanya bisa diisi setelah PR disetujui' using errcode = '55000';
  end if;
  update public.pr_items set supplier_id = p_supplier_id where id = p_item_id;
end;
$$;

revoke all on function public.save_purchase_request(uuid,text,text,jsonb) from public, anon;
revoke all on function public.pr_change_status(uuid,text,text) from public, anon;
revoke all on function public.pr_discard(uuid) from public, anon;
revoke all on function public.pr_set_item_supplier(uuid,uuid) from public, anon;
grant execute on function public.save_purchase_request(uuid,text,text,jsonb) to authenticated;
grant execute on function public.pr_change_status(uuid,text,text) to authenticated;
grant execute on function public.pr_discard(uuid) to authenticated;
grant execute on function public.pr_set_item_supplier(uuid,uuid) to authenticated;

-- ---------------------------------------------------------------
-- Daftar nama staff (hanya id, nama, departemen) agar nama pemohon dan
-- penyetuju bisa tampil di dokumen. Tidak membuka data akun lainnya.
-- View berjalan dengan hak pemilik, sengaja melewati RLS user_profiles.
-- ---------------------------------------------------------------
create view public.user_directory as
  select id, full_name, department_id, is_active from public.user_profiles;
revoke all on public.user_directory from public, anon;
grant select on public.user_directory to authenticated;
