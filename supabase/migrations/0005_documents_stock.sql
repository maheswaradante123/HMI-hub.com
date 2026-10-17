-- HMI Internal System - Phase 7: kerangka dokumen + Stok
-- Kerangka dokumen dipakai oleh RO, Production Order, Packing List, Penimbangan,
-- Analisa, Invoice, CRJ, CPJ, Opname: semua tulis lewat save_doc / doc_change_status
-- (SECURITY DEFINER) yang memeriksa izin dan urutan status di database.

-- ---------------------------------------------------------------
-- Riwayat status bersama (hanya tambah, tidak bisa diubah)
-- ---------------------------------------------------------------
create table public.doc_status_history (
  id          bigint generated always as identity primary key,
  doc_type    text not null,
  doc_id      uuid not null,
  from_status text,
  to_status   text not null,
  note        text,
  changed_by  uuid,
  changed_at  timestamptz not null default now()
);
create index doc_status_history_doc_idx on public.doc_status_history(doc_type, doc_id);
create trigger doc_status_history_immutable before update or delete on public.doc_status_history
  for each row execute function public.block_history_mutation();

-- ---------------------------------------------------------------
-- Registry jenis dokumen dan aturan perpindahan status
-- ---------------------------------------------------------------
create table public.doc_registry (
  doc_type          text primary key,
  table_name        text not null,
  module            text not null,
  header_cols       text[] not null,
  fixed             jsonb not null default '{}',
  editable_statuses text[] not null default '{DRAFT}',
  children          jsonb not null default '[]',   -- [{key, table, fk, cols[]}]
  after_save_fn     text
);

create table public.doc_rules (
  doc_type    text not null references public.doc_registry(doc_type),
  from_status text not null,
  to_status   text not null,
  module      text not null,
  action      text not null check (action in ('view','create','edit','delete','approve','export')),
  needs_note  boolean not null default false,
  label       text not null,
  primary key (doc_type, from_status, to_status)
);

alter table public.doc_status_history enable row level security;
alter table public.doc_registry       enable row level security;
alter table public.doc_rules          enable row level security;

create policy doc_registry_select on public.doc_registry for select to authenticated using (true);
create policy doc_rules_select    on public.doc_rules    for select to authenticated using (true);
create policy doc_status_history_select on public.doc_status_history for select to authenticated
  using (public.has_permission((select r.module from public.doc_registry r where r.doc_type = doc_status_history.doc_type), 'view'));
grant select on public.doc_status_history, public.doc_registry, public.doc_rules to authenticated;

-- ---------------------------------------------------------------
-- save_doc: buat atau ubah dokumen (hanya status yang boleh diedit)
-- ---------------------------------------------------------------
create or replace function public.save_doc(p_type text, p_id uuid, p_header jsonb, p_children jsonb default '{}'::jsonb)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  r       public.doc_registry%rowtype;
  v_id    uuid := p_id;
  v_hdr   jsonb;
  v_cols  text;
  v_status text;
  ch      jsonb;
  v_ccols text;
  v_n     integer;
begin
  select * into r from public.doc_registry where doc_type = p_type;
  if not found then
    raise exception 'Jenis dokumen tidak dikenal' using errcode = '22023';
  end if;
  if not public.has_permission(r.module, case when p_id is null then 'create' else 'edit' end) then
    raise exception 'Anda tidak memiliki izin untuk menyimpan dokumen ini' using errcode = '42501';
  end if;

  v_hdr := coalesce(p_header, '{}'::jsonb) || r.fixed;
  select string_agg(quote_ident(c), ',') into v_cols
    from unnest(r.header_cols || array(select jsonb_object_keys(r.fixed))) c where v_hdr ? c;
  if v_cols is null then
    raise exception 'Isian dokumen kosong' using errcode = '22023';
  end if;

  if v_id is null then
    execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1) returning id',
                   r.table_name, v_cols, v_cols, r.table_name)
      into v_id using v_hdr;
  else
    execute format('select status from public.%I where id = $1 and deleted_at is null for update', r.table_name)
      into v_status using v_id;
    if v_status is null then
      raise exception 'Dokumen tidak ditemukan' using errcode = 'P0002';
    end if;
    if not (v_status = any (r.editable_statuses)) then
      raise exception 'Dokumen berstatus % tidak bisa diubah lagi', v_status using errcode = '55000';
    end if;
    execute format('update public.%I set (%s) = (select %s from jsonb_populate_record(null::public.%I, $2)) where id = $1',
                   r.table_name, v_cols, v_cols, r.table_name)
      using v_id, v_hdr;
  end if;

  for ch in select * from jsonb_array_elements(r.children) loop
    if p_children ? (ch->>'key') then
      select string_agg(quote_ident(c), ',') into v_ccols from jsonb_array_elements_text(ch->'cols') c;
      execute format('delete from public.%I where %I = $1', ch->>'table', ch->>'fk') using v_id;
      execute format(
        'insert into public.%I (%I, line_no, %s) select $1, e.ord, %s from jsonb_array_elements($2) with ordinality e(j, ord), lateral jsonb_populate_record(null::public.%I, e.j) p',
        ch->>'table', ch->>'fk', v_ccols,
        (select string_agg('p.' || quote_ident(c), ',') from jsonb_array_elements_text(ch->'cols') c),
        ch->>'table')
        using v_id, p_children->(ch->>'key');
    end if;
  end loop;

  if r.after_save_fn is not null then
    execute format('select public.%I($1)', r.after_save_fn) using v_id;
  end if;

  if p_id is null then
    insert into public.doc_status_history (doc_type, doc_id, from_status, to_status, changed_by)
    values (p_type, v_id, null, 'DRAFT', auth.uid());
  end if;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------
