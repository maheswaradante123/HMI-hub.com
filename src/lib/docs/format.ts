import type { Col } from "./types.ts";

const idr = new Intl.NumberFormat("id-ID", { style: "currency", currency: "IDR", maximumFractionDigits: 0 });
const num = new Intl.NumberFormat("id-ID", { maximumFractionDigits: 3 });

export function getPath(row: unknown, path: string): unknown {
  let cur: unknown = row;
  for (const key of path.split(".")) {
    if (Array.isArray(cur)) cur = cur[0];
    if (cur === null || cur === undefined || typeof cur !== "object") return undefined;
    cur = (cur as Record<string, unknown>)[key];
  }
  if (Array.isArray(cur)) cur = cur[0];
  return cur;
}

export const fmtRupiah = (n: number) => idr.format(n);
export const fmtQty = (n: number) => num.format(n);
export const fmtDate = (d: string) => !d ? "" :
  new Date(d.length === 10 ? `${d}T00:00:00+07:00` : d).toLocaleDateString("id-ID", { day: "numeric", month: "short", year: "numeric", timeZone: "Asia/Jakarta" });
export const fmtDateTime = (d: string) =>
  new Date(d).toLocaleString("id-ID", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Asia/Jakarta" });

// Teks tampilan untuk satu sel. Status ditangani oleh komponen badge, bukan di sini.
export function cellText(col: Col, row: unknown): string {
  const v = getPath(row, col.path);
  if (v === null || v === undefined || v === "") return "-";
  switch (col.kind) {
    case "money": return fmtRupiah(Number(v));
    case "qty": return fmtQty(Number(v));
    case "pct": return `${fmtQty(Number(v))}%`;
    case "date": return fmtDate(String(v));
    case "datetime": return fmtDateTime(String(v));
    default: return String(v);
  }
}

export const isNumericKind = (k?: Col["kind"]) => k === "money" || k === "qty" || k === "pct";
