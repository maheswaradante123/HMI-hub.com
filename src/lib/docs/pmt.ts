// Perhitungan laporan Pemasukan Toko. Rumus dari Excel Owner:
//   Uang cash yang harus disetor = Total Cash - Total Disetor
//   Total Pendapatan = uang cash yang harus disetor + Cash + QRIS + Debit + Grab + TF Rek HMI + semua piutang
export const PMT_COLS = ["cash", "qris", "debit", "grab", "tf", "deposited"] as const;
export type PmtCol = (typeof PMT_COLS)[number];
export type PmtTotals = Record<PmtCol, number> & { mustDeposit: number; receivables: number; income: number };

export function pmtTotals(lines: Partial<Record<PmtCol, number | null>>[], recv: { amount: number | null }[]): PmtTotals {
  const t = { cash: 0, qris: 0, debit: 0, grab: 0, tf: 0, deposited: 0 } as Record<PmtCol, number>;
  for (const l of lines) for (const c of PMT_COLS) t[c] += Number(l[c] ?? 0);
  const receivables = recv.reduce((s, r) => s + Number(r.amount ?? 0), 0);
  const mustDeposit = t.cash - t.deposited;
  return { ...t, mustDeposit, receivables, income: mustDeposit + t.cash + t.qris + t.debit + t.grab + t.tf + receivables };
}
