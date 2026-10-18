-- HMI Hub - Purchase Request per barang (lembar PR mingguan).
-- Satu lembar PR per minggu (nomor PR-{minggu 3 angka}-{bulan romawi}-{YY}); status dicatat PER BARANG:
-- DRAFT -> SUBMITTED (Purchasing mengajukan) -> APPROVED / REJECTED (Owner) -> ORDERED -> RECEIVED -> CLOSED (saat CPJ direalisasi)
-- CANCELLED bisa dari hampir semua status (kecuali barang sudah masuk jurnal CPJ yang berlaku).
-- Lembar lama (alur per dokumen) tetap ada; statusnya dipindahkan ke barang dan lembarnya tidak bisa diubah per barang.

-- ---------------------------------------------------------------
-- Kolom baru
-- ---------------------------------------------------------------
alter table public.purchase_requests drop constraint purchase_requests_status_check;
alter table public.purchase_requests add constraint purchase_requests_status_check check (status in
  ('OPEN','DRAFT','SUBMITTED','UNDER_REVIEW','APPROVED','REJECTED','ORDERED','RECEIVED','PAID','CLOSED'));

alter table public.pr_items
  add column status       text not null default 'DRAFT' check (status in
                          ('DRAFT','SUBMITTED','APPROVED','REJECTED','ORDERED','RECEIVED','CLOSED','CANCELLED')),
  add column ac           text not null default 'OPR' check (ac in ('OPR','RT','MKT','TOKO')),
  add column code         text not null default 'BP' check (btrim(code) <> ''),
  add column pay_method   text not null default 'tf',
  add column proof        text,
  add column item_date    date not null default (now() at time zone 'Asia/Jakarta')::date,
  add column requester_id uuid references public.user_profiles(id),
  add column unit         text,
  add column decided_by   uuid references public.user_profiles(id),
  add column decided_at   timestamptz,
  add column review_note  text;
alter table public.pr_items alter column unit_id drop not null;

-- Pindahkan data lama: status PR menjadi status barang
update public.pr_items i
   set requester_id = p.requester_id,
       item_date    = p.request_date,
       unit         = (select u.name from public.units u where u.id = i.unit_id),
       status       = case p.status
                        when 'DRAFT' then 'DRAFT'
                        when 'SUBMITTED' then 'SUBMITTED' when 'UNDER_REVIEW' then 'SUBMITTED'
                        when 'APPROVED' then 'APPROVED' when 'REJECTED' then 'REJECTED'
                        when 'ORDERED' then 'ORDERED' when 'RECEIVED' then 'RECEIVED'
                        else 'CLOSED' end
  from public.purchase_requests p where p.id = i.pr_id;
update public.pr_items i set status = 'CANCELLED'
  from public.purchase_requests p where p.id = i.pr_id and p.deleted_at is not null;
alter table public.pr_items alter column requester_id set not null;
create index pr_items_requester_idx on public.pr_items(requester_id);
create index pr_items_status_idx on public.pr_items(status);

alter table public.pr_status_history add column item_id uuid references public.pr_items(id);
create index pr_status_history_item_idx on public.pr_status_history(item_id);

-- ---------------------------------------------------------------
-- Hak lihat: pemilik barang melihat barangnya sendiri; yang punya izin "lihat semua PR" melihat semuanya
-- ---------------------------------------------------------------
drop policy purchase_requests_select on public.purchase_requests;
drop policy pr_items_select on public.pr_items;
drop policy pr_status_history_select on public.pr_status_history;

create policy pr_items_select on public.pr_items for select to authenticated
  using (public.has_permission('purchase_request','view')
         and (requester_id = auth.uid() or public.has_permission('purchase_request_all','view')));
create policy purchase_requests_select on public.purchase_requests for select to authenticated
  using (public.has_permission('purchase_request','view')
         and (requester_id = auth.uid() or public.has_permission('purchase_request_all','view')
              or exists (select 1 from public.pr_items i where i.pr_id = purchase_requests.id and i.requester_id = auth.uid())));
create policy pr_status_history_select on public.pr_status_history for select to authenticated
  using (exists (select 1 from public.purchase_requests p where p.id = pr_id));

