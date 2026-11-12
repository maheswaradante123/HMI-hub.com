# Unggah file ke Google Drive

Tombol **Unggah** (⬆) di kolom Bukti/Tautan (CPJ, CRJ, PMT, Purchase Request) dan di Surat Jalan mengirim file ke
Google Drive perusahaan, lalu mengisi tautannya otomatis. Isi file **tidak** disimpan di Supabase.

- Akun Drive: `harmonimitrainovindo@gmail.com`
- Lokasi umum: `HMI Hub Uploads / <CRJ|PMT|PR|DO|LAIN> / <tahun-bulan>`
- Bukti realisasi **CPJ**: `HMI Hub Uploads / CPJ / 2026 / Oktober 2026 / CPJ-005-X-26 / <Description item>`.
  Di kolom Bukti tiap item ada tombol **Dokumen n/5**. Isinya daftar kelengkapan: PO, Surat Jalan, Invoice, Bukti Penerimaan, Bukti Transfer
  (plus "Lainnya", opsional). Tiap jenis punya tombol Unggah sendiri (boleh banyak file) dan ditandai ✓ bila sudah ada. Jenis menjadi awalan nama
  file di Drive ("Invoice - scan.pdf"). Kolom Bukti terisi tautan folder item. Bulan mengikuti tanggal jurnal; dokumen harus sudah disimpan
  (punya nomor) dan Description item terisi.
- Jangan mengubah nama atau memindahkan folder `HMI Hub Uploads`; aplikasi mencarinya berdasarkan nama di Drive Saya. Isinya boleh diatur bebas.
- Folder lama yang Anda buat manual (mis. `#ADMINKEU/CPJ`) tidak terlihat oleh aplikasi karena izinnya hanya `drive.file`; folder baru dibuat terpisah dengan susunan yang sama.
- Akses file: siapa pun yang punya tautan (hanya bisa melihat)
- Batas: 200 MB per file; PDF, foto (JPG/PNG/WEBP/HEIC), Word, Excel, PowerPoint, CSV, ZIP
- Izin aplikasi hanya `drive.file`: aplikasi hanya bisa menyentuh file yang ia buat sendiri, bukan seluruh isi Drive.

Isi file dikirim browser langsung ke Google; server HMI Hub hanya membuat sesi unggah dan membuka akses tautan,
jadi batas ukuran permintaan Vercel (4,5 MB) tidak berlaku.

## Penyiapan (sekali saja, login sebagai harmonimitrainovindo@gmail.com)

1. Buka <https://console.cloud.google.com/>, buat proyek baru (mis. `hmi-hub`).
2. **APIs & Services → Library** → cari **Google Drive API** → **Enable**.
3. **APIs & Services → OAuth consent screen** (Google Auth Platform):
   - Jenis pengguna **External**, isi nama aplikasi (mis. `HMI Hub`) dan email.
   - Tambahkan scope `.../auth/drive.file`.
   - **Publishing status: In production** (klik *Publish app*). Bila dibiarkan *Testing*, token kedaluwarsa tiap 7 hari.
     Untuk scope `drive.file` tidak perlu verifikasi Google; layar peringatan "belum diverifikasi" saat login boleh dilewati
     (*Advanced → Go to ... (unsafe)*), karena hanya akun sendiri yang memakainya.
4. **Credentials → Create credentials → OAuth client ID** → jenis **Web application**. Pada *Authorized redirect URIs*
   isi `https://developers.google.com/oauthplayground`. Catat **Client ID** dan **Client secret**.
5. Buka <https://developers.google.com/oauthplayground>:
   - Klik ikon roda gigi → centang **Use your own OAuth credentials** → isi Client ID dan Client secret.
   - Di kolom scope (Step 1) ketik `https://www.googleapis.com/auth/drive.file` → **Authorize APIs** → login dengan
     `harmonimitrainovindo@gmail.com` → izinkan.
   - Step 2 → **Exchange authorization code for tokens** → salin **Refresh token**.
6. Di Vercel (**Settings → Environment Variables**, Production) tambahkan:
   - `GOOGLE_CLIENT_ID`
   - `GOOGLE_CLIENT_SECRET`
   - `GOOGLE_REFRESH_TOKEN`
7. **Redeploy**. Coba unggah satu file lewat Surat Jalan → kolom *Tautan scan*.

## Bila gagal

Buka `https://<domain-aplikasi>/api/drive/status` di browser (setelah login). Halaman itu menyebut variabel mana yang tidak terbaca atau bentuknya janggal, dan apakah Google menerima login-nya (`"siap": true` bila semua beres). Nilai rahasia tidak ditampilkan.

| Pesan | Penyebab / tindakan |
| --- | --- |
| "Unggah ke Google Drive belum diatur di server" | Salah satu dari tiga variabel di atas belum diisi, atau belum Redeploy. |
| "Izin Google Drive sudah kedaluwarsa atau dicabut" | Refresh token tidak berlaku lagi (status *Testing* >7 hari, password akun diganti, atau akses dicabut). Ulangi langkah 5 dan ganti `GOOGLE_REFRESH_TOKEN`. |
| "Sesi berakhir. Muat ulang halaman" | Login HMI Hub habis; masuk lagi. |
| "Koneksi terputus saat mengunggah" | Jaringan putus; ulangi. |

Penyimpanan Drive gratis 15 GB dipakai bersama Gmail dan Foto di akun yang sama. Pantau di <https://drive.google.com/drive/quota>.
File yang sudah diunggah tidak terhapus bila baris dokumennya dihapus; hapus manual di Drive bila perlu.
