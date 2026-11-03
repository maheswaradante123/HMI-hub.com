-- HMI Hub - CRJ rekap per periode (Cash Receipt Journal) dan QRIS dipecah per bank.
-- CRJ baru (tipe JCR) satu dokumen per periode (biasanya mingguan), barisnya ditarik dari lima sumber:
--   Closing lunas Qurban Cerdas, pemeliharaan Qurban Cerdas (tagihan bulanan lunas), QRIS toko (Mandiri/BRI),
--   penyetoran cash toko (kolom Disetor di Pemasukan Toko), dan tempo Horeka (invoice) + penjualan non-karkas.
-- Tiap baris punya rekening/kas sendiri. Posting mengurangi piutang invoice/non-karkas pada baris yang bersangkutan;
-- baris Qurban, QRIS, dan setoran hanya mencatat uang masuk. CRJ lama (per penerimaan) tetap ada sebagai arsip dan masih bisa dipakai.
-- Nomor: CRJ-{minggu}-{bulan romawi}-{YY}, sama dengan CPJ; dihitung dari tanggal akhir periode.

-- ---------------------------------------------------------------
-- QRIS toko dipecah per bank. Kolom qris tetap menjadi total (dipakai rumus Pemasukan Toko dan cetakan).
-- ---------------------------------------------------------------
alter table public.store_income_lines add column qris_mandiri numeric(18,2), add column qris_bri numeric(18,2);
create or replace function public.store_income_qris_total() returns trigger
language plpgsql as $$
begin
  if new.qris_mandiri is not null or new.qris_bri is not null then
    new.qris := coalesce(new.qris_mandiri, 0) + coalesce(new.qris_bri, 0);
  end if;
  return new;
end $$;
create trigger store_income_lines_qris before insert or update on public.store_income_lines
  for each row execute function public.store_income_qris_total();
update public.doc_registry set children =
  '[{"key":"lines","table":"store_income_lines","fk":"report_id","cols":["entry_date","description","cash","qris","qris_mandiri","qris_bri","debit","grab","tf","deposited","proof","invoice_id"]},
    {"key":"recv","table":"store_income_receivables","fk":"report_id","cols":["name","amount"]}]'::jsonb
 where doc_type = 'PMT';

-- ---------------------------------------------------------------
-- Nomor mingguan bersama untuk CRJ lama dan CRJ baru supaya tidak ada nomor kembar antar tabel.
-- ---------------------------------------------------------------
create or replace function public.crj_next_number(p_date date) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
  v_base  text;
  v_n     integer;
begin
  v_base := format('CRJ-%s-%s-%s', lpad(public.cpj_week_of(p_date)::text, 3, '0'), v_roman[extract(month from p_date)::int], to_char(p_date, 'YY'));
  perform pg_advisory_xact_lock(hashtext(v_base));
  select (select count(*) from public.cash_receipts where doc_number = v_base or doc_number like v_base || '-%')
       + (select count(*) from public.cash_receipt_journals where doc_number = v_base or doc_number like v_base || '-%')
    into v_n;
  return case when v_n = 0 then v_base else v_base || '-' || (v_n + 1) end;
end $$;
revoke all on function public.crj_next_number(date) from public, anon, authenticated;

-- ---------------------------------------------------------------
-- Tabel jurnal
-- ---------------------------------------------------------------
insert into public.permissions (module, action)
select 'crj', a.action from unnest(array['view','create','edit','delete','approve','export']) as a(action)
on conflict (module, action) do nothing;

