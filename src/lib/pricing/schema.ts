export type PriceInput = {
  sell_price: number | null;
  buy_price: number | null;
  supplier_id: string | null;
  effective_from: string; // YYYY-MM-DD
  note: string | null;
};
export type PriceParse = { ok: true; data: PriceInput } | { ok: false; error: string };

const MAX = 1e13;

// Format Indonesia: titik sebagai pemisah ribuan, koma sebagai desimal.
export function parseMoney(raw: string): number | null | "invalid" {
  const t = raw.replace(/[Rr][Pp]\.?/g, "").replace(/\s/g, "");
  if (t === "") return null;
  // Titik hanya boleh sebagai pemisah ribuan (kelompok 3 angka); "1.5" ditolak agar tidak terbaca 15.
  if (!/^\d{1,3}(\.\d{3})*(,\d+)?$/.test(t) && !/^\d+(,\d+)?$/.test(t)) return "invalid";
  const n = Number(t.replace(/\./g, "").replace(",", "."));
  if (!Number.isFinite(n) || n < 0 || n >= MAX) return "invalid";
  return n;
}

export function isRealDate(s: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s && Number(s.slice(0, 4)) >= 2020;
}

export function parsePrice(
  raw: { sell: string; buy: string; supplier: string; from: string; note: string },
  opts: { canSetCost: boolean; showCost: boolean },
): PriceParse {
  const sell = parseMoney(raw.sell);
  if (sell === "invalid") return { ok: false, error: "Harga jual harus berupa angka, tidak boleh negatif." };

  let buy: number | null = null;
  let supplier: string | null = null;
  if (opts.showCost && opts.canSetCost) {
    const b = parseMoney(raw.buy);
    if (b === "invalid") return { ok: false, error: "Harga beli harus berupa angka, tidak boleh negatif." };
    buy = b;
    const s = raw.supplier.trim();
    if (s) {
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s)) {
        return { ok: false, error: "Supplier belum dipilih dengan benar." };
      }
      supplier = s;
    }
  }

  if (sell === null && buy === null) {
    return { ok: false, error: opts.showCost ? "Isi harga jual atau harga beli." : "Harga jual wajib diisi." };
  }
  if (!isRealDate(raw.from)) return { ok: false, error: "Tanggal berlaku belum diisi dengan benar." };
  const note = raw.note.trim();
  if (note.length > 500) return { ok: false, error: "Catatan terlalu panjang (maksimal 500 huruf)." };

  return { ok: true, data: { sell_price: sell, buy_price: buy, supplier_id: supplier, effective_from: raw.from, note: note || null } };
}
