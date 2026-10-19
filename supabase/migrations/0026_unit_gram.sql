-- 0026: Satuan Gram untuk stok daging/tulang/jeroan.
-- Stok item berkode satuan GRAM disimpan dan ditampilkan dalam gram (seperti aplikasi lama La Mitra).
-- Dokumen (Penimbangan Karkas, Packing List, Invoice, Analisa Pembelian) tetap dalam kg;
-- saat dokumen menggerakkan stok, jumlahnya dikali 1000 otomatis untuk item bersatuan GRAM.
-- Stock Opname dan Catat Stok sudah memakai satuan stok, jadi langsung gram.
--
-- Syarat: tidak boleh ada mutasi stok lama (dalam kg) pada item daging. Jalankan dulu
-- supabase/data/reset_data_dummy.sql bila masih ada data dummy.

insert into public.units (code, name) values ('GRAM', 'Gram') on conflict do nothing;

-- Pengali dari satuan dokumen (kg) ke satuan stok per item.
create or replace function public.stock_factor(p_product uuid) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select case when u.code = 'GRAM' then 1000::numeric else 1::numeric end
                     from public.products p join public.units u on u.id = p.unit_id where p.id = p_product), 1::numeric);
$$;
revoke all on function public.stock_factor(uuid) from public, anon;
grant execute on function public.stock_factor(uuid) to authenticated;

-- Item potongan daging (MANUFACTURE) pindah ke satuan Gram, hanya bila belum ada stok lama.
do $mig$
declare v_gram uuid;
begin
  select id into v_gram from public.units where code = 'GRAM';
  if exists (select 1 from public.stock_movements m join public.products p on p.id = m.product_id
              where p.product_type = 'MANUFACTURE' and p.unit_id <> v_gram) then
    raise exception 'Masih ada mutasi stok lama dalam kg. Jalankan supabase/data/reset_data_dummy.sql terlebih dahulu, lalu ulangi migrasi ini.';
  end if;
  update public.products set unit_id = v_gram where product_type = 'MANUFACTURE' and unit_id <> v_gram;
end
$mig$;

-- Item baru dari Penimbangan Karkas otomatis bersatuan Gram.
create or replace function public.cw_resolve_items(p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  e jsonb; v_name text; v_cat text; v_pid uuid; v_nid uuid; v_code text; v_i int; v_out jsonb := '[]'::jsonb;
  v_cat_code text; v_cat_id uuid; v_unit uuid;
begin
  if not (public.has_permission('carcass_weighing', 'create') or public.has_permission('carcass_weighing', 'edit')) then
    raise exception 'Anda tidak memiliki izin menyimpan penimbangan' using errcode = '42501';
  end if;
  for e in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    v_name := btrim(coalesce(e->>'name', '')); v_cat := coalesce(e->>'cat', 'Daging'); v_pid := null; v_nid := null;
    if v_name = '' or length(v_name) > 100 then raise exception 'Nama item tidak valid' using errcode = '22023'; end if;
    select id into v_pid from public.products where lower(name) = lower(v_name);
    if v_pid is null then select id into v_nid from public.non_carcass_types where lower(name) = lower(v_name); end if;
    if v_pid is null and v_nid is null then
      v_code := trim(both '-' from left(upper(regexp_replace(v_name, '[^A-Za-z0-9]+', '-', 'g')), 30));
      if v_code = '' then v_code := 'ITEM'; end if;
      v_i := 0;
      if v_cat = 'Non-Karkas' then
        while exists (select 1 from public.non_carcass_types where code = case when v_i = 0 then v_code else v_code || '-' || v_i end) loop v_i := v_i + 1; end loop;
        insert into public.non_carcass_types (code, name) values (case when v_i = 0 then v_code else v_code || '-' || v_i end, v_name) returning id into v_nid;
      else
        v_cat_code := case v_cat when 'Tulang' then 'TULANG' when 'Jeroan' then 'JEROHAN' when 'Daging' then 'DAGING' else null end;
        if v_cat_code is null then raise exception 'Kategori item tidak dikenal' using errcode = '22023'; end if;
        select id into v_cat_id from public.product_categories where code = v_cat_code;
        select id into v_unit from public.units where code = 'GRAM';
        if v_unit is null then raise exception 'Satuan Gram belum ada di master' using errcode = '22023'; end if;
        while exists (select 1 from public.products where code = case when v_i = 0 then v_code else v_code || '-' || v_i end) loop v_i := v_i + 1; end loop;
        insert into public.products (code, name, product_type, category_id, unit_id)
        values (case when v_i = 0 then v_code else v_code || '-' || v_i end, v_name, 'MANUFACTURE', v_cat_id, v_unit) returning id into v_pid;
      end if;
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('product_id', v_pid, 'non_carcass_type_id', v_nid));
  end loop;
  return v_out;
