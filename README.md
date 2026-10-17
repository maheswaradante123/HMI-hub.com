# HMI Internal System

Aplikasi internal PT Harmoni Mitra Inovindo. Stack: Next.js 16 (App Router, TypeScript), Tailwind CSS, Supabase (Postgres, Auth, Storage), Vercel.

## Status
- Phase 3 (Authentication & Authorization): login, role, permission, route terlindungi.
- Phase 4 (Master Data): kategori, satuan, jenis sapi/non-karkas/biaya, metode bayar, gudang, lokasi, rekening/kas, customer, supplier, produk.
- Phase 5 (Purchase Request): form PR, alur persetujuan Owner, riwayat status, penomoran PR-2026-0001.
- Phase 6 (Pricing Toko): harga jual/beli per produk dengan riwayat (tidak pernah ditimpa), harga beli/supplier hanya untuk izin `pricing_cost`.

- Phase 7 Stok: mutasi, saldo per item, batas minimum, nilai stok, Stock Opname.
- Phase 8-10: RO dengan harga Horeka per customer, Production Order, Packing List dan Pengiriman.
- Phase 11-12: Penimbangan Karkas, Penjualan Non-Karkas, Analisa Pembelian.
- Phase 13-15: Invoice (pajak), CRJ, CPJ (termasuk pembayaran PR), Gaji.
- Phase 16-18: Dashboard, Laporan CSV, Audit Log, kelola User dan Role.
- Phase 19-20: pengujian (database, unit, CI) dan panduan deploy (docs/DEPLOY.md).

Asumsi bisnis ada di `docs/ASSUMPTIONS.md`, uji penerimaan di `docs/UAT.md`.

## Menjalankan di lokal
1. Buat project Supabase, lalu jalankan migrasi `supabase/migrations/0001` sampai `0009` (atau cukup `supabase/all_migrations.sql`) lalu `supabase/seed.sql` (data dummy development; untuk produksi pakai `seed_production.sql`) di SQL Editor (atau dengan Supabase CLI).
2. `cp .env.example .env.local` dan isi URL, anon key, service role key.
3. `DEV_SEED_PASSWORD='...' node --env-file=.env.local scripts/seed-dev-users.mjs` untuk membuat user dummy.
4. `npm install && npm run dev`

## Keamanan
- Izin diputuskan di database (`has_permission`, RLS). Sidebar hanya tampilan.
- Setiap halaman memeriksa izin di server. Proxy hanya mengarahkan tamu ke /login.
- Service role key hanya dipakai skrip lokal, tidak pernah ke browser.

## Pengujian
- Database: `scripts/db-test.sh` (migrasi, seed, tes 01 sampai 09) pada PostgreSQL kosong; CI di `.github/workflows/ci.yml`.
- Validasi form: `npm run test:unit`.
- Belum diuji otomatis: alur login dan simpan data lewat aplikasi terhadap Supabase sungguhan.
