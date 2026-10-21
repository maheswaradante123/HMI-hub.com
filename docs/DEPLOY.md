# Panduan Deploy (Vercel + Supabase)

## 1. Supabase
1. Buat project Supabase (region terdekat, mis. Singapore). Simpan password database di pengelola kata sandi.
2. Buka SQL Editor, jalankan isi `supabase/all_migrations.sql` (gabungan 0001 sampai 0009; buat ulang dengan `node scripts/bundle-sql.mjs` bila ada migrasi baru).
3. Jalankan `supabase/seed_production.sql` (departemen, role, izin, matriks izin). **Jangan** menjalankan `supabase/seed.sql` di produksi karena berisi data dummy. Isi master data sungguhan (satuan, produk, customer, dst) lewat menu Master Data.
4. Authentication > Providers: aktifkan Email, **matikan** "Allow new users to sign up" (akun dibuat oleh Owner saja).
5. Authentication > URL Configuration: isi Site URL dengan alamat Vercel.
6. Buat akun Owner pertama: Authentication > Users > Add user, lalu jalankan di SQL Editor:
   ```sql
   insert into public.user_profiles (id, full_name, role_id)
   select '<UUID-user-yang-baru-dibuat>', 'Nama Owner', id from public.roles where code = 'OWNER';
   ```
7. Akun staf berikutnya dibuat dengan cara yang sama (role sesuai), lalu role dan departemen bisa diubah dari menu User di aplikasi.

## 2. Vercel
1. Import repository ke Vercel (framework Next.js terdeteksi otomatis).
2. Environment Variables (Production dan Preview):
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
   - Notifikasi email (opsional, lihat bagian 2b): `SMTP_USER`, `SMTP_PASS`, `APP_URL`
3. **Jangan** menaruh `SUPABASE_SERVICE_ROLE_KEY` di Vercel. Kunci itu hanya untuk skrip lokal `scripts/seed-dev-users.mjs`.
4. Deploy. Buka alamat Vercel, masuk sebagai Owner, lalu cek menu Role & Izin.

## 2b. Notifikasi email (migrasi 0029)
Setiap perpindahan status dokumen yang membutuhkan tindakan (RO dikonfirmasi, PO diajukan atau disetujui, Packing List dikemas, Surat Jalan, Invoice, jurnal kas, PR) mengirim email ke user aktif yang **berizin** melakukan langkah berikutnya. Aturannya ada di tabel `notification_rules`; penerima mengikuti role dan izin (termasuk override) sehingga tidak ada daftar penerima manual. Pengirim perubahan tidak menerima emailnya sendiri, dan tiap user bisa mematikannya di menu Notifikasi (sidebar, di bawah nama).

Pengiriman lewat SMTP dengan akun Gmail khusus (batas sekitar 500 email per hari):
1. Buat akun Gmail khusus, mis. `notifikasi.hmi@gmail.com`. Aktifkan Verifikasi 2 Langkah, lalu buat **App Password** di myaccount.google.com/apppasswords (16 huruf).
2. Vercel > Settings > Environment Variables (Production): `SMTP_USER` = alamat Gmail itu, `SMTP_PASS` = App Password, `APP_URL` = alamat aplikasi (mis. `https://hmihub.vercel.app`, tanpa garis miring akhir). Opsional: `MAIL_FROM_NAME` (default "HMI Hub"), `SMTP_HOST`/`SMTP_PORT` untuk layanan selain Gmail (default smtp.gmail.com:465). Lalu Redeploy.
3. Jalankan `supabase/migrations/0029_notifikasi_email.sql` di SQL Editor **sebelum** deploy kode.
4. Buka menu Notifikasi, klik "Kirim email uji ke saya".

Bila `SMTP_USER`/`SMTP_PASS` kosong, aplikasi berjalan normal tanpa mengirim email. Email yang gagal dicoba lagi pada aksi berikutnya dari user yang sama (maksimal 3 kali). Saat domain sendiri sudah ada, ganti ke layanan email transaksional (Resend, dsb.) cukup dengan mengubah variabel SMTP di atas.

## 3. Daftar periksa keamanan sebelum dipakai staf
- [ ] Sign up publik dimatikan di Supabase Auth.
- [ ] Tidak ada akun dummy dari seed (`*@hmi.test` atau sejenisnya) di Authentication > Users.
- [ ] Row Level Security aktif di semua tabel: `select relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity;` harus kosong.
- [ ] Hanya Owner yang memegang izin Role (`role`) dan User (`user`).
- [ ] Backup: aktifkan Point-in-Time Recovery atau jadwalkan backup harian (Supabase Pro), dan ekspor manual sebelum migrasi besar.
- [ ] Tarif pajak sudah diisi di menu Pengaturan Pajak (isi 0 jika belum memakai pajak).
- [ ] Stok awal dicatat lewat menu Stok > Catat stok (jenis "Stok awal"), lalu dicocokkan dengan hitung fisik lewat Stock Opname.

## 4. Pembaruan berikutnya
Migrasi baru ditambahkan sebagai file berurutan di `supabase/migrations/` dan dijalankan di SQL Editor sebelum deploy kode yang memakainya. Jalankan `scripts/db-test.sh` pada database uji kosong terlebih dahulu.
