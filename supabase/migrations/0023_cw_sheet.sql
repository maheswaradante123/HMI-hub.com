-- HMI Hub - Penimbangan Karkas mengikuti preview: berat hidup dan jenis sapi opsional, nomor CW-001-KODESAPI-IV-26,
-- item diketik bebas dengan kategori (Daging/Tulang/Jeroan/Non-Karkas); item yang belum ada di master dibuat otomatis.

alter table public.carcass_weighings
  alter column cow_type_id drop not null,
  alter column live_weight drop not null;   -- cek live_weight > 0 dan karkas <= hidup tetap berlaku bila diisi

-- Nomor: CW-{urut 3 angka}-{KODE SAPI}-{bulan romawi}-{YY}. Urutan berjalan terus (tidak mulai ulang tiap tahun), melanjutkan jumlah CW yang sudah ada.
create table public.cw_counter (id boolean primary key default true check (id), last_number integer not null);
insert into public.cw_counter (id, last_number) select true, count(*) from public.carcass_weighings;
alter table public.cw_counter enable row level security;
create or replace function public.cw_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_n integer; v_code text;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
begin
  if new.doc_number is not null then return new; end if;
  update public.cw_counter set last_number = last_number + 1 returning last_number into v_n;
  v_code := upper(regexp_replace(coalesce(new.cow_number, ''), '[^A-Za-z0-9]', '', 'g'));
  new.doc_number := format('CW-%s-%s-%s-%s', lpad(v_n::text, 3, '0'), coalesce(nullif(v_code, ''), 'KODE'),
                           v_roman[extract(month from new.weigh_date)::int], to_char(new.weigh_date, 'YY'));
  return new;
end $$;
revoke all on function public.cw_assign_number() from public, anon, authenticated;
drop trigger carcass_weighings_docno on public.carcass_weighings;
create trigger carcass_weighings_docno before insert on public.carcass_weighings
  for each row execute function public.cw_assign_number();

-- Mengubah daftar [{name, cat}] menjadi id master. Nama yang sudah ada dipakai apa adanya (tanpa mengubah kategorinya);
-- nama baru dibuat di master dengan kategori yang dipilih. cat: Daging, Tulang, Jeroan (produk, masuk stok) atau Non-Karkas.
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
        select id into v_unit from public.units where code = 'KG';
        if v_unit is null then raise exception 'Satuan KG belum ada di master' using errcode = '22023'; end if;
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

-- Urutan CW berikutnya (untuk pratinjau nomor di form; nomor resmi dibuat saat disimpan).
create or replace function public.cw_next_seq() returns integer
language sql stable security definer set search_path = public as $$
  select case when public.has_permission('carcass_weighing', 'view') then (select last_number from public.cw_counter where id) + 1 end;
$$;
revoke all on function public.cw_next_seq() from public, anon;
grant execute on function public.cw_next_seq() to authenticated;