end $$;
revoke all on function public.cw_resolve_items(jsonb) from public, anon;
grant execute on function public.cw_resolve_items(jsonb) to authenticated;

-- Penimbangan karkas menambah stok (kg -> satuan stok item).
create or replace function public.cw_on_status() returns trigger language plpgsql security definer set search_path = public as $$
declare i record; v_meat numeric;
begin
  if new.status = 'FINAL' and old.status = 'DRAFT' then
    select coalesce(sum(weight), 0) into v_meat from public.cw_items where cw_id = new.id and product_id is not null;
    if not exists (select 1 from public.cw_items where cw_id = new.id) then
      raise exception 'Penimbangan belum memiliki hasil potongan' using errcode = '22023';
    end if;
    if v_meat > new.carcass_weight then
      raise exception 'Total berat daging (% kg) melebihi berat karkas (% kg)', v_meat, new.carcass_weight using errcode = '22023';
    end if;
    for i in select * from public.cw_items where cw_id = new.id and product_id is not null loop
      perform public.post_stock(i.product_id, new.warehouse_id, 'IN_PRODUCTION', i.weight * public.stock_factor(i.product_id), null, 'CW', new.id,
                                'Penimbangan karkas ' || new.doc_number, new.weigh_date);
    end loop;
  elsif new.status = 'VOID' and old.status = 'FINAL' then
    if exists (select 1 from public.ap_cows c join public.purchase_analyses a on a.id = c.ap_id
                where c.cw_id = new.id and a.status <> 'VOID' and a.deleted_at is null) then
      raise exception 'Batalkan Analisa Pembelian terkait terlebih dahulu' using errcode = '55000';
    end if;
    for i in select * from public.cw_items where cw_id = new.id and product_id is not null loop
      perform public.post_stock(i.product_id, new.warehouse_id, 'REVERSAL_OUT', -i.weight * public.stock_factor(i.product_id), null, 'CW', new.id,
                                'Batal penimbangan ' || new.doc_number);
    end loop;
  end if;
  return null;
end $$;

-- Packing List mengurangi stok (kg -> satuan stok item).
create or replace function public.pl_on_status() returns trigger language plpgsql security definer set search_path = public as $$
declare i record;
begin
  if new.status = 'PACKED' and old.status = 'DRAFT' then
    if not exists (select 1 from public.pl_items where pl_id = new.id) then
      raise exception 'Packing List belum memiliki barang' using errcode = '22023';
    end if;
    for i in select * from public.pl_items where pl_id = new.id loop
      perform public.post_stock(i.product_id, new.warehouse_id, 'OUT_SALE', -i.qty * public.stock_factor(i.product_id), null, 'PL', new.id, 'Packing list ' || new.doc_number, new.pack_date);
    end loop;
  elsif new.status = 'DELIVERED' and old.status = 'PACKED' then
    update public.packing_lists set delivered_at = now() where id = new.id;
  elsif new.status = 'CANCELLED' and old.status = 'PACKED' then
    for i in select * from public.pl_items where pl_id = new.id loop
      perform public.post_stock(i.product_id, new.warehouse_id, 'REVERSAL_IN', i.qty * public.stock_factor(i.product_id), null, 'PL', new.id, 'Batal packing list ' || new.doc_number);
    end loop;
  end if;
  return null;
end $$;
