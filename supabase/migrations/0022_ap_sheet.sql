-- HMI Hub - Analisa Pembelian mengikuti contoh ANALISA_PEMBELIAN (satu analisa untuk satu atau beberapa ekor sapi).
-- Nomor: {urut 3 angka per tahun}-{SUPPLIER}-{JENIS SAPI}-{bulan romawi}-{YY}, mis. 001-AINUL-BX-IV-26.
-- Perubahan: supplier, jenis sapi, TOP, nomor invoice supplier, banyak sapi per analisa (ap_cows), penjualan non-karkas
-- diketik di analisa (ap_nonk), Lower Side / UpperSide, dan Total Biaya yang boleh diisi manual.

-- ---------------------------------------------------------------
-- Kolom header baru
-- ---------------------------------------------------------------
alter table public.purchase_analyses
  add column supplier_id        uuid references public.suppliers(id),
  add column cow_type_id        uuid references public.cow_types(id),
  add column top_date           date,
  add column supplier_invoice   text,
  add column lower_side         numeric(12,3) check (lower_side is null or lower_side >= 0),
  add column upper_side         numeric(12,3) check (upper_side is null or upper_side >= 0),
  add column manual_total_cost  numeric(18,2) check (manual_total_cost is null or manual_total_cost >= 0),
  alter column cw_id drop not null;   -- analisa lama masih menyimpan cw_id; analisa baru memakai ap_cows
drop index public.purchase_analyses_cw_uq;

-- ---------------------------------------------------------------
-- Sapi yang dianalisa (dari Penimbangan Karkas)
-- ---------------------------------------------------------------
create table public.ap_cows (
  id       uuid primary key default gen_random_uuid(),
  ap_id    uuid not null references public.purchase_analyses(id),
  line_no  integer not null,
  cw_id    uuid not null references public.carcass_weighings(id),
  unique (ap_id, line_no), unique (ap_id, cw_id)
);
create index ap_cows_ap_idx on public.ap_cows(ap_id);
create index ap_cows_cw_idx on public.ap_cows(cw_id);

-- Penjualan non-karkas (Babat, Lemak, Kepala, Kaki, Kulit, ...): diketik di analisa. Berat boleh kosong.
create table public.ap_nonk (
  id         uuid primary key default gen_random_uuid(),
  ap_id      uuid not null references public.purchase_analyses(id),
  line_no    integer not null,
  name       text not null check (btrim(name) <> ''),
  weight     numeric(12,3) check (weight is null or weight >= 0),
  unit_price numeric(18,2) not null default 0 check (unit_price >= 0),
  unique (ap_id, line_no)
);
create index ap_nonk_ap_idx on public.ap_nonk(ap_id);

-- Analisa lama: satu sapi (cw_id) menjadi satu baris ap_cows; supplier dan jenis sapi ikut penimbangan.
insert into public.ap_cows (ap_id, line_no, cw_id) select id, 1, cw_id from public.purchase_analyses where cw_id is not null;
update public.purchase_analyses a set supplier_id = w.supplier_id, cow_type_id = w.cow_type_id
  from public.carcass_weighings w where w.id = a.cw_id;

select public.attach_child_standard('ap_cows', 'purchase_analysis');
select public.attach_child_standard('ap_nonk', 'purchase_analysis');

-- ---------------------------------------------------------------
-- Penomoran
-- ---------------------------------------------------------------
create table public.ap_sequences (yy text primary key, last_number integer not null default 0);
alter table public.ap_sequences enable row level security;
create or replace function public.ap_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_n integer; v_sup text; v_type text;
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
begin
  if new.doc_number is not null then return new; end if;
  select upper(regexp_replace(name, '[^A-Za-z0-9]', '', 'g')) into v_sup from public.suppliers where id = new.supplier_id;
  select upper(regexp_replace(code, '[^A-Za-z0-9]', '', 'g')) into v_type from public.cow_types where id = new.cow_type_id;
  insert into public.ap_sequences as s (yy, last_number) values (to_char(new.analysis_date, 'YY'), 1)
  on conflict (yy) do update set last_number = s.last_number + 1
  returning last_number into v_n;
  new.doc_number := format('%s-%s-%s-%s-%s', lpad(v_n::text, 3, '0'), coalesce(nullif(v_sup, ''), 'SUPPLIER'), coalesce(nullif(v_type, ''), 'SAPI'),
                           v_roman[extract(month from new.analysis_date)::int], to_char(new.analysis_date, 'YY'));
  return new;
