# Daftar Uji Penerimaan (UAT)

Jalankan dengan akun dummy tiap role pada lingkungan uji, bukan produksi. Centang saat hasilnya sesuai.

## Alur utama toko
1. Produksi: Stok > Catat stok, stok awal Topside 50 kg. Saldo tampil 50.
2. Marketing: Order / RO > RO baru untuk Hotel A (harga dikosongkan). Harga terisi otomatis. Simpan, lalu Konfirmasi.
3. Marketing: dari RO, buat Production Order, ajukan. Owner: setujui.
4. Produksi: dari Production Order, buat Packing List dengan sopir dan plat. Tandai selesai dikemas. Stok berkurang. Jika stok kurang, muncul pesan jelas dan stok tidak berubah.
5. Produksi: tandai terkirim. Menu Pengiriman menampilkan waktu terkirim.
6. Accounting: dari Packing List, buat Invoice. Harga dan pajak benar. Terbitkan.
7. Accounting: Catat pembayaran (CRJ) sebagian dengan metode KOPRA. Invoice menjadi Dibayar sebagian. Bayar sisanya, invoice Lunas. Batalkan CRJ kedua dengan alasan, invoice kembali Dibayar sebagian.

## Alur sapi
1. Purchasing: Penimbangan Karkas baru (nomor sapi format lama, berat hidup 460, karkas 250, beberapa potongan). Finalkan. Stok daging bertambah. Tidak ada CPJ yang terbentuk otomatis.
2. Purchasing: Jual non-karkas ke pembeli. Konfirmasi. Accounting catat CRJ untuk penjualan itu.
3. Purchasing: Analisa Pembelian dari penimbangan. Harga terisi dari Pricing Toko, bisa diketik ulang. Persentase karkas, persentase daging, harga karkas per kg, dan laba tampil. Ubah harga di Pricing Toko, lalu buka analisa lama: angkanya tidak berubah.

## Purchase Request
1. Marketing buat PR dan ajukan. Owner setujui. Purchasing tandai dipesan lalu diterima.
2. Accounting: Catat pembayaran PR (CPJ), posting. PR menjadi Sudah dibayar. Tutup PR.

## Pembatasan akses (harus ditolak)
- [ ] Marketing tidak melihat harga beli, menu Invoice, CRJ, CPJ, Gaji.
- [ ] Produksi tidak melihat Invoice, CRJ, CPJ, Gaji, harga beli, nilai stok.
- [ ] Purchasing tidak melihat Gaji dan harga Horeka.
- [ ] Hanya Owner yang menyetujui PR, Production Order, dan Stock Opname.
- [ ] Mengetik alamat halaman terlarang langsung menampilkan Akses ditolak.
- [ ] Dokumen berstatus final/terposting tidak bisa diubah, hanya dibatalkan dengan alasan.
- [ ] Audit Log (Owner) mencatat setiap perubahan di atas.

## Aksesibilitas staf senior
- [ ] Semua tulisan terbaca di layar 13 inci tanpa zoom.
- [ ] Setiap tombol berisi kata kerja jelas. Pesan kesalahan memberi tahu apa yang harus diperbaiki.
