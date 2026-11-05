-- HMI Hub - Pemasukan Toko: Debit dipecah per bank (Mandiri/BRI), kolom Grab dihentikan,
-- dan CRJ pertokoan menarik semua kolom bank dari Pemasukan Toko: QRIS, Debit, TF Rek HMI, dan Disetor.
--
-- Kolom grab tetap ada di tabel supaya data lama tidak hilang, tetapi tidak lagi dipakai form, total, maupun cetakan.

-- Debit dipecah per bank. Kolom debit tetap menjadi total (dipakai rumus dan cetakan).
alter table public.store_income_lines add column debit_mandiri numeric(18,2), add column debit_bri numeric(18,2);
create or replace function public.store_income_debit_total() returns trigger
language plpgsql as $$
begin
  if new.debit_mandiri is not null or new.debit_bri is not null then
    new.debit := coalesce(new.debit_mandiri, 0) + coalesce(new.debit_bri, 0);
  end if;
  return new;
end $$;
create trigger store_income_lines_debit before insert or update on public.store_income_lines
  for each row execute function public.store_income_debit_total();

update public.doc_registry set children =
  '[{"key":"lines","table":"store_income_lines","fk":"report_id","cols":["entry_date","description","cash","qris","qris_mandiri","qris_bri","debit","debit_mandiri","debit_bri","tf","deposited","proof","invoice_id"]},
    {"key":"recv","table":"store_income_receivables","fk":"report_id","cols":["name","amount"]}]'::jsonb
 where doc_type = 'PMT';

-- Sumber CRJ baru: DEBIT (per bank) dan TF (transfer ke rekening HMI, rekening dipilih saat membuat CRJ).
alter table public.cash_receipt_lines drop constraint if exists cash_receipt_lines_source_check;
alter table public.cash_receipt_lines add constraint cash_receipt_lines_source_check
  check (source in ('QURBAN_CLOSING','QURBAN_CARE','QRIS','DEBIT','TF','CASH_DEPOSIT','HOREKA','NONKARKAS','OTHER'));

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
  elsif new.source in ('QRIS','DEBIT','TF','CASH_DEPOSIT') and new.src_ref is null then
    raise exception 'Baris QRIS, debit, transfer, dan setoran cash harus ditarik dari Pemasukan Toko' using errcode = '22023';
  end if;
  if new.source <> 'HOREKA' and new.invoice_id is not null then raise exception 'Invoice hanya untuk baris tempo Horeka' using errcode = '22023'; end if;
  if new.source <> 'NONKARKAS' and new.ncs_id is not null then raise exception 'Penjualan non-karkas hanya untuk baris non-karkas' using errcode = '22023'; end if;
  return new;
end $$;

-- Tarik baris dari sumber (ditambah DEBIT dan TF).
create or replace function public.crj_pull(p_source text, p_from date, p_to date)
returns table (source text, ref_id uuid, src_ref text, trans_date date, description text, amount numeric, account_id uuid)
language plpgsql stable security definer set search_path = public as $$
declare v_mandiri uuid; v_bri uuid;
begin
  if not public.has_permission('crj','create') and not public.has_permission('crj','edit') then
    raise exception 'Tidak berhak' using errcode = '42501';
  end if;
  if p_source not in ('QURBAN_CLOSING','QURBAN_CARE','QRIS','DEBIT','TF','CASH_DEPOSIT','HOREKA','NONKARKAS') then
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

  elsif p_source = 'DEBIT' then
    select a.id into v_mandiri from public.accounts a where a.is_active and a.name ilike '%mandiri%' order by a.name limit 1;
    select a.id into v_bri     from public.accounts a where a.is_active and a.name ilike '%bri%'     order by a.name limit 1;
    return query
    select 'DEBIT'::text, null::uuid, (r.doc_number || '|' || x.entry_date || '|DEBIT_' || x.bank), x.entry_date,
           format('Debit %s toko (%s)', case x.bank when 'MANDIRI' then 'Mandiri' else 'BRI' end, r.doc_number),
           x.amt, case x.bank when 'MANDIRI' then v_mandiri else v_bri end
      from (
        select l.report_id, l.entry_date, 'MANDIRI'::text as bank, sum(l.debit_mandiri) as amt from public.store_income_lines l where l.debit_mandiri > 0 group by l.report_id, l.entry_date
        union all
        select l.report_id, l.entry_date, 'BRI'::text, sum(l.debit_bri) from public.store_income_lines l where l.debit_bri > 0 group by l.report_id, l.entry_date
      ) x
      join public.store_income_reports r on r.id = x.report_id and r.deleted_at is null and r.status <> 'VOID'
     where x.entry_date between p_from and p_to
       and not exists (select 1 from public.cash_receipt_lines l join public.cash_receipt_journals j on j.id = l.journal_id and j.status <> 'VOID' and j.deleted_at is null
                        where l.source = 'DEBIT' and l.src_ref = (r.doc_number || '|' || x.entry_date || '|DEBIT_' || x.bank))
     order by 4, 5;

  elsif p_source = 'TF' then
    -- Transfer ke rekening HMI yang diketik di Pemasukan Toko. Baris pembayaran invoice (berisi invoice) tidak ikut:
    -- itu sudah tercatat lewat baris tempo Horeka.
    return query
    select 'TF'::text, null::uuid, (r.doc_number || '|' || x.entry_date || '|TF'), x.entry_date,
           format('Transfer ke rekening HMI, toko (%s)', r.doc_number), x.amt, null::uuid
      from (select l.report_id, l.entry_date, sum(l.tf) as amt from public.store_income_lines l where l.tf > 0 and l.invoice_id is null group by l.report_id, l.entry_date) x
      join public.store_income_reports r on r.id = x.report_id and r.deleted_at is null and r.status <> 'VOID'
     where x.entry_date between p_from and p_to
       and not exists (select 1 from public.cash_receipt_lines l join public.cash_receipt_journals j on j.id = l.journal_id and j.status <> 'VOID' and j.deleted_at is null
                        where l.source = 'TF' and l.src_ref = (r.doc_number || '|' || x.entry_date || '|TF'))
     order by 4;

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

create or replace view public.v_cash_receipt_lines with (security_invoker = true) as
select l.id, j.doc_number, l.line_no, l.trans_date,
       case l.source when 'QURBAN_CLOSING' then 'Closing lunas Qurban' when 'QURBAN_CARE' then 'Pemeliharaan Qurban' when 'QRIS' then 'QRIS toko' when 'DEBIT' then 'Debit toko' when 'TF' then 'Transfer toko'
                     when 'CASH_DEPOSIT' then 'Penyetoran cash toko' when 'HOREKA' then 'Tempo Horeka' when 'NONKARKAS' then 'Non-karkas' else 'Lainnya' end as source_label,
       l.description, a.name as account_name, l.amount, l.proof
  from public.cash_receipt_lines l
  join public.cash_receipt_journals j on j.id = l.journal_id and j.status = 'POSTED' and j.deleted_at is null
  join public.accounts a on a.id = l.account_id;
grant select on public.v_cash_receipt_lines to authenticated;
