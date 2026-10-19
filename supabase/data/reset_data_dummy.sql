-- ============================================================================
-- HAPUS DATA DUMMY: mengosongkan semua dokumen dan stok, lalu nomor dokumen mulai dari 1 lagi.
-- Jalankan SEBELUM migrasi 0026 dan skrip stok awal, hanya sekali, di Supabase SQL Editor.
--
-- DIHAPUS : RO, Production Order, Packing List, Invoice, Delivery Order, CRJ, Pemasukan Toko,
--           Cash Payment Journal, CPJ, Gaji, Purchase Request, Analisa Pembelian, Penimbangan
--           Karkas, Penjualan Non-Karkas, Stock Opname, seluruh mutasi stok, data Qurban
--           (pesanan, penimbangan, tagihan, QC, pembeli), riwayat status, Audit Log,
--           dan penghitung nomor dokumen.
-- DIPERTAHANKAN: user, role & hak akses, produk, kategori, satuan, customer, supplier, rekening,
--           gudang, harga (Pricing Toko, Harga Horeka), tarif Qurban dan pengaturan pajak.
--
-- Tindakan ini TIDAK BISA DIBATALKAN. Agar tidak terjalankan tanpa sengaja, ubah baris di bawah
-- menjadi: v_konfirmasi text := 'HAPUS DATA DUMMY';
-- ============================================================================
do $reset$
declare
  v_konfirmasi text := '';   -- << ganti menjadi 'HAPUS DATA DUMMY'
begin
  if v_konfirmasi <> 'HAPUS DATA DUMMY' then
    raise exception 'Dibatalkan: ubah v_konfirmasi menjadi ''HAPUS DATA DUMMY'' bila Anda yakin.';
  end if;

  -- Tanpa CASCADE: bila ada tabel lain yang masih menunjuk ke tabel ini, perintah gagal (aman) dan tidak ada yang terhapus.
  truncate table
    public.crj_allocations, public.cash_receipts,
    public.cash_journal_lines, public.cash_journals,
    public.cash_payments,
    public.store_income_lines, public.store_income_receivables, public.store_income_reports,
    public.inv_items, public.invoices,
    public.delivery_orders,
    public.pl_items, public.packing_lists,
    public.po_items, public.production_orders,
    public.ro_items, public.request_orders,
    public.ap_costs, public.ap_items, public.ap_nonk, public.ap_cows, public.purchase_analyses,
    public.cw_items, public.carcass_weighings,
    public.ncs_items, public.noncarcass_sales,
    public.so_items, public.stock_opnames,
    public.stock_movements,
    public.pr_status_history, public.pr_items, public.purchase_requests,
    public.qurban_bills, public.qurban_buyer_details, public.qurban_qc_reports, public.qurban_weighings, public.qurban_orders,
    public.doc_status_history, public.audit_logs,
    public.ap_sequences, public.do_sequences, public.document_sequences, public.inv_sequences,
    public.pl_sequences, public.pmt_sequences, public.ro_sequences, public.qurban_sequences;

  update public.cw_counter set last_number = 0;
  raise notice 'Selesai: semua dokumen, stok, dan penghitung nomor dikosongkan.';
end
$reset$;
