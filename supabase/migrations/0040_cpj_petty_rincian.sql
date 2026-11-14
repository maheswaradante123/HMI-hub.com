-- HMI Hub - CPJ: rincian bertingkat untuk baris Petty Cash.
-- Baris yang deskripsinya memuat "petty cash" dijabarkan menjadi beberapa transaksi (tanggal, digunakan untuk, jumlah, tautan folder dokumen).
-- Rincian disimpan sebagai jsonb di barisnya sendiri supaya ikut tersimpan oleh save_doc (yang membuat ulang baris setiap simpan).
-- Bentuk: [{"no":1,"date":"2026-10-31","text":"Bensin","amount":50000,"proof":"https://drive.google.com/..."}]
-- Saat realisasi diselesaikan (ACC -> REALIZED), total rincian wajib sama dengan Real. Amount barisnya.
alter table public.cash_journal_lines add column if not exists details jsonb;

create or replace function public.jcp_line_defaults() returns trigger
language plpgsql as $$
begin
  new.flag  := coalesce(nullif(btrim(new.flag), ''), 'NONE');
  new.price := coalesce(new.price, 0);
  new.qty   := coalesce(new.qty, 1);
  new.ac    := nullif(btrim(coalesce(new.ac, '')), '');
  new.code  := nullif(btrim(coalesce(new.code, '')), '');
  new.unit  := nullif(btrim(coalesce(new.unit, '')), '');
  new.proof := nullif(btrim(coalesce(new.proof, '')), '');
  -- aplikasi mengirim rincian sebagai teks JSON; simpan sebagai larik
  if new.details is not null and jsonb_typeof(new.details) = 'string' then
    new.details := (new.details #>> '{}')::jsonb;
  end if;
  new.details := coalesce(new.details, '[]'::jsonb);
  if jsonb_typeof(new.details) <> 'array' then
    raise exception 'Rincian Petty Cash harus berupa daftar' using errcode = '22023';
  end if;
  return new;
end $$;

update public.doc_registry set children =
  '[{"key":"lines","table":"cash_journal_lines","fk":"journal_id","cols":["trans_date","ac","code","description","price","qty","unit","flag","pr_item_id","real_price","real_qty","proof","details"]}]'
 where doc_type = 'JCP';

create or replace function public.jcp_check_petty() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r      record;
  v_real numeric;
  v_sum  numeric;
begin
  if tg_op = 'UPDATE' and new.status = 'REALIZED' and old.status is distinct from 'REALIZED' then
    for r in
      select l.line_no, l.description, l.price, l.qty, l.real_price, l.real_qty, l.details
        from public.cash_journal_lines l
       where l.journal_id = new.id and l.description ~* 'petty\s*cash' and l.flag not in ('REJECTED', 'INCOMING')
       order by l.line_no
    loop
      v_real := coalesce(r.real_price, r.price) * coalesce(r.real_qty, r.qty);
      select coalesce(sum((e->>'amount')::numeric), 0) into v_sum from jsonb_array_elements(coalesce(r.details, '[]'::jsonb)) e;
      if v_sum is distinct from v_real then
        raise exception 'Baris % (%): total rincian Rp % tidak sama dengan realisasi Rp %. Lengkapi rincian Petty Cash dulu.',
          r.line_no, r.description, to_char(v_sum, 'FM999G999G999G990'), to_char(v_real, 'FM999G999G999G990') using errcode = '22023';
      end if;
    end loop;
  end if;
  return new;
end $$;
revoke all on function public.jcp_check_petty() from public, anon, authenticated;
drop trigger if exists cash_journals_petty on public.cash_journals;
create trigger cash_journals_petty before update on public.cash_journals
  for each row execute function public.jcp_check_petty();