create table public.cash_receipt_journals (
  id          uuid primary key default gen_random_uuid(),
  doc_number  text unique,
  period_from date not null default (now() at time zone 'Asia/Jakarta')::date,
  period_to   date not null default (now() at time zone 'Asia/Jakarta')::date,
  notes       text,
  status      text not null default 'DRAFT' check (status in ('DRAFT','POSTED','VOID')),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id),
  deleted_at timestamptz,
  constraint crj_journal_period check (period_to >= period_from)
);
create table public.cash_receipt_lines (
  id               uuid primary key default gen_random_uuid(),
  journal_id       uuid not null references public.cash_receipt_journals(id),
  line_no          integer not null,
  source           text not null check (source in ('QURBAN_CLOSING','QURBAN_CARE','QRIS','CASH_DEPOSIT','HOREKA','NONKARKAS','OTHER')),
  trans_date       date not null,
  description      text not null check (btrim(description) <> ''),
  account_id       uuid not null references public.accounts(id),
  amount           numeric(18,2) not null check (amount > 0),
  proof            text,
  invoice_id       uuid references public.invoices(id),
  ncs_id           uuid references public.noncarcass_sales(id),
  qurban_order_id  uuid references public.qurban_orders(id),
  qurban_bill_id   uuid references public.qurban_bills(id),
  src_ref          text,
  unique (journal_id, line_no)
);
create index cash_receipt_lines_journal_idx on public.cash_receipt_lines(journal_id);
create index cash_receipt_lines_invoice_idx on public.cash_receipt_lines(invoice_id) where invoice_id is not null;
create index cash_receipt_lines_order_idx   on public.cash_receipt_lines(qurban_order_id) where qurban_order_id is not null;
create index cash_receipt_lines_bill_idx    on public.cash_receipt_lines(qurban_bill_id) where qurban_bill_id is not null;
create index cash_receipt_lines_ref_idx     on public.cash_receipt_lines(src_ref) where src_ref is not null;

select public.attach_doc_standard('cash_receipt_journals', 'JCR', 'CRJ', 'crj');
select public.attach_child_standard('cash_receipt_lines', 'crj');

create or replace function public.crj_journal_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.doc_number is not null then return new; end if;
  new.doc_number := public.crj_next_number(new.period_to);
  return new;
end $$;
revoke all on function public.crj_journal_assign_number() from public, anon, authenticated;
drop trigger cash_receipt_journals_docno on public.cash_receipt_journals;
create trigger cash_receipt_journals_docno before insert on public.cash_receipt_journals
  for each row execute function public.crj_journal_assign_number();

-- CRJ lama ikut memakai penghitung bersama.
create or replace function public.crj_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.doc_number is not null then return new; end if;
  new.doc_number := public.crj_next_number(new.receipt_date);
  return new;
end $$;

-- Baris: bersihkan isian, dan pastikan rujukan sesuai sumbernya.
create or replace function public.crj_line_check() returns trigger
language plpgsql as $$
begin
  new.proof   := nullif(btrim(coalesce(new.proof, '')), '');
  new.src_ref := nullif(btrim(coalesce(new.src_ref, '')), '');
  if num_nonnulls(new.invoice_id, new.ncs_id, new.qurban_order_id, new.qurban_bill_id) > 1 then
    raise exception 'Satu baris hanya boleh merujuk satu dokumen sumber' using errcode = '22023';
  end if;
  if new.source = 'HOREKA' and new.invoice_id is null then
    raise exception 'Baris tempo Horeka harus memilih invoice' using errcode = '22023';
  elsif new.source = 'NONKARKAS' and new.ncs_id is null then
    raise exception 'Baris non-karkas harus memilih penjualan non-karkas' using errcode = '22023';
  elsif new.source = 'QURBAN_CLOSING' and new.qurban_order_id is null then
    raise exception 'Baris closing Qurban harus merujuk pesanan Qurban' using errcode = '22023';
  elsif new.source = 'QURBAN_CARE' and new.qurban_bill_id is null then
    raise exception 'Baris pemeliharaan Qurban harus merujuk tagihan bulanan' using errcode = '22023';
  elsif new.source in ('QRIS','CASH_DEPOSIT') and new.src_ref is null then
    raise exception 'Baris QRIS dan setoran cash harus ditarik dari Pemasukan Toko' using errcode = '22023';
  end if;
  if new.source <> 'HOREKA' and new.invoice_id is not null then raise exception 'Invoice hanya untuk baris tempo Horeka' using errcode = '22023'; end if;
  if new.source <> 'NONKARKAS' and new.ncs_id is not null then raise exception 'Penjualan non-karkas hanya untuk baris non-karkas' using errcode = '22023'; end if;
  return new;
end $$;
create trigger cash_receipt_lines_check before insert or update on public.cash_receipt_lines
  for each row execute function public.crj_line_check();

