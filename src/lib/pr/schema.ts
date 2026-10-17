import { z } from "zod";
import { parseMoney } from "../pricing/schema.ts";

export type PrItemInput = {
  product_id: string | null;
  item_name: string;
  qty: number;
  unit_id: string;
  estimated_price: number | null;
  notes: string | null;
};
export type PrInput = { reason: string; priority: "LOW" | "NORMAL" | "HIGH"; items: PrItemInput[] };
export type ParseResult = { ok: true; data: PrInput } | { ok: false; error: string };

const uuid = z.string().uuid();

// raw.rows adalah isian mentah per baris barang dari form.
export function parsePr(raw: {
  reason: string;
  priority: string;
  rows: Record<string, string>[];
}): ParseResult {
  const reason = raw.reason.trim();
  if (!reason) return { ok: false, error: "Alasan pembelian wajib diisi." };
  if (reason.length > 1000) return { ok: false, error: "Alasan pembelian terlalu panjang." };
  if (!["LOW", "NORMAL", "HIGH"].includes(raw.priority)) {
    return { ok: false, error: "Prioritas belum dipilih." };
  }

  // Baris yang benar-benar kosong diabaikan.
  const rows = raw.rows.filter((r) => Object.values(r).some((v) => v.trim() !== ""));
  if (rows.length === 0) return { ok: false, error: "Isi minimal satu barang." };
  if (rows.length > 100) return { ok: false, error: "Maksimal 100 barang dalam satu PR." };

  const items: PrItemInput[] = [];
  for (const [i, r] of rows.entries()) {
    const n = i + 1;
    const name = (r.item_name ?? "").trim();
    if (!name) return { ok: false, error: `Barang baris ${n}: nama barang wajib diisi.` };
    if (name.length > 200) return { ok: false, error: `Barang baris ${n}: nama barang terlalu panjang.` };

    const qty = Number((r.qty ?? "").replace(",", "."));
    if (!(r.qty ?? "").trim() || !Number.isFinite(qty)) {
      return { ok: false, error: `Barang baris ${n}: jumlah harus berupa angka.` };
    }
    if (qty <= 0) return { ok: false, error: `Barang baris ${n}: jumlah harus lebih dari 0.` };
    if (qty >= 1e9) return { ok: false, error: `Barang baris ${n}: jumlah terlalu besar.` };

    if (!uuid.safeParse(r.unit_id).success) {
      return { ok: false, error: `Barang baris ${n}: satuan belum dipilih.` };
    }

    const parsedPrice = parseMoney(r.estimated_price ?? "");
    if (parsedPrice === "invalid") {
      return { ok: false, error: `Barang baris ${n}: estimasi harga harus berupa angka, tidak boleh negatif.` };
    }
    const price: number | null = parsedPrice;

    const productId = (r.product_id ?? "").trim();
    if (productId && !uuid.safeParse(productId).success) {
      return { ok: false, error: `Barang baris ${n}: produk tidak valid.` };
    }

    items.push({
      product_id: productId || null,
      item_name: name,
      qty,
      unit_id: r.unit_id,
      estimated_price: price,
      notes: (r.notes ?? "").trim() || null,
    });
  }
  return { ok: true, data: { reason, priority: raw.priority as PrInput["priority"], items } };
}
