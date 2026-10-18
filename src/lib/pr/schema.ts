import { parseMoney } from "../pricing/schema.ts";
import { PR_AC_VALUES } from "./lines.ts";

export type PrItemInput = { ac: string; code: string; item_name: string; price: number; qty: number; unit: string; pay_method: string };
// "2,5" -> 2.5; "1.250,5" -> 1250.5; "2.5" -> 2.5 (satu titik dianggap desimal); "1.250.000" -> 1250000.
function parseQty(v: string): number {
  let t = v.trim();
  if (t.includes(",")) t = t.replace(/\./g, "").replace(",", ".");
  else if ((t.match(/\./g) ?? []).length > 1) t = t.replace(/\./g, "");
  return t === "" ? NaN : Number(t);
}
export type ParseResult = { ok: true; items: PrItemInput[] } | { ok: false; error: string };

// raw adalah isian mentah per baris barang dari form (teks). Baris yang benar-benar kosong diabaikan.
export function parsePrRows(raw: Record<string, string>[]): ParseResult {
  const rows = raw.filter((r) => ["item_name", "price", "qty"].some((k) => (r[k] ?? "").trim() !== ""));
  if (rows.length === 0) return { ok: false, error: "Isi minimal satu barang." };
  if (rows.length > 100) return { ok: false, error: "Maksimal 100 barang sekali simpan." };
  const items: PrItemInput[] = [];
  for (const [i, r] of rows.entries()) {
    const n = i + 1;
    const name = (r.item_name ?? "").trim();
    if (!name) return { ok: false, error: `Barang baris ${n}: description wajib diisi.` };
    if (name.length > 200) return { ok: false, error: `Barang baris ${n}: description terlalu panjang.` };
    const qty = parseQty(r.qty ?? "");
    if (!(r.qty ?? "").trim() || !Number.isFinite(qty)) return { ok: false, error: `Barang baris ${n}: qty harus berupa angka.` };
    if (qty <= 0) return { ok: false, error: `Barang baris ${n}: qty harus lebih dari 0.` };
    if (qty >= 1e9) return { ok: false, error: `Barang baris ${n}: qty terlalu besar.` };
    const unit = (r.unit ?? "").trim();
    if (!unit) return { ok: false, error: `Barang baris ${n}: satuan wajib diisi.` };
    if (unit.length > 20) return { ok: false, error: `Barang baris ${n}: satuan terlalu panjang.` };
    const price = parseMoney(r.price ?? "");
    if (price === "invalid") return { ok: false, error: `Barang baris ${n}: harga harus berupa angka, tidak boleh negatif.` };
    const ac = (r.ac ?? "").trim() || "OPR";
    if (!PR_AC_VALUES.includes(ac)) return { ok: false, error: `Barang baris ${n}: A/C tidak dikenal.` };
    const code = (r.code ?? "").trim() || "BP";
    if (code.length > 10) return { ok: false, error: `Barang baris ${n}: kode biaya terlalu panjang.` };
    const pay = (r.pay_method ?? "").trim() || "tf";
    if (pay.length > 40) return { ok: false, error: `Barang baris ${n}: kolom Pembelian terlalu panjang.` };
    items.push({ ac, code, item_name: name, price: price ?? 0, qty, unit, pay_method: pay });
  }
  return { ok: true, items };
}