-- doc_change_status: pindah status sesuai doc_rules
-- ---------------------------------------------------------------
create or replace function public.doc_change_status(p_type text, p_id uuid, p_to text, p_note text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  r      public.doc_registry%rowtype;
  v_from text;
  v_rule public.doc_rules%rowtype;
begin
  select * into r from public.doc_registry where doc_type = p_type;
  if not found then
    raise exception 'Jenis dokumen tidak dikenal' using errcode = '22023';
  end if;
  execute format('select status from public.%I where id = $1 and deleted_at is null for update', r.table_name)
    into v_from using p_id;
  if v_from is null then
    raise exception 'Dokumen tidak ditemukan' using errcode = 'P0002';
  end if;

  select * into v_rule from public.doc_rules where doc_type = p_type and from_status = v_from and to_status = p_to;
  if not found then
    raise exception 'Perpindahan status dari % ke % tidak diizinkan', v_from, p_to using errcode = '55000';
  end if;
  if not public.has_permission(v_rule.module, v_rule.action) then
    raise exception 'Anda tidak memiliki izin untuk aksi "%"', v_rule.label using errcode = '42501';
  end if;
  if v_rule.needs_note and btrim(coalesce(p_note, '')) = '' then
    raise exception 'Alasan atau catatan wajib diisi' using errcode = '22023';
  end if;

  perform set_config('hmi.doc_note', coalesce(btrim(p_note), ''), true);
  execute format('update public.%I set status = $2 where id = $1', r.table_name) using p_id, p_to;
  perform set_config('hmi.doc_note', '', true);

  insert into public.doc_status_history (doc_type, doc_id, from_status, to_status, note, changed_by)
  values (p_type, p_id, v_from, p_to, nullif(btrim(coalesce(p_note, '')), ''), auth.uid());
end;
$$;

revoke all on function public.save_doc(text,uuid,jsonb,jsonb) from public, anon;
revoke all on function public.doc_change_status(text,uuid,text,text) from public, anon;
grant execute on function public.save_doc(text,uuid,jsonb,jsonb) to authenticated;
grant execute on function public.doc_change_status(text,uuid,text,text) to authenticated;

-- ---------------------------------------------------------------
-- Stok: buku mutasi (hanya tambah). Saldo = jumlah mutasi.
-- ---------------------------------------------------------------
create table public.stock_movements (
  id            uuid primary key default gen_random_uuid(),
  product_id    uuid not null references public.products(id),
  warehouse_id  uuid not null references public.warehouses(id),
  movement_date date not null default (now() at time zone 'Asia/Jakarta')::date,
  movement_type text not null check (movement_type in
    ('OPENING','IN_PURCHASE','IN_PRODUCTION','OUT_SALE','ADJUST_IN','ADJUST_OUT',
     'OPNAME_IN','OPNAME_OUT','REVERSAL_IN','REVERSAL_OUT')),
  qty           numeric(14,3) not null check (qty <> 0),   -- bertanda: masuk +, keluar -
  unit_cost     numeric(18,2) check (unit_cost >= 0),
  ref_type      text,
  ref_id        uuid,
  note          text,
  created_at    timestamptz not null default now(),
  created_by    uuid references auth.users(id) default auth.uid()
);
create index stock_movements_product_idx on public.stock_movements(product_id, warehouse_id);
create index stock_movements_ref_idx     on public.stock_movements(ref_type, ref_id);
create trigger stock_movements_immutable before update or delete on public.stock_movements
  for each row execute function public.block_history_mutation();

alter table public.stock_movements enable row level security;
create policy stock_movements_select on public.stock_movements for select to authenticated
  using (public.has_permission('stock','view'));
grant select on public.stock_movements to authenticated;

-- Fungsi internal: tidak bisa dipanggil langsung oleh user.
create or replace function public.post_stock(
  p_product uuid, p_wh uuid, p_type text, p_qty numeric, p_cost numeric,
  p_ref_type text, p_ref_id uuid, p_note text, p_date date default null)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_bal  numeric;
  v_name text;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_product::text || p_wh::text, 0));
  if p_qty < 0 then
    select coalesce(sum(qty), 0) into v_bal from public.stock_movements where product_id = p_product and warehouse_id = p_wh;
    if v_bal + p_qty < 0 then
      select name into v_name from public.products where id = p_product;
      raise exception 'Stok % tidak cukup (tersedia %, diminta %)', v_name, v_bal, -p_qty using errcode = '22023';
    end if;
  end if;
  insert into public.stock_movements (product_id, warehouse_id, movement_date, movement_type, qty, unit_cost, ref_type, ref_id, note)
  values (p_product, p_wh, coalesce(p_date, (now() at time zone 'Asia/Jakarta')::date), p_type, p_qty, p_cost, p_ref_type, p_ref_id, p_note);
