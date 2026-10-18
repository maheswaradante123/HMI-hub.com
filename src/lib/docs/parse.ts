import { isRealDate, parseMoney } from "../pricing/schema.ts";
import type { Field, DocConfig, Child } from "./types.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Jumlah/berat: titik atau koma sebagai desimal (maksimal 3 angka), tanpa pemisah ribuan.
export function parseQty(raw: string): number | null | "invalid" {
  const t = raw.replace(/\s/g, "");
  if (t === "") return null;
  if (!/^\d{1,9}([.,]\d{1,3})?$/.test(t)) return "invalid";
  const n = Number(t.replace(",", "."));
  return Number.isFinite(n) ? n : "invalid";
}

export type Value = string | number | null;
export type Row = Record<string, Value>;
export type Parsed = { ok: true; header: Row; children: Record<string, Row[]> } | { ok: false; error: string };
export type Payload = { header?: Record<string, string>; children?: Record<string, Record<string, string>[]> };

function parseField(f: Field, raw: string, where: string): { v: Value } | { error: string } {
  const t = (raw ?? "").trim();
  if (t === "") {
    if (f.blankAs0 && (f.kind === "money" || f.kind === "qty")) return { v: 0 };
    if (f.required) return { error: `${where}${f.label} wajib diisi.` };
    return { v: null };
  }
  switch (f.kind) {
    case "date":
      return isRealDate(t) ? { v: t } : { error: `${where}${f.label} bukan tanggal yang benar.` };
    case "qty": {
      const n = parseQty(t);
      if (n === "invalid" || n === null) return { error: `${where}${f.label} harus berupa angka (contoh 12,5), maksimal 3 angka di belakang koma.` };
      return { v: n };
    }
    case "money": {
      const n = parseMoney(t);
      if (n === "invalid" || n === null) return { error: `${where}${f.label} harus berupa angka rupiah (contoh 135.000), tidak boleh negatif.` };
      return { v: n };
    }
    case "smoney": {
      // Rupiah boleh negatif (mis. pengeluaran kas yang mengurangi Cash).
      const neg = t.startsWith("-");
      const n = parseMoney(neg ? t.slice(1).trim() : t);
      if (n === "invalid" || n === null) return { error: `${where}${f.label} harus berupa angka rupiah (contoh 135.000 atau -50.000).` };
      return { v: neg ? -n : n };
    }
    case "ref":
      return UUID.test(t) ? { v: t } : { error: `${where}${f.label} belum dipilih dengan benar.` };
    case "select":
      return f.options?.some((o) => o.value === t) ? { v: t } : { error: `${where}${f.label} belum dipilih dengan benar.` };
    default: {
      if (t.length > 1000) return { error: `${where}${f.label} terlalu panjang (maksimal 1000 huruf).` };
      return { v: f.upper ? t.toUpperCase() : t };
    }
  }
}

function parseRow(fields: Field[], raw: Record<string, string>, where: string): { row: Row } | { error: string } {
  const row: Row = {};
  for (const f of fields) {
    const r = parseField(f, raw[f.name] ?? "", where);
    if ("error" in r) return r;
    row[f.name] = r.v;
  }
  return { row };
}

const isBlankRow = (c: Child, raw: Record<string, string>) =>
  c.fields.every((f) => (raw[f.name] ?? "").trim() === "" || (f.blankAs0 && (raw[f.name] ?? "").trim() === "0"));

export function parseDoc(cfg: DocConfig, payload: Payload): Parsed {
  const header = parseRow(cfg.header, payload.header ?? {}, "");
  if ("error" in header) return { ok: false, error: header.error };

  const children: Record<string, Row[]> = {};
  for (const c of cfg.children) {
    const rows: Row[] = [];
    const src = (payload.children?.[c.key] ?? []).filter((r) => !isBlankRow(c, r));
    if (src.length > 200) return { ok: false, error: `${c.title}: terlalu banyak baris (maksimal 200).` };
    for (let i = 0; i < src.length; i++) {
      const r = parseRow(c.fields, src[i], `${c.title} baris ${i + 1}: `);
      if ("error" in r) return { ok: false, error: r.error };
      if (c.exclusive) {
        const [a, b] = c.exclusive;
        if ((r.row[a] === null) === (r.row[b] === null)) {
          return { ok: false, error: `${c.title} baris ${i + 1}: isi salah satu saja.` };
        }
      }
      rows.push(r.row);
    }
    if (c.required && rows.length === 0) return { ok: false, error: `${c.title}: isi minimal satu baris.` };
    // Produk atau jenis yang sama tidak boleh dobel dalam satu dokumen.
    for (const f of c.fields.filter((x) => x.kind === "ref" && x.name !== "unused")) {
      const seen = new Set<string>();
      for (const r of rows) {
        const v = r[f.name];
        if (typeof v !== "string") continue;
        if (seen.has(v) && ["product_id", "non_carcass_type_id"].includes(f.name)) {
          return { ok: false, error: `${c.title}: ${f.label} yang sama diisi lebih dari sekali. Gabungkan jadi satu baris.` };
        }
        seen.add(v);
      }
    }
    children[c.key] = rows;
  }
  return { ok: true, header: header.row, children };
}

// Untuk total berjalan di form (tampilan saja; perhitungan resmi dilakukan database).
export function lineTotal(qty: string, price: string): number {
  const q = parseQty(qty);
  const p = parseMoney(price === "" ? "0" : price);
  if (typeof q !== "number" || typeof p !== "number") return 0;
  return q * p;
}
