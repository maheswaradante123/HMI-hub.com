-- Merapikan CPJ minggu ke-5 Oktober 2026:
--   1. CPJ-005-X-26 (dibatalkan) dihapus permanen.
--   2. CPJ-005-X-26-2 diganti nomornya menjadi CPJ-005-X-26.
--   3. Realisasinya dibatalkan: status kembali ke ACC (tanggal ACC tetap), isian realisasi (harga, jumlah, bukti) dikosongkan
--      sehingga bisa diisi dari awal. Kolom rencana tidak disentuh.
--   4. PR yang tadinya jadi "Dibayar" karena realisasi ini dikembalikan ke "Barang diterima"; saat realisasi diselesaikan lagi,
--      statusnya otomatis menjadi "Dibayar" lagi.
-- Jalankan sekali di Supabase SQL Editor. Bila syarat awal tidak terpenuhi, skrip berhenti tanpa mengubah apa pun.
do $$
declare
  v_old uuid; v_new uuid; v_acc date; r record; v_lines integer;
begin
  select id into v_old from public.cash_journals where doc_number = 'CPJ-005-X-26' and status = 'VOID';
  select id, approved_on into v_new, v_acc from public.cash_journals where doc_number = 'CPJ-005-X-26-2' and status = 'REALIZED' and deleted_at is null;
  if v_old is null then raise exception 'CPJ-005-X-26 berstatus Dibatalkan tidak ditemukan. Tidak ada yang diubah.'; end if;
  if v_new is null then raise exception 'CPJ-005-X-26-2 berstatus Direalisasi tidak ditemukan. Tidak ada yang diubah.'; end if;

  -- 1. hapus jurnal yang dibatalkan
  delete from public.cash_journal_lines where journal_id = v_old;
  delete from public.cash_journals where id = v_old;

  -- 2 dan 3. batalkan realisasi: kembali ke ACC, lalu kosongkan isian realisasi
  --    PR yang menjadi Dibayar karena jurnal ini dikembalikan ke Barang diterima (sama seperti saat jurnal dibatalkan)
  for r in
    select distinct p.id from public.cash_journal_lines l
      join public.pr_items i on i.id = l.pr_item_id
      join public.purchase_requests p on p.id = i.pr_id
     where l.journal_id = v_new and p.status = 'PAID'
       and not exists (
         select 1 from public.cash_journal_lines l2
           join public.cash_journals j2 on j2.id = l2.journal_id and j2.status = 'REALIZED' and j2.deleted_at is null and j2.id <> v_new
           join public.pr_items i2 on i2.id = l2.pr_item_id
          where i2.pr_id = p.id)
       and not exists (select 1 from public.cash_payments c where c.pr_id = p.id and c.status = 'POSTED')
  loop
    update public.purchase_requests set status = 'RECEIVED' where id = r.id;
    insert into public.pr_status_history (pr_id, from_status, to_status, note, changed_by)
    values (r.id, 'PAID', 'RECEIVED', 'Realisasi CPJ-005-X-26 dibatalkan untuk diisi ulang', null);
  end loop;

  update public.cash_journals set status = 'ACC', realized_on = null, doc_number = 'CPJ-005-X-26' where id = v_new;
  update public.cash_journals set approved_on = v_acc where id = v_new; -- pindah ke ACC mengisi ulang tanggal ACC; kembalikan yang asli
  update public.cash_journal_lines set real_price = null, real_qty = null, proof = null where journal_id = v_new;
  get diagnostics v_lines = row_count;

  raise notice 'Selesai. CPJ-005-X-26 sekarang berstatus ACC, % baris realisasi dikosongkan.', v_lines;
end $$;

select doc_number, journal_date, approved_on, realized_on, status from public.cash_journals where deleted_at is null order by doc_number;