end $$;
revoke all on function public.ap_assign_number() from public, anon, authenticated;
drop trigger purchase_analyses_docno on public.purchase_analyses;
create trigger purchase_analyses_docno before insert on public.purchase_analyses
  for each row execute function public.ap_assign_number();

-- ---------------------------------------------------------------
-- Pemeriksaan
-- ---------------------------------------------------------------
create or replace function public.ap_before() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.supplier_id is null and (tg_op = 'INSERT' or old.supplier_id is not null) then
    raise exception 'Supplier wajib diisi' using errcode = '22023';
  end if;
  if new.cow_type_id is null and (tg_op = 'INSERT' or old.cow_type_id is not null) then
    raise exception 'Jenis sapi wajib diisi' using errcode = '22023';
  end if;
  return new;
end $$;

-- Sapi harus sudah final dan tidak boleh dipakai analisa lain yang masih berlaku.
create or replace function public.ap_cows_check() returns trigger language plpgsql security definer set search_path = public as $$
declare v_st text;
begin
  perform pg_advisory_xact_lock(hashtext('ap_cow:' || new.cw_id::text));
  select status into v_st from public.carcass_weighings where id = new.cw_id and deleted_at is null;
  if v_st is distinct from 'FINAL' then
    raise exception 'Analisa hanya bisa dibuat setelah penimbangan karkas selesai (final)' using errcode = '22023';
  end if;
  if exists (select 1 from public.ap_cows c join public.purchase_analyses a on a.id = c.ap_id
              where c.cw_id = new.cw_id and c.ap_id <> new.ap_id and a.status <> 'VOID' and a.deleted_at is null) then
    raise exception 'Sapi ini sudah dipakai di analisa lain' using errcode = '23505';
  end if;
  return new;
end $$;
create trigger ap_cows_check before insert or update of cw_id on public.ap_cows
  for each row execute function public.ap_cows_check();

create or replace function public.ap_on_final() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'FINAL' and old.status = 'DRAFT' then
    if not exists (select 1 from public.ap_cows where ap_id = new.id) then
      raise exception 'Analisa belum memiliki sapi' using errcode = '22023';
    end if;
    if not exists (select 1 from public.ap_items where ap_id = new.id) then
      raise exception 'Analisa belum memiliki item produk' using errcode = '22023';
    end if;
  end if;
  return new;
end $$;

