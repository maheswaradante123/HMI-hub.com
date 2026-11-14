-- HMI Hub - CPJ: melengkapi atau merevisi dokumen (folder bukti dan rincian Petty Cash) pada jurnal yang sudah lewat.
-- Jurnal yang sudah ACC atau direalisasi terkunci angkanya, tetapi dokumen pendukung boleh ditambah kapan saja.
-- Fungsi ini hanya menyentuh kolom proof dan details; rencana dan realisasi tidak bisa diubah lewat sini. Perubahan tercatat di riwayat audit baris.
create or replace function public.jcp_update_docs(p_id uuid, p_lines jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_status text;
  e        jsonb;
  v_det    jsonb;
begin
  if not public.has_permission('cpj_journal', 'edit') then
    raise exception 'Anda tidak memiliki izin untuk melengkapi dokumen CPJ' using errcode = '42501';
  end if;
  select status into v_status from public.cash_journals where id = p_id and deleted_at is null for update;
  if v_status is null then raise exception 'Jurnal tidak ditemukan' using errcode = 'P0002'; end if;
  if v_status = 'VOID' then raise exception 'Jurnal yang dibatalkan tidak bisa diubah' using errcode = '55000'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then raise exception 'Isian tidak terbaca' using errcode = '22023'; end if;
  for e in select * from jsonb_array_elements(p_lines) loop
    v_det := e->'details';
    if v_det is not null and jsonb_typeof(v_det) = 'string' then v_det := (v_det #>> '{}')::jsonb; end if;
    if v_det is not null and jsonb_typeof(v_det) not in ('array', 'null') then
      raise exception 'Rincian Petty Cash harus berupa daftar' using errcode = '22023';
    end if;
    update public.cash_journal_lines l set
      proof   = case when e ? 'proof' then nullif(btrim(coalesce(e->>'proof', '')), '') else l.proof end,
      details = case when v_det is null or jsonb_typeof(v_det) = 'null' then l.details else v_det end
     where l.journal_id = p_id and l.line_no = (e->>'line_no')::int;
  end loop;
end $$;
revoke all on function public.jcp_update_docs(uuid, jsonb) from public, anon;
grant execute on function public.jcp_update_docs(uuid, jsonb) to authenticated;