end;
$$;
revoke all on function public.post_stock(uuid,uuid,text,numeric,numeric,text,uuid,text,date) from public, anon, authenticated;

-- Pencatatan manual oleh user: stok awal, pembelian masuk, penyesuaian.
create or replace function public.record_stock_movement(
  p_product uuid, p_wh uuid, p_type text, p_qty numeric, p_cost numeric, p_note text, p_date date default null)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.has_permission('stock','create') then
    raise exception 'Anda tidak memiliki izin mencatat stok' using errcode = '42501';
  end if;
  if p_type not in ('OPENING','IN_PURCHASE','ADJUST_IN','ADJUST_OUT') then
    raise exception 'Jenis mutasi tidak diizinkan' using errcode = '22023';
  end if;
  if p_qty is null or p_qty <= 0 then
    raise exception 'Jumlah harus lebih dari 0' using errcode = '22023';
  end if;
  if p_type in ('ADJUST_IN','ADJUST_OUT') and btrim(coalesce(p_note,'')) = '' then
    raise exception 'Penyesuaian stok wajib disertai alasan' using errcode = '22023';
  end if;
  if p_type = 'IN_PURCHASE' and p_cost is null then
    raise exception 'Harga beli per satuan wajib diisi untuk pembelian masuk' using errcode = '22023';
  end if;
  if p_date is not null and p_date > (now() at time zone 'Asia/Jakarta')::date then
    raise exception 'Tanggal mutasi tidak boleh di masa depan' using errcode = '22023';
  end if;
  if not exists (select 1 from public.products where id = p_product and is_active) then
    raise exception 'Produk tidak ditemukan atau nonaktif' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.warehouses where id = p_wh and is_active) then
    raise exception 'Gudang tidak ditemukan atau nonaktif' using errcode = 'P0002';
  end if;
  if p_cost is not null and not public.has_permission('pricing_cost','view') then
    raise exception 'Anda tidak memiliki izin mengisi harga beli' using errcode = '42501';
  end if;
  perform public.post_stock(p_product, p_wh, p_type,
    case when p_type = 'ADJUST_OUT' then -p_qty else p_qty end,
    p_cost, 'MANUAL', null, nullif(btrim(coalesce(p_note,'')), ''), p_date);
end;
$$;
revoke all on function public.record_stock_movement(uuid,uuid,text,numeric,numeric,text,date) from public, anon;
grant execute on function public.record_stock_movement(uuid,uuid,text,numeric,numeric,text,date) to authenticated;

-- Saldo per produk per gudang dan ringkasan per produk (stok per item).
create view public.v_stock_balance with (security_invoker = true) as
  select product_id, warehouse_id, sum(qty)::numeric(14,3) as qty
    from public.stock_movements group by product_id, warehouse_id;

create view public.v_stock_summary with (security_invoker = true) as
  select p.id as product_id, p.code, p.name, p.product_type, p.unit_id, p.min_stock,
         coalesce(b.qty, 0)::numeric(14,3) as qty,
         (coalesce(b.qty, 0) < p.min_stock) as is_low
    from public.products p
    left join (select product_id, sum(qty) as qty from public.stock_movements group by product_id) b on b.product_id = p.id
   where p.is_active;
grant select on public.v_stock_balance, public.v_stock_summary to authenticated;

