-- ============================================================================
-- Migrasi Invoice lama (arsip Google Sheets)
-- DIBUAT OTOMATIS oleh scripts/gen_inv.py — jangan diubah tangan.
-- Jalankan SEKALI di Supabase SQL Editor, SETELAH migrasi 0017 dan 0026
-- (aman diulang: berhenti jika nomor sudah ada; semua-atau-tidak sama sekali).
--
-- Invoice arsip langsung berstatus LUNAS (PAID) atau belum dibayar (ISSUED / PARTIAL bila ada uang muka),
-- berdasarkan NoA (hijau = dibayar) — tanpa membuat CRJ, jadi tidak ada uang masuk yang tercatat ulang.
-- Invoice sample/gratis bernilai Rp0 dan berstatus PAID. Tautan ke Packing List / RO tidak dibuat
-- (dokumen lama tidak memuat nomornya); nomor Surat Jalan tersimpan di kolom "Surat jalan".
-- ============================================================================
do $mig$
declare
  v        jsonb := $json$/*DATA*/$json$;
  c jsonb; p jsonb; r jsonb; it jsonb;
  v_cust   jsonb := '{}'::jsonb;   -- kode customer -> id
  v_prod   jsonb := '{}'::jsonb;   -- nama produk -> id
  v_dup text; v_ids uuid[]; v_id uuid; v_cat uuid; v_unit uuid; v_code text; v_i int; v_ln int; v_pid uuid;
  n_c_new int := 0; n_c_old int := 0; n_p_new int := 0; n_p_old int := 0; n_inv int := 0; n_it int := 0; n_open int := 0;
  s_total numeric := 0; s_open numeric := 0;
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'invoices' and column_name = 'delivery_note_no') then
    raise exception 'Jalankan dulu migrasi 0017 (kolom invoice), lalu ulangi skrip ini';
  end if;
  if not exists (select 1 from public.units where code = 'GRAM') then raise exception 'Jalankan dulu migrasi 0026 (satuan Gram)'; end if;
  select string_agg(doc_number, ', ' order by doc_number) into v_dup from (select doc_number from public.invoices where doc_number in (select e.j->>'no' from jsonb_array_elements(v->'invs') as e(j)) order by doc_number limit 8) d;
  if v_dup is not null then
    raise exception 'Nomor invoice sudah ada: % (dan mungkin lainnya). Skrip ini sudah pernah dijalankan, atau nomor tersebut sudah terpakai oleh invoice baru — dihentikan agar tidak ganda.', v_dup;
  end if;

  -- 1) Pelanggan: pakai yang sudah ada (nama / kode Horeka / pola nama), selain itu dibuat.
  for c in select * from jsonb_array_elements(v->'customers') loop
    select array_agg(id) into v_ids from public.customers
     where lower(name) = lower(c->>'name')
        or (c->>'type' = 'HOREKA' and code = c->>'code')
        or code = c->>'code'
        or lower(name) like any (array(select lower(jsonb_array_elements_text(c->'like'))));
    if coalesce(array_length(v_ids, 1), 0) > 1 then
      raise exception 'Customer % cocok dengan lebih dari satu data di master Pelanggan. Samakan namanya dulu.', c->>'name';
    elsif coalesce(array_length(v_ids, 1), 0) = 1 then
      v_id := v_ids[1]; n_c_old := n_c_old + 1;
    else
      v_code := c->>'code'; v_i := 0;
      while exists (select 1 from public.customers where code = case when v_i = 0 then v_code else v_code || '-' || v_i end) loop v_i := v_i + 1; end loop;
      insert into public.customers (code, name, type, address, phone, payment_term_days)
      values (case when v_i = 0 then v_code else v_code || '-' || v_i end, c->>'name', c->>'type', c->>'address', c->>'phone', (c->>'term')::int)
      returning id into v_id;
      n_c_new := n_c_new + 1;
    end if;
    v_cust := v_cust || jsonb_build_object(c->>'code', v_id);
  end loop;

  -- 2) Produk: cocokkan nama; belum ada → dibuat.
  for p in select * from jsonb_array_elements(v->'products') loop
    select id into v_pid from public.products where lower(name) = lower(p->>'name');
    if v_pid is null then
      v_cat := null;
      if p->>'cat' is not null then
        select id into v_cat from public.product_categories
         where code = case p->>'cat' when 'Tulang' then 'TULANG' when 'Jeroan' then 'JEROHAN' else 'DAGING' end;
        if v_cat is null then
          select id into v_cat from public.product_categories
           where lower(name) = any (case p->>'cat' when 'Tulang' then array['tulang','tulang sapi']
                                                   when 'Jeroan' then array['jerohan','jeroan','jerohan sapi','jeroan sapi']
                                                   else array['daging','daging sapi'] end)
           order by created_at limit 1;
        end if;
        if v_cat is null then
          insert into public.product_categories (code, name)
          values (case p->>'cat' when 'Tulang' then 'TULANG' when 'Jeroan' then 'JEROHAN' else 'DAGING' end, case p->>'cat' when 'Jeroan' then 'Jerohan' else p->>'cat' end)
          returning id into v_cat;
        end if;
      end if;
      select id into v_unit from public.units where code = p->>'unit';
      v_code := trim(both '-' from left(upper(regexp_replace(p->>'name', '[^A-Za-z0-9]+', '-', 'g')), 30)); v_i := 0;
      while exists (select 1 from public.products where code = case when v_i = 0 then v_code else v_code || '-' || v_i end) loop v_i := v_i + 1; end loop;
      insert into public.products (code, name, product_type, category_id, unit_id)
      values (case when v_i = 0 then v_code else v_code || '-' || v_i end, p->>'name', p->>'type', v_cat, v_unit)
      returning id into v_pid;
      n_p_new := n_p_new + 1;
    else n_p_old := n_p_old + 1;
    end if;
    v_prod := v_prod || jsonb_build_object(p->>'name', v_pid);
  end loop;

  -- Harga baris diambil persis dari dokumen (bukan dari daftar harga customer); trigger harga-otomatis dimatikan sebentar.
  alter table public.inv_items disable trigger inv_items_default_price;

  -- 3) Invoice + baris. Status langsung PAID / ISSUED / PARTIAL; tidak ada CRJ yang dibuat.
  for r in select * from jsonb_array_elements(v->'invs') loop
    insert into public.invoices (doc_number, customer_id, invoice_date, due_date, tax_rate, subtotal, tax_amount, total, paid_amount, down_payment,
                                 notes, status, delivery_note_no, buyer_name, phone, bank_info, signer)
    values (r->>'no', (v_cust->>(r->>'c'))::uuid, (r->>'d')::date, coalesce((r->>'due')::date, (r->>'d')::date), 0, (r->>'sub')::numeric, 0, (r->>'total')::numeric,
            (r->>'paid')::numeric, (r->>'dp')::numeric, r->>'notes', r->>'st', r->>'do', r->>'kep', r->>'ph', r->>'bank', 'Ahmad Hunain')
    returning id into v_id;
    v_ln := 0;
    for it in select * from jsonb_array_elements(r->'it') loop
      v_ln := v_ln + 1; n_it := n_it + 1;
      insert into public.inv_items (inv_id, line_no, product_id, qty, unit_price, description)
      values (v_id, v_ln, (v_prod->>(it->>'p'))::uuid, (it->>'q')::numeric, (it->>'pr')::numeric, it->>'n');
    end loop;
    n_inv := n_inv + 1; s_total := s_total + (r->>'total')::numeric;
    if r->>'st' in ('ISSUED','PARTIAL') then n_open := n_open + 1; s_open := s_open + (r->>'total')::numeric - (r->>'paid')::numeric; end if;
  end loop;

  alter table public.inv_items enable trigger inv_items_default_price;

  -- Urutan nomor berikutnya melanjutkan arsip (supaya invoice baru tidak bentrok).
  insert into public.inv_sequences (ym, last_number)
  select to_char(invoice_date, 'YYYYMM'), max((substring(doc_number from '^INV-([0-9]{3})-'))::int)
    from public.invoices
   where doc_number in (select e.j->>'no' from jsonb_array_elements(v->'invs') as e(j)) and doc_number ~ '^INV-[0-9]{3}-[IVX]+-[0-9]{2}$'
     and to_char(invoice_date, 'YY') = substring(doc_number from '-([0-9]{2})$')
   group by to_char(invoice_date, 'YYYYMM')
  on conflict (ym) do update set last_number = greatest(public.inv_sequences.last_number, excluded.last_number);

  raise notice 'Selesai: % invoice (% baris), nilai Rp %, belum dibayar % invoice Rp %. Customer baru % (sudah ada %), produk baru % (sudah ada %).',
    n_inv, n_it, to_char(s_total, 'FM999G999G999G999'), n_open, to_char(s_open, 'FM999G999G999G999'), n_c_new, n_c_old, n_p_new, n_p_old;
end
$mig$;
