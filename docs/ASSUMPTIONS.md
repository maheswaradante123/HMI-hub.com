# Keputusan dan Asumsi Bisnis

Daftar ini memuat keputusan yang saya ambil tanpa konfirmasi eksplisit agar pembangunan bisa lanjut. Mohon ditinjau; setiap butir mudah diubah.

## Stok (Phase 7)
- Stok dihitung per item dan per gudang dari buku mutasi yang hanya bisa ditambah. Koreksi dilakukan dengan mutasi baru, tidak dengan mengubah yang lama.
- Stok tidak boleh minus. Packing list dan pembatalan penimbangan ditolak jika membuat stok minus.
- Jenis pencatatan manual: stok awal, pembelian masuk (dengan harga beli), penyesuaian tambah/kurang (wajib alasan).
- Tanda "Menipis" muncul jika stok di bawah batas minimum produk (diisi manual).
- Nilai stok = stok x harga beli terakhir dari pencatatan "Pembelian masuk". Produk hasil potong sapi belum punya harga beli terakhir sehingga nilainya kosong.
- Stock Opname disetujui Owner. Selisih dicatat sebagai mutasi koreksi.

## RO, Production Order, Packing List (Phase 8-10)
- Harga RO: harga Horeka per customer jika ada, selain itu harga toko. Harga disalin ke RO saat dibuat sehingga perubahan harga setelahnya tidak mengubah RO lama.
- RO: Draf, Dikonfirmasi, Selesai, Dibatalkan. Production Order hanya dari RO yang dikonfirmasi; disetujui Owner (PPIC).
- Packing List dibuat Produksi dari Production Order yang disetujui (atau langsung dari RO). Stok keluar saat "Selesai dikemas". Membatalkan packing list yang sudah dikemas hanya boleh Owner dan mengembalikan stok.
- Pengiriman tidak punya dokumen terpisah: sopir, plat, dan waktu terkirim ada di packing list.

## Penimbangan, Non-Karkas, Analisa (Phase 11-12)
- Nomor sapi memakai format lama (teks bebas), harus unik di antara penimbangan aktif.
- Berat karkas tidak boleh melebihi berat hidup; total berat daging tidak boleh melebihi karkas. Finalisasi memasukkan stok daging/tulang. Non-karkas tidak masuk stok.
- Penimbangan tidak membuat CPJ otomatis.
- Penjualan non-karkas dilakukan ke satu pembeli bertipe "pembeli non-karkas"; nilainya otomatis masuk ke Analisa Pembelian setelah dikonfirmasi, dan dibayar lewat CRJ.
- Rumus: karkas % = karkas / berat hidup; daging % = daging / karkas; harga karkas per kg = total pembelian sapi / berat karkas; laba = hasil penjualan item + non-karkas - total pembelian - biaya.
- Harga item di analisa disimpan saat analisa dibuat. Sumber harga (Pricing Toko atau diketik) dicatat per baris.
- Biaya di analisa memakai jenis biaya yang fleksibel (master Jenis Biaya).
- Satu analisa aktif per penimbangan.

## Invoice, CRJ, CPJ, Gaji (Phase 13-15)
- Invoice dibuat dari packing list yang sudah dikemas (satu invoice aktif per packing list). Harga invoice mengikuti harga di RO asal; jika tidak ada RO, memakai harga Horeka atau harga toko saat tanggal invoice. Jatuh tempo = tanggal invoice + termin customer, bisa diisi manual.
- Pajak: satu tarif global di menu Pengaturan Pajak, default 0%. Tarif dikunci pada invoice saat diterbitkan.
- Status lunas/sebagian hanya berubah lewat posting CRJ. CRJ yang dibatalkan membalik efeknya. KOPRA hanya label metode bayar.
- Pembayaran tidak boleh melebihi sisa tagihan. Total alokasi tidak boleh melebihi jumlah CRJ; sisa yang tidak dialokasikan diperbolehkan (mis. penerimaan lain).
- Pembatalan posting hanya oleh pemegang izin Hapus/Batal (default Owner dan Accounting).
- CPJ untuk PR: PR harus berstatus Barang diterima; posting pertama mengubah PR menjadi Sudah dibayar. Menutup PR (Selesai) dilakukan Accounting setelah dibayar. Pembatalan CPJ mengembalikan PR ke Barang diterima selama belum ditutup.
- Gaji memakai tabel yang sama dengan CPJ tetapi hanya terlihat oleh pemegang izin Gaji. Bonus belum dibuat (sesuai keputusan).

## Dashboard, Laporan, Admin (Phase 16-18)
- Dashboard hanya menampilkan angka yang boleh dilihat role tersebut.
- Laporan berformat CSV dengan perlindungan terhadap rumus Excel berbahaya.
- Akun baru dibuat lewat Supabase Auth (butuh kunci layanan, sengaja tidak ada di aplikasi web). Aplikasi mengelola role, departemen, status aktif, dan matriks izin.
- Owner tidak bisa mengubah role atau status akunnya sendiri dari aplikasi, untuk mencegah terkunci.

## Belum dibangun
- Pengurangan stok untuk penjualan eceran (tetap di Kasir Pintar).
- Bonus, perhitungan HPP, dan jurnal akuntansi lengkap.
- Notifikasi (email/WhatsApp) dan unggah lampiran dokumen.
- Pengujian otomatis alur login dan simpan terhadap Supabase sungguhan (lihat docs/UAT.md untuk uji manual).

## Revisi RBAC (migrasi 0010)
- Matriks izin mengikuti gambar Owner. Marketing boleh membuat dan mengubah PO (keputusan Owner); sel bertanda "?" dibaca: Kasir melihat PO/PL/CW, Kasir VCE di Stok, Produksi V di Penjualan Toko, Accounting tanpa approve PR.
- Owner boleh mengubah Production Order pada status apa pun kecuali dibatalkan. Penimbangan Karkas final tetap terkunci karena finalisasi sudah mencatat stok; untuk koreksi, Owner membatalkan lalu menimbang ulang.
- Penjualan Toko pada matriks dipetakan ke modul Penjualan Non-Karkas.
