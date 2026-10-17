// Pesan dari fungsi database sudah berbahasa Indonesia; kode lain diganti pesan umum.
export function dbMessage(error: { code?: string; message?: string }): string {
  switch (error.code) {
    case "42501":
    case "55000":
    case "22023":
    case "P0002":
      return error.message ?? "Aksi tidak dapat dilakukan.";
    case "23505":
      return "Data ganda: nomor atau kombinasi ini sudah dipakai dokumen lain yang masih aktif.";
    case "23503":
      return "Ada data terkait yang tidak ditemukan. Muat ulang halaman lalu coba lagi.";
    case "23514":
    case "23P01":
      return "Ada isian yang tidak sesuai aturan (misalnya berat karkas lebih besar dari berat hidup, atau tanggal bertabrakan). Periksa kembali.";
    default:
      return "Belum berhasil disimpan. Silakan coba lagi. Jika masih gagal, hubungi Owner.";
  }
}
