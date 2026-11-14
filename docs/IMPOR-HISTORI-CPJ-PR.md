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