-- Nilai stok memakai harga beli terakhir (pembelian masuk terbaru). Hanya untuk pricing_cost.
create view public.v_stock_value as
  select s.product_id, s.code, s.name, s.qty, l.unit_cost as last_cost,
         case when l.unit_cost is null then null else (s.qty * l.unit_cost)::numeric(18,2) end as value
    from public.v_stock_summary s
    left join lateral (
      select unit_cost from public.stock_movements m
       where m.product_id = s.product_id and m.movement_type = 'IN_PURCHASE' and m.unit_cost is not null
       order by m.movement_date desc, m.created_at desc limit 1) l on true
   where public.has_permission('pricing_cost','view') and public.has_permission('stock','view');
grant select on public.v_stock_value to authenticated;

-- ---------------------------------------------------------------
-- Stock Opname
-- ---------------------------------------------------------------
create table public.stock_opnames (
  id           uuid primary key default gen_random_uuid(),
  doc_number   text unique,
  opname_date  date not null default (now() at time zone 'Asia/Jakarta')::date,
  warehouse_id uuid not null references public.warehouses(id),
  notes        text,
  status       text not null default 'DRAFT' check (status in ('DRAFT','APPROVED','CANCELLED')),
  created_at   timestamptz not null default now(),
  created_by   uuid references auth.users(id),
  updated_at   timestamptz not null default now(),
  updated_by   uuid references auth.users(id),
  deleted_at   timestamptz
);
create table public.so_items (
  id          uuid primary key default gen_random_uuid(),
  opname_id   uuid not null references public.stock_opnames(id),
  line_no     integer not null,
  product_id  uuid not null references public.products(id),
  system_qty  numeric(14,3) not null default 0,
  counted_qty numeric(14,3) not null check (counted_qty >= 0),
  unique (opname_id, line_no),
  unique (opname_id, product_id)
);
create index so_items_opname_idx on public.so_items(opname_id);

create trigger stock_opnames_docno before insert on public.stock_opnames
  for each row execute function public.assign_doc_number('SO', 'SO');
create trigger stock_opnames_actor before insert or update on public.stock_opnames
  for each row execute function public.set_actor_columns();
create trigger stock_opnames_audit after insert or update or delete on public.stock_opnames
  for each row execute function public.audit_row_change();
create trigger so_items_audit after insert or update or delete on public.so_items
  for each row execute function public.audit_row_change();

alter table public.stock_opnames enable row level security;
alter table public.so_items      enable row level security;
create policy stock_opnames_select on public.stock_opnames for select to authenticated
  using (public.has_permission('stock_opname','view'));
create policy so_items_select on public.so_items for select to authenticated
  using (public.has_permission('stock_opname','view'));
grant select on public.stock_opnames, public.so_items to authenticated;

create or replace function public.so_fill_system_qty(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.so_items i
     set system_qty = coalesce((select sum(m.qty) from public.stock_movements m
                                 where m.product_id = i.product_id and m.warehouse_id = o.warehouse_id), 0)
    from public.stock_opnames o
   where o.id = p_id and i.opname_id = o.id;
end;
$$;
revoke all on function public.so_fill_system_qty(uuid) from public, anon, authenticated;

create or replace function public.so_on_status()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  i    record;
  v_bal numeric;
  v_diff numeric;
begin
  if new.status = 'APPROVED' and old.status = 'DRAFT' then
    for i in select * from public.so_items where opname_id = new.id loop
      select coalesce(sum(qty), 0) into v_bal from public.stock_movements
       where product_id = i.product_id and warehouse_id = new.warehouse_id;
      v_diff := i.counted_qty - v_bal;
      update public.so_items set system_qty = v_bal where id = i.id;
      if v_diff <> 0 then
        perform public.post_stock(i.product_id, new.warehouse_id,
          case when v_diff > 0 then 'OPNAME_IN' else 'OPNAME_OUT' end,
          v_diff, null, 'SO', new.id, 'Stock opname ' || new.doc_number, new.opname_date);
      end if;
    end loop;
  end if;
  return new;
end;
$$;
create trigger stock_opnames_status after update of status on public.stock_opnames
  for each row execute function public.so_on_status();

insert into public.doc_registry (doc_type, table_name, module, header_cols, children, after_save_fn) values
 ('SO', 'stock_opnames', 'stock_opname', '{opname_date,warehouse_id,notes}',
  '[{"key":"items","table":"so_items","fk":"opname_id","cols":["product_id","counted_qty"]}]', 'so_fill_system_qty');
insert into public.doc_rules (doc_type, from_status, to_status, module, action, needs_note, label) values
 ('SO','DRAFT','APPROVED','stock_opname','approve',false,'Setujui dan koreksi stok'),
 ('SO','DRAFT','CANCELLED','stock_opname','edit',true,'Batalkan');