-- Penimbangan final tidak boleh dibatalkan selama masih dipakai analisa yang berlaku.
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
      perform public.post_stock(i.product_id, new.warehouse_id, 'IN_PRODUCTION', i.weight, null, 'CW', new.id,
                                'Penimbangan karkas ' || new.doc_number, new.weigh_date);
    end loop;
  elsif new.status = 'VOID' and old.status = 'FINAL' then
    if exists (select 1 from public.ap_cows c join public.purchase_analyses a on a.id = c.ap_id
                where c.cw_id = new.id and a.status <> 'VOID' and a.deleted_at is null) then
      raise exception 'Batalkan Analisa Pembelian terkait terlebih dahulu' using errcode = '55000';
    end if;
    for i in select * from public.cw_items where cw_id = new.id and product_id is not null loop
      perform public.post_stock(i.product_id, new.warehouse_id, 'REVERSAL_OUT', -i.weight, null, 'CW', new.id,
                                'Batal penimbangan ' || new.doc_number);
    end loop;
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------
-- Hasil analisa
-- karkas % = karkas / hidup; Daging = berat item berkategori Daging; daging % = daging / karkas;
-- harga karkas = harga sapi / karkas; Total Biaya = isian manual, atau harga sapi + biaya operasional.
-- ---------------------------------------------------------------
drop view public.v_purchase_analysis;
create view public.v_purchase_analysis as
select a.id, a.doc_number, a.status, a.analysis_date, a.notes, a.total_purchase,
       a.supplier_id, a.cow_type_id, a.top_date, a.supplier_invoice, a.lower_side, a.upper_side,
       w.cow_number, w.live_weight, w.carcass_weight,
       case when w.live_weight > 0 then round(w.carcass_weight / w.live_weight * 100, 2) end            as carcass_pct,
       coalesce(i.meat_weight, 0)                                                                         as meat_weight,
       case when w.carcass_weight > 0 then round(coalesce(i.meat_weight, 0) / w.carcass_weight * 100, 2) end as meat_pct,
       case when w.carcass_weight > 0 then round(a.total_purchase / w.carcass_weight, 2) end             as carcass_price_per_kg,
       coalesce(i.revenue, 0)                                                                             as revenue,
       coalesce(n.amount, 0)                                                                              as noncarcass_amount,
       coalesce(c.cost_total, 0)                                                                          as cost_total,
       coalesce(a.manual_total_cost, a.total_purchase + coalesce(c.cost_total, 0))                        as total_cost,
       coalesce(i.revenue, 0) + coalesce(n.amount, 0) - coalesce(a.manual_total_cost, a.total_purchase + coalesce(c.cost_total, 0)) as profit
  from public.purchase_analyses a
  left join (select ac.ap_id, string_agg(cw.cow_number, ', ' order by ac.line_no) cow_number, sum(cw.live_weight) live_weight, sum(cw.carcass_weight) carcass_weight
               from public.ap_cows ac join public.carcass_weighings cw on cw.id = ac.cw_id group by ac.ap_id) w on w.ap_id = a.id
  left join (select it.ap_id, sum(it.weight) filter (where pc.code = 'DAGING') meat_weight, sum(it.weight * it.unit_price) revenue
               from public.ap_items it join public.products p on p.id = it.product_id left join public.product_categories pc on pc.id = p.category_id group by it.ap_id) i on i.ap_id = a.id
  left join (select ap_id, sum(amount) cost_total from public.ap_costs group by ap_id) c on c.ap_id = a.id
  left join (select ap_id, sum(coalesce(weight, 0) * unit_price) amount from public.ap_nonk group by ap_id) n on n.ap_id = a.id
 where a.deleted_at is null and public.has_permission('purchase_analysis','view');
revoke all on public.v_purchase_analysis from public, anon;
grant select on public.v_purchase_analysis to authenticated;

-- ---------------------------------------------------------------
-- Registry
-- ---------------------------------------------------------------
update public.doc_registry set
  header_cols = '{analysis_date,supplier_id,cow_type_id,top_date,supplier_invoice,total_purchase,lower_side,upper_side,manual_total_cost,notes}',
  children = '[{"key":"cows","table":"ap_cows","fk":"ap_id","cols":["cw_id"]},{"key":"items","table":"ap_items","fk":"ap_id","cols":["product_id","weight","unit_price","price_source"]},{"key":"nonk","table":"ap_nonk","fk":"ap_id","cols":["name","weight","unit_price"]},{"key":"costs","table":"ap_costs","fk":"ap_id","cols":["cost_type_id","amount","note"]}]'
 where doc_type = 'AP';

-- Urutan berikutnya pada tahun tertentu (untuk pratinjau nomor di form; nomor resmi dibuat saat disimpan).
create or replace function public.ap_next_seq(p_yy text) returns integer
language sql stable security definer set search_path = public as $$
  select case when public.has_permission('purchase_analysis', 'view') then coalesce((select last_number from public.ap_sequences where yy = p_yy), 0) + 1 end;
$$;
revoke all on function public.ap_next_seq(text) from public, anon;
grant execute on function public.ap_next_seq(text) to authenticated;
