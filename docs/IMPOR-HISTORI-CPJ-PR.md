# Impor histori CPJ dan PR (Januari 2026 dan seterusnya)

Status: tahap baca dan cocokkan. Belum ada yang dimasukkan ke database.

## Berkas sumber
- `CPJ_JANUARI` s/d `CPJ_SEPTEMBER` (10 berkas; `CPJ_JANUARI_2026` identik dengan `CPJ_JANUARI`) dan `PR-JANUARI-26` s/d `PR-OKTOBER`.
- Per minggu ada sheet rencana `CPJ-00n-...` dan sheet realisasi `R-CPJ-00n-...`; Juli juga punya `PC-R-CPJ-...` (rincian Petty Cash per minggu).
- Sheet lain (MOVE, cash, Salinan dari..., lapkeu, REMBES, Sheet2, PROYEKSI) diabaikan dulu.
- PR: sheet `PR-00n-M-26` dengan kolom A/C, Tanggal, Description, Price, Qty, Unit, Amount, Stok, Status (Approved/Received/...), catatan.

## Temuan
- Nomor dan tanggal di header sheet CPJ basi (hasil salin): banyak sheet April sampai September bertanggal 6 Apr 2026. Nama sheet pun kadang salah bulan (berkas April berisi sheet `CPJ-001-III-26` yang isinya April). Usulan identitas: nomor urut dari nama sheet + bulan dari nama berkas; tanggal jurnal = awal minggu ke-n bulan itu (aturan minggu aplikasi). Perlu dikonfirmasi pemilik.
- Tata letak kolom beda tiap bulan (kolom Kode ada atau tidak, kolom catatan liar); parser mendeteksi dari judul kolom.
- Jenis baris dibaca dari warna sel: kuning NON_CPJ, oranye OVER, merah REJECTED, biru muda INCOMING.
- Total permintaan hasil hitung cocok dengan ringkasan sheet pada 27 dari 38 jurnal. Total realisasi belum cocok (aturan kolom realisasi pada sheet perlu dipelajari per sheet: baris tanpa realisasi bernilai 0 di Excel, sedangkan aplikasi menganggap kosong = sama dengan rencana, jadi saat impor real_price/real_qty harus diisi eksplisit).
- Bukti: sel "Attachment Of Proof" berisi hyperlink Drive per file, bisa dibawa ke kolom Bukti.
- Mutasi rekening 18 Sep 2026 sampai sekarang akan dikirim terpisah; CPJ setelah tanggal itu dibentuk dari mutasi dan dicocokkan dengan PR.

## Skrip
- `scripts/import-histori/parse_cpj.py`: membaca semua sheet CPJ ke `cpj_raw.json`.
- `scripts/import-histori/review.py`: membuat `Daftar_CPJ_review.xlsx` (satu baris per jurnal, usulan nomor/tanggal, cek total).

## Mutasi rekening (dibaca 14 Nov 2026)
- Mandiri 1290015674415 (rekening CPJ), Jan s/d 14 Nov 2026: 2.911 transaksi, jumlah dan total debit/kredit sama persis dengan ringkasan tiap statement; saldo berjalan tanpa putus (`scripts/import-histori/mandiri.py`, memakai pdfplumber).
- BRI 117001000653562 (Britama Bisnis, QRIS toko), Jun s/d Nov 2026: total debit sama persis dengan ringkasan; kredit kurang Rp 10 ribuan per bulan karena baris bunga tanpa uraian (`bri.py`). BCA menyusul.
- Berkas mutasi sendiri tidak disimpan di repo (data sensitif).
- Mencocokkan baris CPJ ke mutasi dengan jumlah persis hanya mengena 22% baris (33% nilai), karena banyak pembayaran digabung atau tunai; total mingguan Mandiri juga tidak sejajar dengan CPJ karena rekening ini juga dipakai transaksi usaha lain. Pencocokan harus berupa usulan per baris yang dikonfirmasi pemilik, bukan otomatis.
- Satu berkas bukan mutasi: notifikasi BNI 30 Sep 2026, Habitare (HK Realtindo) membayar Rp 4.883.765 untuk "Pembelian Beef Cl 90, Iga periode 31 Juli-6 Agustus 2026" ke Mandiri; ini pembayaran customer (bahan NoA), bukan CPJ.
