-- Fase revisi: matriks RBAC sesuai gambar Owner, Owner boleh mengubah dokumen final.
-- Menggantikan izin seed lama untuk peran non-Owner. Owner (superuser) tidak memakai baris role_permissions.

create or replace function public.is_owner() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select r.is_superuser from public.user_profiles p join public.roles r on r.id = p.role_id
                    where p.id = auth.uid() and p.is_active and r.is_active), false)
$$;
revoke all on function public.is_owner() from public, anon;
grant execute on function public.is_owner() to authenticated;

-- Hapus izin lama non-Owner pada modul yang diatur matriks
delete from public.role_permissions rp using public.roles r, public.permissions p
 where rp.role_id = r.id and rp.permission_id = p.id and r.code <> 'OWNER'
   and p.module in ('customer','ro','production_order','packing_list','carcass_weighing','purchase_request','supplier','pricing','purchase_analysis','stock','stock_opname','noncarcass_sale','invoice','report');

create or replace function pg_temp.g(p_role text, p_module text, p_actions text[]) returns void language sql as $f$
  insert into public.role_permissions (role_id, permission_id) select r.id, p.id from public.roles r, public.permissions p
   where r.code = p_role and p.module = p_module and p.action = any(p_actions) on conflict do nothing;
$f$;

select pg_temp.g('MARKETING','customer','{view,create,edit}');
select pg_temp.g('ACCOUNTING','customer','{view}');
select pg_temp.g('MARKETING','ro','{view,create,edit}');
select pg_temp.g('ACCOUNTING','ro','{view}');
select pg_temp.g('PRODUKSI','ro','{view}');
select pg_temp.g('MARKETING','production_order','{view,create,edit}');
select pg_temp.g('ACCOUNTING','production_order','{view}');
select pg_temp.g('PRODUKSI','production_order','{view,edit}');
select pg_temp.g('KASIR','production_order','{view}');
select pg_temp.g('MARKETING','packing_list','{view}');
select pg_temp.g('ACCOUNTING','packing_list','{view}');
select pg_temp.g('PRODUKSI','packing_list','{view,create,edit}');
select pg_temp.g('KASIR','packing_list','{view}');
select pg_temp.g('PURCHASING','carcass_weighing','{view}');
select pg_temp.g('ACCOUNTING','carcass_weighing','{view}');
select pg_temp.g('PRODUKSI','carcass_weighing','{view,create,edit}');
select pg_temp.g('KASIR','carcass_weighing','{view}');
select pg_temp.g('MARKETING','purchase_request','{view,create}');
select pg_temp.g('PURCHASING','purchase_request','{view,create,edit}');
select pg_temp.g('ACCOUNTING','purchase_request','{view}');
select pg_temp.g('PRODUKSI','purchase_request','{view,create}');
select pg_temp.g('KASIR','purchase_request','{view,create}');
select pg_temp.g('PURCHASING','supplier','{view,create,edit}');
select pg_temp.g('ACCOUNTING','supplier','{view}');
select pg_temp.g('MARKETING','pricing','{view}');
select pg_temp.g('PURCHASING','pricing','{view,create,edit}');
select pg_temp.g('ACCOUNTING','pricing','{view}');
select pg_temp.g('PRODUKSI','pricing','{view}');
select pg_temp.g('KASIR','pricing','{view}');
select pg_temp.g('PURCHASING','purchase_analysis','{view,create,edit,export}');
select pg_temp.g('ACCOUNTING','purchase_analysis','{view}');
select pg_temp.g('MARKETING','stock','{view}');
select pg_temp.g('MARKETING','stock_opname','{view}');
select pg_temp.g('PURCHASING','stock','{view}');
select pg_temp.g('PURCHASING','stock_opname','{view}');
select pg_temp.g('ACCOUNTING','stock','{view}');
select pg_temp.g('ACCOUNTING','stock_opname','{view}');
select pg_temp.g('PRODUKSI','stock','{view,create,edit}');
select pg_temp.g('PRODUKSI','stock_opname','{view,create,edit}');
select pg_temp.g('KASIR','stock','{view,create,edit}');
select pg_temp.g('KASIR','stock_opname','{view,create,edit}');
select pg_temp.g('MARKETING','noncarcass_sale','{view}');
select pg_temp.g('ACCOUNTING','noncarcass_sale','{view}');
select pg_temp.g('PRODUKSI','noncarcass_sale','{view}');
select pg_temp.g('KASIR','noncarcass_sale','{view,create,edit}');
select pg_temp.g('PURCHASING','invoice','{view}');
select pg_temp.g('ACCOUNTING','invoice','{view,create,edit,delete,approve,export}');
select pg_temp.g('MARKETING','report','{view}');
select pg_temp.g('PURCHASING','report','{view}');
select pg_temp.g('ACCOUNTING','report','{view,export}');

-- Persetujuan PR hanya Owner (kolom Approve di matriks)
delete from public.role_permissions rp using public.roles r, public.permissions p
 where rp.role_id=r.id and rp.permission_id=p.id and r.code<>'OWNER' and p.action='approve' and p.module='purchase_request';

-- Owner boleh mengubah dokumen berstatus final (kecuali dibatalkan)
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
    if not (v_status = any (r.editable_statuses) or (public.is_owner() and p_type = 'PROD' and v_status <> 'CANCELLED')) then
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
