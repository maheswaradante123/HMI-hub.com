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
3. **Jangan** menaruh `SUPABASE_SERVICE_ROLE_KEY` di Vercel. Kunci itu hanya untuk skrip lokal `scripts/seed-dev-users.mjs`.
4. Deploy. Buka alamat Vercel, masuk sebagai Owner, lalu cek menu Role & Izin.

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
