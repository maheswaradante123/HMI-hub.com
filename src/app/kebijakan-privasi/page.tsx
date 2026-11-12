import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Kebijakan Privasi - HMI Hub",
  robots: { index: false, follow: false },
};

export default function PrivacyPage() {
  return (
    <main className="mx-auto max-w-2xl px-5 py-10 text-lg leading-relaxed">
      <h1 className="text-3xl font-bold">Kebijakan Privasi HMI Hub</h1>
      <p className="mt-2 text-muted">Berlaku sejak 12 November 2026</p>

      <p className="mt-6">
        HMI Hub adalah sistem internal PT Harmoni Mitra Inovindo untuk mencatat operasional usaha (pesanan, pengiriman, jurnal kas, pembelian, dan
        stok). Aplikasi ini hanya dipakai oleh karyawan dan mitra yang akunnya dibuat oleh perusahaan, bukan untuk masyarakat umum.
      </p>

      <h2 className="mt-8 text-xl font-bold">Data yang disimpan</h2>
      <p className="mt-2">
        Nama dan email akun pengguna, catatan transaksi yang diinput pengguna, dan tautan ke berkas pendukung. Data disimpan pada layanan basis data
        yang dikelola perusahaan dan hanya dapat dibuka oleh pengguna yang berizin.
      </p>

      <h2 className="mt-8 text-xl font-bold">Akses ke Google Drive</h2>
      <p className="mt-2">
        Fitur unggah berkas menyimpan dokumen pendukung (misalnya surat jalan, invoice, dan bukti transfer) ke Google Drive milik perusahaan. Aplikasi
        meminta izin terbatas (drive.file), yaitu hanya untuk berkas dan folder yang dibuat oleh aplikasi itu sendiri. Aplikasi tidak membaca,
        mengubah, atau menghapus berkas lain di Drive. Izin ini diberikan satu kali oleh akun Google perusahaan, bukan oleh setiap pengguna, dan
        penggunaan data dari Google mematuhi Kebijakan Data Pengguna Layanan API Google, termasuk persyaratan Penggunaan Terbatas.
      </p>

      <h2 className="mt-8 text-xl font-bold">Pembagian data</h2>
      <p className="mt-2">Data tidak dijual dan tidak dibagikan kepada pihak ketiga, kecuali penyedia layanan teknis yang menjalankan aplikasi ini atas nama perusahaan.</p>

      <h2 className="mt-8 text-xl font-bold">Kontak</h2>
      <p className="mt-2">Pertanyaan atau permintaan penghapusan data dapat dikirim ke harmonimitrainovindo@gmail.com.</p>
    </main>
  );
}