-- Setelah simpan: satu pesanan/tagihan Qurban atau satu angka Pemasukan Toko hanya boleh ada di satu jurnal yang masih berlaku.
create or replace function public.crj_after_save(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_dup text;
begin
  select j.doc_number into v_dup
    from public.cash_receipt_lines l
    join public.cash_receipt_lines o on o.journal_id <> l.journal_id
         and ((l.qurban_order_id is not null and o.qurban_order_id = l.qurban_order_id)
           or (l.qurban_bill_id  is not null and o.qurban_bill_id  = l.qurban_bill_id)
           or (l.src_ref is not null and o.src_ref = l.src_ref and o.source = l.source))
    join public.cash_receipt_journals j on j.id = o.journal_id and j.status <> 'VOID' and j.deleted_at is null
   where l.journal_id = p_id
   limit 1;
  if v_dup is not null then
    raise exception 'Ada baris yang sudah tercatat di CRJ %', v_dup using errcode = '23505';
  end if;
  if exists (select 1 from public.cash_receipt_lines l where l.journal_id = p_id group by l.qurban_order_id having l.qurban_order_id is not null and count(*) > 1)
     or exists (select 1 from public.cash_receipt_lines l where l.journal_id = p_id group by l.qurban_bill_id having l.qurban_bill_id is not null and count(*) > 1)
     or exists (select 1 from public.cash_receipt_lines l where l.journal_id = p_id group by l.source, l.src_ref having l.src_ref is not null and count(*) > 1) then
    raise exception 'Baris yang sama muncul dua kali dalam jurnal ini' using errcode = '23505';
  end if;
end $$;
revoke all on function public.crj_after_save(uuid) from public, anon, authenticated;

-- Posting: periksa baris, kurangi piutang invoice/non-karkas. Batal posting mengembalikannya.
create or replace function public.crj_journal_apply(p_id uuid, p_sign integer) returns void
language plpgsql security definer set search_path = public as $$
declare a record; v_inv public.invoices%rowtype; v_ncs public.noncarcass_sales%rowtype; v_new numeric;
begin
  for a in select * from public.cash_receipt_lines where journal_id = p_id and (invoice_id is not null or ncs_id is not null) order by line_no loop
    if a.invoice_id is not null then
      select * into v_inv from public.invoices where id = a.invoice_id for update;
      v_new := v_inv.paid_amount + p_sign * a.amount;
      if p_sign > 0 then
        if v_inv.status not in ('ISSUED','PARTIAL') then
          raise exception 'Invoice % tidak dalam status yang bisa dibayar', v_inv.doc_number using errcode = '22023';
        end if;
        if v_new > v_inv.total then
          raise exception 'Pembayaran melebihi sisa tagihan invoice % (sisa %)', v_inv.doc_number, v_inv.total - v_inv.paid_amount using errcode = '22023';
        end if;
      elsif v_new < 0 then
        raise exception 'Saldo invoice % tidak konsisten', v_inv.doc_number using errcode = '55000';
      end if;
      update public.invoices
         set paid_amount = v_new,
             status = case when v_new >= total then 'PAID' when v_new > 0 then 'PARTIAL' else 'ISSUED' end
       where id = v_inv.id;
    else
      select * into v_ncs from public.noncarcass_sales where id = a.ncs_id for update;
      v_new := v_ncs.paid_amount + p_sign * a.amount;
      if p_sign > 0 then
        if v_ncs.status <> 'CONFIRMED' then
          raise exception 'Penjualan non-karkas % tidak dalam status yang bisa dibayar', v_ncs.doc_number using errcode = '22023';
        end if;
        if v_new > v_ncs.total_amount then
          raise exception 'Pembayaran melebihi tagihan penjualan non-karkas %', v_ncs.doc_number using errcode = '22023';
        end if;
      elsif v_new < 0 then
        raise exception 'Saldo penjualan non-karkas % tidak konsisten', v_ncs.doc_number using errcode = '55000';
      end if;
      update public.noncarcass_sales
         set paid_amount = v_new,
             status = case when v_new >= total_amount then 'PAID' else 'CONFIRMED' end
       where id = v_ncs.id;
    end if;
  end loop;
end $$;
revoke all on function public.crj_journal_apply(uuid, integer) from public, anon, authenticated;

create or replace function public.crj_journal_on_status() returns trigger
language plpgsql security definer set search_path = public as $$
declare x record;
begin
  if new.status = 'POSTED' and old.status = 'DRAFT' then
    if not exists (select 1 from public.cash_receipt_lines where journal_id = new.id) then
      raise exception 'Isi minimal satu baris sebelum diposting' using errcode = '22023';
    end if;
    if exists (select 1 from public.cash_receipt_lines l join public.accounts a on a.id = l.account_id where l.journal_id = new.id and not a.is_active) then
      raise exception 'Ada baris dengan rekening/kas nonaktif' using errcode = '22023';
    end if;
    for x in select l.line_no, o.status from public.cash_receipt_lines l join public.qurban_orders o on o.id = l.qurban_order_id where l.journal_id = new.id loop
      if x.status <> 'PAID' then raise exception 'Baris %: pesanan Qurban belum berstatus Lunas', x.line_no using errcode = '22023'; end if;
    end loop;
    for x in select l.line_no, b.status from public.cash_receipt_lines l join public.qurban_bills b on b.id = l.qurban_bill_id where l.journal_id = new.id loop
      if x.status <> 'PAID' then raise exception 'Baris %: tagihan pemeliharaan Qurban belum berstatus Lunas', x.line_no using errcode = '22023'; end if;
    end loop;
    perform public.crj_journal_apply(new.id, 1);
  elsif new.status = 'VOID' and old.status = 'POSTED' then
    perform public.crj_journal_apply(new.id, -1);
  end if;
  return null;
end $$;
revoke all on function public.crj_journal_on_status() from public, anon, authenticated;
create trigger cash_receipt_journals_status after update of status on public.cash_receipt_journals
  for each row execute function public.crj_journal_on_status();

insert into public.doc_registry (doc_type, table_name, module, header_cols, children, after_save_fn) values
 ('JCR','cash_receipt_journals','crj','{period_from,period_to,notes}',
  '[{"key":"lines","table":"cash_receipt_lines","fk":"journal_id","cols":["source","trans_date","description","account_id","amount","proof","invoice_id","ncs_id","qurban_order_id","qurban_bill_id","src_ref"]}]',
  'crj_after_save');
insert into public.doc_rules (doc_type, from_status, to_status, module, action, needs_note, label) values
 ('JCR','DRAFT','POSTED','crj','edit',false,'Posting penerimaan'),
 ('JCR','DRAFT','VOID','crj','edit',true,'Batalkan'),
 ('JCR','POSTED','VOID','crj','delete',true,'Batalkan posting');

-- ---------------------------------------------------------------
-- Tarik baris dari sumber. Mengembalikan kandidat yang belum ada di CRJ lain yang masih berlaku.
--   QURBAN_CLOSING : pesanan Qurban Lunas, tanggal lunas dalam periode (jumlah = sisa bayar invoice)
--   QURBAN_CARE    : tagihan pemeliharaan bulanan Lunas, tanggal lunas dalam periode
--   QRIS           : Pemasukan Toko, kolom QRIS Mandiri dan QRIS BRI per tanggal (rekening bawaan dicari dari namanya)
--   CASH_DEPOSIT   : Pemasukan Toko, kolom Disetor per tanggal (rekening dipilih saat membuat CRJ)
--   HOREKA         : invoice ISSUED/PARTIAL yang masih ada sisa tagihan (tidak terbatas periode)
--   NONKARKAS      : penjualan non-karkas CONFIRMED yang masih ada sisa
-- ---------------------------------------------------------------
create or replace function public.crj_pull(p_source text, p_from date, p_to date)
returns table (source text, ref_id uuid, src_ref text, trans_date date, description text, amount numeric, account_id uuid)
language plpgsql stable security definer set search_path = public as $$
declare v_mandiri uuid; v_bri uuid;
begin
  if not public.has_permission('crj','create') and not public.has_permission('crj','edit') then
    raise exception 'Tidak berhak' using errcode = '42501';
  end if;
  if p_source not in ('QURBAN_CLOSING','QURBAN_CARE','QRIS','CASH_DEPOSIT','HOREKA','NONKARKAS') then
    raise exception 'Sumber tidak dikenal' using errcode = '22023';
  end if;

  if p_source = 'QURBAN_CLOSING' then
    return query
    select 'QURBAN_CLOSING'::text, o.id, null::text, ((coalesce(o.paid_at, o.inv_date::timestamptz)) at time zone 'Asia/Jakarta')::date,
           format('Closing lunas Qurban %s · %s (%s)', o.cow_no, o.customer_nick, coalesce(o.inv_no, o.pro_no, '-')),
           o.due_amount::numeric, null::uuid
      from public.v_qurban_orders o
     where o.status = 'PAID' and o.due_amount > 0
       and ((coalesce(o.paid_at, o.inv_date::timestamptz)) at time zone 'Asia/Jakarta')::date between p_from and p_to
       and not exists (select 1 from public.cash_receipt_lines l join public.cash_receipt_journals j on j.id = l.journal_id and j.status <> 'VOID' and j.deleted_at is null where l.qurban_order_id = o.id)
     order by 4, o.cow_no;

  elsif p_source = 'QURBAN_CARE' then
    return query
    select 'QURBAN_CARE'::text, b.id, null::text, ((coalesce(b.paid_at, b.bill_date::timestamptz)) at time zone 'Asia/Jakarta')::date,
           format('Pemeliharaan Qurban %s · %s · %s (%s)', o.cow_no, o.customer_nick, b.ym, b.bill_no),
           (b.days * b.rate)::numeric, null::uuid
      from public.qurban_bills b join public.qurban_orders o on o.id = b.order_id and o.deleted_at is null
     where b.status = 'PAID' and b.days * b.rate > 0
       and ((coalesce(b.paid_at, b.bill_date::timestamptz)) at time zone 'Asia/Jakarta')::date between p_from and p_to
       and not exists (select 1 from public.cash_receipt_lines l join public.cash_receipt_journals j on j.id = l.journal_id and j.status <> 'VOID' and j.deleted_at is null where l.qurban_bill_id = b.id)
     order by 4, o.cow_no, b.ym;

  elsif p_source = 'QRIS' then
    select a.id into v_mandiri from public.accounts a where a.is_active and a.name ilike '%mandiri%' order by a.name limit 1;
    select a.id into v_bri     from public.accounts a where a.is_active and a.name ilike '%bri%'     order by a.name limit 1;
    return query
    select 'QRIS'::text, null::uuid, (r.doc_number || '|' || x.entry_date || '|' || x.bank), x.entry_date,
           format('QRIS %s toko (%s)', case x.bank when 'MANDIRI' then 'Mandiri' else 'BRI' end, r.doc_number),
           x.amt, case x.bank when 'MANDIRI' then v_mandiri else v_bri end
      from (
        select l.report_id, l.entry_date, 'MANDIRI'::text as bank, sum(l.qris_mandiri) as amt from public.store_income_lines l where l.qris_mandiri > 0 group by l.report_id, l.entry_date
        union all
        select l.report_id, l.entry_date, 'BRI'::text, sum(l.qris_bri) from public.store_income_lines l where l.qris_bri > 0 group by l.report_id, l.entry_date
      ) x
      join public.store_income_reports r on r.id = x.report_id and r.deleted_at is null and r.status <> 'VOID'
     where x.entry_date between p_from and p_to
       and not exists (select 1 from public.cash_receipt_lines l join public.cash_receipt_journals j on j.id = l.journal_id and j.status <> 'VOID' and j.deleted_at is null
                        where l.source = 'QRIS' and l.src_ref = (r.doc_number || '|' || x.entry_date || '|' || x.bank))
     order by 4, 5;

  elsif p_source = 'CASH_DEPOSIT' then
    return query
    select 'CASH_DEPOSIT'::text, null::uuid, (r.doc_number || '|' || x.entry_date || '|SETOR'), x.entry_date,
           format('Penyetoran cash toko (%s)', r.doc_number), x.amt, null::uuid
      from (select l.report_id, l.entry_date, sum(l.deposited) as amt from public.store_income_lines l where l.deposited > 0 group by l.report_id, l.entry_date) x
      join public.store_income_reports r on r.id = x.report_id and r.deleted_at is null and r.status <> 'VOID'
     where x.entry_date between p_from and p_to
       and not exists (select 1 from public.cash_receipt_lines l join public.cash_receipt_journals j on j.id = l.journal_id and j.status <> 'VOID' and j.deleted_at is null
                        where l.source = 'CASH_DEPOSIT' and l.src_ref = (r.doc_number || '|' || x.entry_date || '|SETOR'))
     order by 4;

  elsif p_source = 'HOREKA' then
    return query
    select 'HOREKA'::text, i.id, null::text, p_to,
           format('Pembayaran invoice %s · %s (jatuh tempo %s)', i.doc_number, c.name, coalesce(to_char(i.due_date, 'DD-MM-YYYY'), '-')),
           (i.total - i.paid_amount)::numeric, null::uuid
      from public.invoices i join public.customers c on c.id = i.customer_id
     where i.status in ('ISSUED','PARTIAL') and i.deleted_at is null and i.total - i.paid_amount > 0
       and not exists (select 1 from public.cash_receipt_lines l join public.cash_receipt_journals j on j.id = l.journal_id and j.status = 'DRAFT' and j.deleted_at is null where l.invoice_id = i.id)
     order by i.due_date nulls last, i.doc_number;

  else
    return query
    select 'NONKARKAS'::text, n.id, null::text, p_to,
           format('Pembayaran non-karkas %s · %s', n.doc_number, c.name),
           (n.total_amount - n.paid_amount)::numeric, null::uuid
      from public.noncarcass_sales n join public.customers c on c.id = n.customer_id
     where n.status = 'CONFIRMED' and n.deleted_at is null and n.total_amount - n.paid_amount > 0
       and not exists (select 1 from public.cash_receipt_lines l join public.cash_receipt_journals j on j.id = l.journal_id and j.status = 'DRAFT' and j.deleted_at is null where l.ncs_id = n.id)
     order by n.doc_number;
  end if;
end $$;
revoke all on function public.crj_pull(text, date, date) from public, anon;
grant execute on function public.crj_pull(text, date, date) to authenticated;

-- Pemasukan Toko menarik pembayaran invoice dari CRJ lama dan baris tempo Horeka CRJ baru yang sudah diposting.
create or replace function public.store_income_invoice_lines(p_from date, p_to date)
returns table (entry_date date, description text, tf numeric, invoice_id uuid)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_permission('store_income','create') and not public.has_permission('store_income','edit') then
    raise exception 'Tidak berhak' using errcode = '42501';
  end if;
  return query
  select d.entry_date, d.description, d.tf, d.invoice_id from (
    select r.receipt_date as entry_date, 'Pemasukan ' || i.doc_number as description, sum(a.amount) as tf, i.id as invoice_id
      from public.cash_receipts r
      join public.crj_allocations a on a.crj_id = r.id and a.invoice_id is not null
      join public.invoices i on i.id = a.invoice_id
     where r.status = 'POSTED' and r.deleted_at is null and r.receipt_date between p_from and p_to
     group by r.receipt_date, i.doc_number, i.id
    union all
    select l.trans_date, 'Pemasukan ' || i.doc_number, sum(l.amount), i.id
      from public.cash_receipt_lines l
      join public.cash_receipt_journals j on j.id = l.journal_id and j.status = 'POSTED' and j.deleted_at is null
      join public.invoices i on i.id = l.invoice_id
     where l.trans_date between p_from and p_to
     group by l.trans_date, i.doc_number, i.id
    union all
    select i.invoice_date, 'Pemasukan ' || i.doc_number || ' (uang muka)', i.down_payment, i.id
      from public.invoices i
     where i.down_payment > 0 and i.status <> 'VOID' and i.status <> 'DRAFT' and i.deleted_at is null
       and i.invoice_date between p_from and p_to
  ) d order by d.entry_date, d.description;
end $$;

-- Laporan kas masuk dari CRJ baru (hanya jurnal yang sudah diposting).
create view public.v_cash_receipt_lines with (security_invoker = true) as
select l.id, j.doc_number, l.line_no, l.trans_date,
       case l.source when 'QURBAN_CLOSING' then 'Closing lunas Qurban' when 'QURBAN_CARE' then 'Pemeliharaan Qurban' when 'QRIS' then 'QRIS toko'
                     when 'CASH_DEPOSIT' then 'Penyetoran cash toko' when 'HOREKA' then 'Tempo Horeka' when 'NONKARKAS' then 'Non-karkas' else 'Lainnya' end as source_label,
       l.description, a.name as account_name, l.amount, l.proof
  from public.cash_receipt_lines l
  join public.cash_receipt_journals j on j.id = l.journal_id and j.status = 'POSTED' and j.deleted_at is null
  join public.accounts a on a.id = l.account_id;
grant select on public.v_cash_receipt_lines to authenticated;

-- Dashboard: kas masuk bulan ini ikut menghitung CRJ baru.
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
    select coalesce((select sum(amount) from public.cash_receipts
                      where status = 'POSTED' and deleted_at is null and receipt_date >= v_month and receipt_date <= v_today), 0)
         + coalesce((select sum(l.amount) from public.cash_receipt_lines l
                       join public.cash_receipt_journals j on j.id = l.journal_id and j.status = 'POSTED' and j.deleted_at is null
                      where l.trans_date >= v_month and l.trans_date <= v_today), 0)
      into v_n;
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
