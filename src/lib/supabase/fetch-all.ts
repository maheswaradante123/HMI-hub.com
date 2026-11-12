// Supabase membatasi satu permintaan sampai 1000 baris. Fungsi ini mengambil halaman demi halaman sampai habis,
// supaya daftar tidak terpotong berapa pun banyaknya data. Urutan di kueri harus tetap (akhiri dengan kolom id).
const PAGE = 1000;

export async function fetchAll<T>(
  page: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: unknown }>,
): Promise<{ data: T[]; error: unknown }> {
  const all: T[] = [];
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await page(from, from + PAGE - 1);
    if (error) return { data: all, error };
    const rows = data ?? [];
    all.push(...rows);
    if (rows.length < PAGE) return { data: all, error: null };
  }
}