-- ---------------------------------------------------------------
-- Fungsi lama (alur per dokumen) diganti
-- ---------------------------------------------------------------
drop function public.save_purchase_request(uuid,text,text,jsonb);
drop function public.pr_change_status(uuid,text,text);
drop function public.pr_discard(uuid);
drop function public.pr_set_item_supplier(uuid,uuid);

-- ---------------------------------------------------------------
-- Nomor lembar mingguan
-- ---------------------------------------------------------------
create or replace function public.pr_sheet_number(p_date date) returns text
language sql immutable as $$
  select format('PR-%s-%s-%s', lpad(public.cpj_week_of(p_date)::text, 3, '0'),
         (array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'])[extract(month from p_date)::int],
         to_char(p_date, 'YY'))
$$;

-- ---------------------------------------------------------------
-- Tambah barang ke lembar minggu itu (dibuat otomatis bila belum ada)
-- Barang baru selalu DRAFT. Tanggal selain hari ini hanya untuk yang berhak memproses (Purchasing / Owner).
-- ---------------------------------------------------------------
create or replace function public.pr_add_items(p_items jsonb, p_date date default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_date  date := coalesce(p_date, v_today);
  v_no    text;
  v_sheet public.purchase_requests%rowtype;
  v_it    jsonb;
  v_line  integer;
  v_id    uuid;
  v_desc  text; v_qty numeric; v_price numeric; v_unit text;
begin
  if not public.has_permission('purchase_request','create') then
    raise exception 'Anda tidak memiliki izin membuat Purchase Request' using errcode = '42501';
  end if;
  if v_date <> v_today and not public.has_permission('purchase_request','edit') then
    raise exception 'Barang hanya bisa ditambahkan ke lembar minggu ini' using errcode = '42501';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Isi minimal satu barang' using errcode = '22023';
  end if;

  v_no := public.pr_sheet_number(v_date);
  perform pg_advisory_xact_lock(hashtext(v_no));
  select * into v_sheet from public.purchase_requests where doc_number = v_no and deleted_at is null;
  if not found then
    insert into public.purchase_requests (doc_number, request_date, requester_id, department_id, reason, status)
    select v_no, v_date, v_uid, up.department_id, 'Lembar PR mingguan', 'OPEN'
      from public.user_profiles up where up.id = v_uid
    returning * into v_sheet;
  elsif v_sheet.status <> 'OPEN' then
    raise exception 'Lembar % memakai alur lama dan tidak bisa ditambah barang', v_no using errcode = '55000';
  end if;

  select coalesce(max(line_no), 0) into v_line from public.pr_items where pr_id = v_sheet.id;
  for v_it in select * from jsonb_array_elements(p_items) loop
    v_desc  := btrim(coalesce(v_it->>'item_name', ''));
    v_qty   := nullif(v_it->>'qty', '')::numeric;
    v_price := coalesce(nullif(v_it->>'price', '')::numeric, 0);
    v_unit  := btrim(coalesce(v_it->>'unit', ''));
    if v_desc = '' then raise exception 'Description wajib diisi' using errcode = '22023'; end if;
    if v_qty is null or v_qty <= 0 then raise exception 'Qty harus lebih dari 0' using errcode = '22023'; end if;
    if v_price < 0 then raise exception 'Harga tidak boleh negatif' using errcode = '22023'; end if;
    if v_unit = '' then raise exception 'Satuan wajib diisi' using errcode = '22023'; end if;
    v_line := v_line + 1;
    insert into public.pr_items (pr_id, line_no, item_name, qty, unit, estimated_price, ac, code, pay_method, item_date, requester_id, status)
    values (v_sheet.id, v_line, v_desc, v_qty, v_unit, v_price,
            coalesce(nullif(v_it->>'ac', ''), 'OPR'), coalesce(nullif(btrim(v_it->>'code'), ''), 'BP'),
            coalesce(nullif(btrim(v_it->>'pay_method'), ''), 'tf'), v_date, v_uid, 'DRAFT')
    returning id into v_id;
    insert into public.pr_status_history (pr_id, item_id, from_status, to_status, changed_by)
    values (v_sheet.id, v_id, null, 'DRAFT', v_uid);
  end loop;
  return v_sheet.id;
end $$;

-- ---------------------------------------------------------------
-- Ubah isian satu barang. Isian utama hanya saat DRAFT (pembuat atau Purchasing/Owner);
-- Pembelian dan bukti boleh diisi pemroses di status apa pun yang masih berjalan.
-- ---------------------------------------------------------------
create or replace function public.pr_update_item(p_id uuid, p_fields jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  i public.pr_items%rowtype;
  v_sheet_status text;
  v_edit boolean := public.has_permission('purchase_request','edit');
  v_main boolean := p_fields ?| array['item_name','qty','unit','price','ac','code','item_date'];
begin
  select * into i from public.pr_items where id = p_id for update;
  if not found then raise exception 'Barang tidak ditemukan' using errcode = 'P0002'; end if;
  select status into v_sheet_status from public.purchase_requests where id = i.pr_id and deleted_at is null;
  if v_sheet_status is null then raise exception 'Barang tidak ditemukan' using errcode = 'P0002'; end if;
  if v_sheet_status <> 'OPEN' then raise exception 'Lembar lama tidak bisa diubah per barang' using errcode = '55000'; end if;

  if v_main then
    if i.status <> 'DRAFT' then raise exception 'Isian barang hanya bisa diubah saat masih Draft' using errcode = '55000'; end if;
    if not ((i.requester_id = v_uid and public.has_permission('purchase_request','create')) or v_edit) then
      raise exception 'Anda tidak boleh mengubah barang ini' using errcode = '42501';
    end if;
  end if;
  if p_fields ?| array['pay_method','proof'] then
    if not (v_edit or (i.status = 'DRAFT' and i.requester_id = v_uid)) then
      raise exception 'Anda tidak memiliki izin memproses pembelian' using errcode = '42501';
    end if;
    if i.status in ('CANCELLED','REJECTED') then
      raise exception 'Barang yang dibatalkan atau ditolak tidak bisa diubah' using errcode = '55000';
    end if;
  end if;

  update public.pr_items set
    item_name       = case when p_fields ? 'item_name' then btrim(p_fields->>'item_name') else item_name end,
    qty             = case when p_fields ? 'qty' then (p_fields->>'qty')::numeric else qty end,
    unit            = case when p_fields ? 'unit' then btrim(p_fields->>'unit') else unit end,
    estimated_price = case when p_fields ? 'price' then coalesce(nullif(p_fields->>'price','')::numeric, 0) else estimated_price end,
    ac              = case when p_fields ? 'ac' then p_fields->>'ac' else ac end,
    code            = case when p_fields ? 'code' then coalesce(nullif(btrim(p_fields->>'code'), ''), 'BP') else code end,
    item_date       = case when p_fields ? 'item_date' then (p_fields->>'item_date')::date else item_date end,
    pay_method      = case when p_fields ? 'pay_method' then coalesce(nullif(btrim(p_fields->>'pay_method'), ''), 'tf') else pay_method end,
    proof           = case when p_fields ? 'proof' then nullif(btrim(p_fields->>'proof'), '') else proof end
   where id = p_id;
end $$;

-- ---------------------------------------------------------------
-- Pindah status beberapa barang sekaligus. Barang yang tidak cocok dilewati; hasilnya jumlah yang berpindah.
-- ---------------------------------------------------------------
create or replace function public.pr_move_items(p_ids uuid[], p_to text, p_note text default null)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_n   integer := 0;
  i     record;
  v_new text;
  v_in_journal boolean;
begin
  if not public.has_permission('purchase_request','view') then
    raise exception 'Anda tidak memiliki izin' using errcode = '42501';
  end if;
  if p_to not in ('SUBMITTED','APPROVED','REJECTED','ORDERED','RECEIVED','CANCELLED') then
    raise exception 'Status tujuan tidak dikenal' using errcode = '22023';
  end if;
  if p_to = 'SUBMITTED' and not public.has_permission('purchase_request','edit') then
    raise exception 'Hanya Purchasing yang boleh mengajukan ke Owner' using errcode = '42501';
  end if;
  if p_to in ('APPROVED','REJECTED') and not public.has_permission('purchase_request','approve') then
    raise exception 'Hanya Owner yang boleh menyetujui atau menolak' using errcode = '42501';
  end if;
  if p_to in ('ORDERED','RECEIVED') and not public.has_permission('purchase_request','edit') then
    raise exception 'Anda tidak memiliki izin memproses pembelian' using errcode = '42501';
  end if;
  if p_to = 'REJECTED' and btrim(coalesce(p_note, '')) = '' then
    raise exception 'Alasan penolakan wajib diisi' using errcode = '22023';
  end if;

  for i in
    select it.*, p.status as sheet_status from public.pr_items it
      join public.purchase_requests p on p.id = it.pr_id and p.deleted_at is null
     where it.id = any(p_ids) order by it.id for update of it
  loop
    continue when i.sheet_status <> 'OPEN';
    continue when not (
      (p_to = 'SUBMITTED' and i.status = 'DRAFT')
      or (p_to in ('APPROVED','REJECTED') and i.status = 'SUBMITTED')
      or (p_to = 'ORDERED' and i.status = 'APPROVED')
      or (p_to = 'RECEIVED' and i.status in ('APPROVED','ORDERED'))
      or (p_to = 'CANCELLED' and i.status in ('DRAFT','SUBMITTED','APPROVED','ORDERED','RECEIVED','REJECTED')));
    if p_to = 'CANCELLED' then
      continue when not (public.has_permission('purchase_request','delete')
                         or (i.status = 'DRAFT' and i.requester_id = v_uid and public.has_permission('purchase_request','create')));
      select exists (select 1 from public.cash_journal_lines l join public.cash_journals j on j.id = l.journal_id
                      where l.pr_item_id = i.id and j.status <> 'VOID' and j.deleted_at is null) into v_in_journal;
      continue when v_in_journal;
    end if;

    v_new := p_to;
    -- barang diterima yang sudah dibayar lewat CPJ yang direalisasi langsung CLOSED
    if p_to = 'RECEIVED' and exists (select 1 from public.cash_journal_lines l join public.cash_journals j on j.id = l.journal_id
                                      where l.pr_item_id = i.id and j.status = 'REALIZED' and j.deleted_at is null) then
      v_new := 'CLOSED';
    end if;

    update public.pr_items set status = v_new,
           decided_by  = case when p_to in ('APPROVED','REJECTED') then v_uid else decided_by end,
           decided_at  = case when p_to in ('APPROVED','REJECTED') then now() else decided_at end,
           review_note = case when p_to = 'REJECTED' then btrim(p_note) else review_note end
     where id = i.id;
    insert into public.pr_status_history (pr_id, item_id, from_status, to_status, note, changed_by)
    values (i.pr_id, i.id, i.status, v_new, nullif(btrim(coalesce(p_note, '')), ''), v_uid);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- Nomor CPJ yang memuat barang (untuk kolom CPJ di lembar PR). Hanya untuk id yang diberikan pemanggil.
create or replace function public.pr_item_journals(p_ids uuid[])
returns table (pr_item_id uuid, journal_number text, journal_status text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_permission('purchase_request','view') then
    raise exception 'Anda tidak memiliki izin' using errcode = '42501';
  end if;
  return query
  select l.pr_item_id, j.doc_number, j.status
    from public.cash_journal_lines l join public.cash_journals j on j.id = l.journal_id and j.status <> 'VOID' and j.deleted_at is null
   where l.pr_item_id = any(p_ids);
end $$;

revoke all on function public.pr_add_items(jsonb, date) from public, anon;
revoke all on function public.pr_update_item(uuid, jsonb) from public, anon;
revoke all on function public.pr_move_items(uuid[], text, text) from public, anon;
revoke all on function public.pr_item_journals(uuid[]) from public, anon;
grant execute on function public.pr_add_items(jsonb, date) to authenticated;
grant execute on function public.pr_update_item(uuid, jsonb) to authenticated;
grant execute on function public.pr_move_items(uuid[], text, text) to authenticated;
grant execute on function public.pr_item_journals(uuid[]) to authenticated;

-- ---------------------------------------------------------------
-- CPJ baru (JCP) membaca status per barang
-- ---------------------------------------------------------------
drop function public.cpj_pullable_pr_items();
create function public.cpj_pullable_pr_items()
returns table (pr_item_id uuid, pr_number text, pr_status text, item_name text, qty numeric, unit text, price numeric, ac text, code text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_permission('cpj_journal','create') and not public.has_permission('cpj_journal','edit') then
    raise exception 'Tidak berhak' using errcode = '42501';
  end if;
  return query
  select i.id, p.doc_number, i.status, i.item_name, i.qty, coalesce(i.unit, u.name)::text, coalesce(i.estimated_price, 0)::numeric, i.ac, i.code
    from public.pr_items i
    join public.purchase_requests p on p.id = i.pr_id and p.deleted_at is null
    left join public.units u on u.id = i.unit_id
   where i.status in ('APPROVED','ORDERED','RECEIVED')
     and not exists (
       select 1 from public.cash_journal_lines l join public.cash_journals j on j.id = l.journal_id and j.status <> 'VOID' and j.deleted_at is null
        where l.pr_item_id = i.id)
   order by p.doc_number, i.line_no;
end $$;
revoke all on function public.cpj_pullable_pr_items() from public, anon;
grant execute on function public.cpj_pullable_pr_items() to authenticated;

-- Realisasi selesai -> barang PR yang sudah diterima menjadi CLOSED. Batal setelah realisasi -> kembali RECEIVED.
create or replace function public.jcp_on_status() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.status = 'REALIZED' and old.status = 'ACC' then
    for r in
      select i.id, i.pr_id from public.cash_journal_lines l
        join public.pr_items i on i.id = l.pr_item_id
       where l.journal_id = new.id and i.status = 'RECEIVED'
    loop
      update public.pr_items set status = 'CLOSED' where id = r.id;
      insert into public.pr_status_history (pr_id, item_id, from_status, to_status, note, changed_by)
      values (r.pr_id, r.id, 'RECEIVED', 'CLOSED', 'Dibayar lewat ' || new.doc_number, auth.uid());
    end loop;
  elsif new.status = 'VOID' and old.status = 'REALIZED' then
    for r in
      select i.id, i.pr_id from public.cash_journal_lines l
        join public.pr_items i on i.id = l.pr_item_id
       where l.journal_id = new.id and i.status = 'CLOSED'
         and not exists (
           select 1 from public.cash_journal_lines l2
             join public.cash_journals j2 on j2.id = l2.journal_id and j2.status = 'REALIZED' and j2.deleted_at is null and j2.id <> new.id
            where l2.pr_item_id = i.id)
    loop
      update public.pr_items set status = 'RECEIVED' where id = r.id;
      insert into public.pr_status_history (pr_id, item_id, from_status, to_status, note, changed_by)
      values (r.pr_id, r.id, 'CLOSED', 'RECEIVED', 'Jurnal ' || new.doc_number || ' dibatalkan', auth.uid());
    end loop;
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------
-- Dashboard: barang PR yang menunggu persetujuan Owner
-- ---------------------------------------------------------------
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
    select count(*) into v_n from public.pr_items i join public.purchase_requests p on p.id = i.pr_id and p.deleted_at is null
     where i.status = 'SUBMITTED';
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

-- ---------------------------------------------------------------
-- Izin: Accounting melihat semua PR (dipakai menyusun CPJ); Purchasing boleh unduh PDF/Excel PR
-- ---------------------------------------------------------------
create or replace function pg_temp.g(p_role text, p_module text, p_actions text[]) returns void language sql as $f$
  insert into public.role_permissions (role_id, permission_id) select r.id, p.id from public.roles r, public.permissions p
   where r.code = p_role and p.module = p_module and p.action = any(p_actions) on conflict do nothing;
$f$;
select pg_temp.g('ACCOUNTING','purchase_request_all','{view}');
select pg_temp.g('PURCHASING','purchase_request','{export}');
select pg_temp.g('ACCOUNTING','purchase_request','{export}');
