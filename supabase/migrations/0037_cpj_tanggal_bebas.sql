-- HMI Hub - CPJ: tanggal (jurnal dan tiap baris) boleh diganti setelah ACC Owner.
-- Tanggal dikeluarkan dari sidik jari rencana; yang terkunci setelah ACC tetap A/C, kode, deskripsi, harga, qty, unit, jenis baris,
-- dan item PR. Sidik jari jurnal yang sudah ada dihitung ulang dengan rumus baru supaya simpan setelah ACC tidak ditolak.
create or replace function public.jcp_after_save(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_status text;
  v_hash   text;
  v_old    text;
  v_dup    text;
begin
  select status, plan_hash into v_status, v_old from public.cash_journals where id = p_id;
  select md5(coalesce(string_agg(concat_ws('|', l.line_no, l.ac, l.code, l.description, l.price, l.qty, l.unit, l.flag, l.pr_item_id), E'\n' order by l.line_no), ''))
    into v_hash from public.cash_journal_lines l where l.journal_id = p_id;
  if v_status = 'DRAFT' then
    update public.cash_journals set plan_hash = v_hash where id = p_id;
  elsif v_status = 'ACC' and v_hash is distinct from v_old then
    raise exception 'Jurnal sudah di-ACC Owner: kolom rencana tidak boleh diubah, hanya realisasi dan bukti' using errcode = '55000';
  end if;
  select j.doc_number into v_dup
    from public.cash_journal_lines l
    join public.cash_journal_lines o on o.pr_item_id = l.pr_item_id and o.journal_id <> l.journal_id
    join public.cash_journals j on j.id = o.journal_id and j.status <> 'VOID' and j.deleted_at is null
   where l.journal_id = p_id and l.pr_item_id is not null
   limit 1;
  if v_dup is not null then
    raise exception 'Item Purchase Request sudah dipakai di jurnal %', v_dup using errcode = '23505';
  end if;
end $$;
revoke all on function public.jcp_after_save(uuid) from public, anon, authenticated;

update public.cash_journals j set plan_hash = (
  select md5(coalesce(string_agg(concat_ws('|', l.line_no, l.ac, l.code, l.description, l.price, l.qty, l.unit, l.flag, l.pr_item_id), E'\n' order by l.line_no), ''))
    from public.cash_journal_lines l where l.journal_id = j.id)
 where j.status <> 'DRAFT';
