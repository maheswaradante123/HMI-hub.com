-- Tambah produk cepat dari form RO (hak: membuat RO). Produk tercatat sebagai MANUFACTURE.
create or replace function public.ro_quick_product(p_name text, p_unit_id uuid, p_category_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_name text := btrim(coalesce(p_name,'')); v_code text; v_id uuid; v_i int := 0;
begin
  if not public.has_permission('ro','create') then
    raise exception 'Tidak berhak' using errcode = '42501';
  end if;
  if v_name = '' or length(v_name) > 100 then
    raise exception 'Nama produk tidak valid' using errcode = '22023';
  end if;
  select id into v_id from public.products where lower(name) = lower(v_name);
  if v_id is not null then return v_id; end if;
  v_code := upper(regexp_replace(v_name, '[^A-Za-z0-9]+', '-', 'g'));
  v_code := trim(both '-' from left(v_code, 30));
  if v_code = '' then v_code := 'PRD'; end if;
  while exists (select 1 from public.products where code = case when v_i = 0 then v_code else v_code || '-' || v_i end) loop
    v_i := v_i + 1;
  end loop;
  if v_i > 0 then v_code := v_code || '-' || v_i; end if;
  insert into public.products (code, name, product_type, category_id, unit_id)
  values (v_code, v_name, 'MANUFACTURE', p_category_id, p_unit_id) returning id into v_id;
  return v_id;
end $$;
revoke all on function public.ro_quick_product(text, uuid, uuid) from public, anon;
grant execute on function public.ro_quick_product(text, uuid, uuid) to authenticated;
