// Format tampilan Qurban Cerdas. Murni tampilan; semua hitungan uang dilakukan database.
const BLN = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];

export const rp = (n: number | string | null | undefined) =>
  "Rp " + Math.round(Number(n ?? 0)).toLocaleString("id-ID");
export const kg = (n: number | string | null | undefined) =>
  Number(n ?? 0).toLocaleString("id-ID", { maximumFractionDigits: 2 }) + " Kg";
export const tgl = (iso: string | null | undefined) => {
  if (!iso) return "-";
  const [y, m, d] = iso.slice(0, 10).split("-").map(Number);
  return `${d} ${BLN[m - 1]} ${y}`;
};
export const bulan = (ym: string) => {
  const [y, m] = ym.split("-").map(Number);
  return `${BLN[m - 1]} ${y}`;
};

export const STATUS_LABEL: Record<string, string> = {
  PROFORMA: "Proforma", INVOICE: "Menunggu bayar", PAID: "Lunas", CANCELLED: "Dibatalkan", ISSUED: "Menunggu bayar",
};
export const STATUS_STYLE: Record<string, string> = {
  PROFORMA: "bg-neutral-200 text-neutral-900",
  INVOICE: "bg-amber-200 text-amber-950",
  ISSUED: "bg-amber-200 text-amber-950",
  PAID: "bg-green-200 text-green-950",
  CANCELLED: "bg-red-200 text-red-950",
};
export const MODE_LABEL: Record<string, string> = { FULL: "Lunas di awal", MONTHLY: "Bayar per bulan" };
export const CHOICE_LABEL: Record<string, string> = {
  SELF: "Dipakai sendiri", SELL_OUT: "Dijual ke pihak lain", SELL_BACK: "Dijual kembali ke HMI",
};

export const todayIso = () => new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 10);
