-- Merapikan laporan Pemasukan Toko: hanya PMT-004-X-26 yang benar. Ia diganti nomornya menjadi PMT-001-X-26,
-- semua laporan Pemasukan Toko lain (draf, final, atau dibatalkan) dihapus permanen, dan nomor urut dikembalikan.
-- Jalankan sekali di Supabase SQL Editor. Aman diulang: bila PMT-004-X-26 sudah tidak ada, skrip berhenti tanpa mengubah apa pun.
do $$
declare
  v_keep uuid; v_hapus integer; v_stale integer; r record; v_max integer;
begin
  select id into v_keep from public.store_income_reports where doc_number = 'PMT-004-X-26' and deleted_at is null;
  if v_keep is null then raise exception 'PMT-004-X-26 tidak ditemukan (mungkin sudah diganti nomornya). Tidak ada yang diubah.'; end if;

  create temp table _buang on commit drop as select id, doc_number from public.store_income_reports where id <> v_keep;
  select count(*) into v_hapus from _buang;

  -- baris CRJ yang pernah menarik dari laporan yang dihapus akan kehilangan rujukannya; hanya dihitung, tidak dihapus
  select count(*) into v_stale from public.cash_receipt_lines l join _buang b on l.src_ref like b.doc_number || '|%';

  delete from public.store_income_lines       where report_id in (select id from _buang);
  delete from public.store_income_receivables where report_id in (select id from _buang);
  delete from public.store_income_reports     where id in (select id from _buang);

  update public.store_income_reports set doc_number = 'PMT-001-X-26' where id = v_keep;
  -- rujukan tarikan CRJ ikut nomor baru supaya baris yang sudah ditarik tidak muncul lagi sebagai tarikan baru
  update public.cash_receipt_lines set src_ref = 'PMT-001-X-26' || substr(src_ref, length('PMT-004-X-26') + 1) where src_ref like 'PMT-004-X-26|%';

  -- nomor urut per bulan kembali ke nomor terbesar yang masih dipakai
  for r in select ym from public.pmt_sequences loop
    select coalesce(max(substring(doc_number from 5 for 3)::integer), 0) into v_max
      from public.store_income_reports where doc_number ~ '^PMT-[0-9]{3}-' and to_char(period_to, 'YYYYMM') = r.ym;
    update public.pmt_sequences set last_number = v_max where ym = r.ym;
  end loop;

  raise notice 'Laporan dihapus: %. PMT-004-X-26 sekarang PMT-001-X-26.', v_hapus;
  if v_stale > 0 then raise notice 'Perhatian: % baris CRJ merujuk laporan yang dihapus (rujukannya sudah tidak ada).', v_stale; end if;
end $$;

select doc_number, period_from, period_to, status from public.store_income_reports where deleted_at is null order by doc_number;
select * from public.pmt_sequences order by ym;
