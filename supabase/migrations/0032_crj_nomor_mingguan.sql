-- Penomoran CRJ disamakan dengan CPJ: CRJ-<minggu>-<bulan romawi>-<tahun>, contoh CRJ-002-XI-26.
-- Minggu ke-1 dimulai tanggal 1 (awal minggu Senin), dihitung dari tanggal penerimaan. Jika minggu itu sudah
-- punya CRJ lain, nomor diberi akhiran -2, -3, dst. (sama dengan CPJ). Nomor CRJ lama (CRJ-2026-0001) tidak diubah.
create or replace function public.crj_assign_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_roman text[] := array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'];
  v_base  text;
  v_n     integer;
begin
  if new.doc_number is not null then return new; end if;
  v_base := format('CRJ-%s-%s-%s', lpad(public.cpj_week_of(new.receipt_date)::text, 3, '0'),
                   v_roman[extract(month from new.receipt_date)::int], to_char(new.receipt_date, 'YY'));
  perform pg_advisory_xact_lock(hashtext(v_base));
  select count(*) into v_n from public.cash_receipts where doc_number = v_base or doc_number like v_base || '-%';
  new.doc_number := case when v_n = 0 then v_base else v_base || '-' || (v_n + 1) end;
  return new;
end $$;
revoke all on function public.crj_assign_number() from public, anon, authenticated;
drop trigger cash_receipts_docno on public.cash_receipts;
create trigger cash_receipts_docno before insert on public.cash_receipts
  for each row execute function public.crj_assign_number();
