"use client";

import Link from "next/link";
import { useActionState, useMemo, useState, useTransition } from "react";
import { pullInvoiceIncome, pullReceivables, saveDoc, type DocFormState } from "@/app/(app)/d/actions";
import { parseMoney } from "@/lib/pricing/schema";
import { fmtRupiah } from "@/lib/docs/format";
import { PMT_COLS, pmtTotals, type PmtCol } from "@/lib/docs/pmt";

type Row = Record<string, string>;
const inp = "w-full rounded-md border-2 border-line bg-white px-2 py-2 text-base";
const lab = "mb-1 block text-sm font-semibold uppercase tracking-wide text-muted";
const COL_LABEL: Record<PmtCol, string> = { cash: "Cash", qris: "QRIS", debit: "Debit", grab: "Grab", tf: "TF Rek HMI", deposited: "Disetor" };
const blankLine = (date = ""): Row => ({ entry_date: date, description: "Pemasukan", cash: "", qris: "", debit: "", grab: "", tf: "", deposited: "", proof: "", invoice_id: "" });
const sm = (v: string) => {
  const t = (v ?? "").trim();
  if (!t) return 0;
  const neg = t.startsWith("-");
  const n = parseMoney(neg ? t.slice(1).trim() : t);
  return typeof n === "number" ? (neg ? -n : n) : 0;
};
const fmtIn = (n: number) => `${n < 0 ? "-" : ""}${Math.abs(n).toLocaleString("id-ID")}`;

export function PmtForm({ id, initial, number, cancelHref }: {
  id: string; initial: { header: Row; lines: Row[]; recv: Row[] }; number: string; cancelHref: string;
}) {
  const [state, action, pending] = useActionState<DocFormState, FormData>(saveDoc.bind(null, "pmt", id), {});
  const restored = useMemo(() => {
    if (!state.payload) return null;
    try { const p = JSON.parse(state.payload); return { header: (p.header ?? {}) as Row, lines: (p.children?.lines ?? []) as Row[], recv: (p.children?.recv ?? []) as Row[] }; } catch { return null; }
  }, [state.payload]);
  const [h, setH] = useState<Row>(restored?.header ?? initial.header);
  const [lines, setLines] = useState<Row[]>(restored?.lines ?? (initial.lines.length ? initial.lines : [blankLine()]));
  const [recv, setRecv] = useState<Row[]>(restored?.recv ?? initial.recv);
  const [msg, setMsg] = useState("");
  const [busy, start] = useTransition();

  const setLine = (i: number, k: string, v: string) => setLines((r) => r.map((x, j) => (j === i ? { ...x, [k]: v } : x)));
  const setRecvRow = (i: number, k: string, v: string) => setRecv((r) => r.map((x, j) => (j === i ? { ...x, [k]: v } : x)));
  const t = pmtTotals(lines.map((l) => Object.fromEntries(PMT_COLS.map((c) => [c, sm(l[c] ?? "")]))), recv.map((r) => ({ amount: sm(r.amount ?? "") })));

  const pullInv = () => start(async () => {
    setMsg("");
    const res = await pullInvoiceIncome(h.period_from ?? "", h.period_to ?? "");
    if (res.error) { setMsg(res.error); return; }
    const have = new Set(lines.map((l) => l.invoice_id).filter(Boolean));
    const add: Row[] = (res.lines ?? []).filter((l) => !have.has(l.invoice_id) || !l.invoice_id)
      .map((l) => ({ ...blankLine(l.entry_date), description: l.description, tf: fmtIn(l.tf), invoice_id: l.invoice_id }));
    const kept = lines.filter((l) => l.description.trim() !== "Pemasukan" || PMT_COLS.some((c) => (l[c] ?? "").trim()) || l.invoice_id);
    setLines([...kept, ...add].sort((a, b) => (a.entry_date || "9").localeCompare(b.entry_date || "9")));
    setMsg(add.length ? `${add.length} baris pembayaran invoice ditambahkan.` : "Tidak ada pembayaran invoice baru pada periode ini.");
  });
  const pullRecv = () => start(async () => {
    setMsg("");
    const res = await pullReceivables();
    if (res.error) { setMsg(res.error); return; }
    const manual = recv.filter((r) => !(res.recv ?? []).some((x) => x.name === r.name));
    setRecv([...(res.recv ?? []).map((x) => ({ name: x.name, amount: fmtIn(x.amount) })), ...manual]);
    setMsg(`Piutang diperbarui dari invoice yang belum lunas (${(res.recv ?? []).length} pelanggan).`);
  });

  const payload = JSON.stringify({ header: h, children: { lines, recv } });
  return (
    <form action={action} noValidate className="max-w-[1400px]">
      <input type="hidden" name="payload" value={payload} />
      <div className="space-y-8 rounded-2xl border border-line bg-white p-6 shadow-sm">
        <section>
          <h2 className="mb-4 text-sm font-bold uppercase tracking-widest text-muted">Periode</h2>
          <div className="grid gap-4 md:grid-cols-4">
            <div><label className={lab}>Nomor</label><input className={`${inp} bg-background text-muted`} readOnly value={number || "Otomatis saat disimpan"} /></div>
            <div><label className={lab} htmlFor="pm-from">Dari *</label><input id="pm-from" type="date" className={inp} value={h.period_from ?? ""} onChange={(e) => setH((x) => ({ ...x, period_from: e.target.value }))} /></div>
            <div><label className={lab} htmlFor="pm-to">Sampai *</label><input id="pm-to" type="date" className={inp} value={h.period_to ?? ""} onChange={(e) => setH((x) => ({ ...x, period_to: e.target.value }))} /></div>
            <div><label className={lab} htmlFor="pm-note">Catatan</label><input id="pm-note" className={inp} value={h.notes ?? ""} onChange={(e) => setH((x) => ({ ...x, notes: e.target.value }))} /></div>
          </div>
        </section>

        <section>
          <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
            <h2 className="text-sm font-bold uppercase tracking-widest text-muted">Pemasukan</h2>
            <button type="button" onClick={pullInv} disabled={busy} className="rounded-md border-2 border-brand px-4 py-2 font-semibold text-brand hover:bg-background disabled:opacity-60">Tarik pembayaran invoice</button>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[1200px] text-left">
              <thead><tr className="text-sm uppercase tracking-wide text-muted">
                <th className="w-8 pb-2">No</th><th className="w-36 pb-2">Tanggal</th><th className="pb-2">Deskripsi</th>
                {PMT_COLS.map((c) => <th key={c} className="w-32 pb-2 text-right">{COL_LABEL[c]}</th>)}
                <th className="w-36 pb-2">Bukti</th><th className="w-10" />
              </tr></thead>
              <tbody>
                {lines.map((l, i) => (
                  <tr key={i} className="align-top">
                    <td className="py-1 pr-1 pt-3 text-muted">{i + 1}</td>
                    <td className="py-1 pr-1"><input type="date" aria-label={`Tanggal ${i + 1}`} className={inp} value={l.entry_date ?? ""} onChange={(e) => setLine(i, "entry_date", e.target.value)} /></td>
                    <td className="py-1 pr-1"><input aria-label={`Deskripsi ${i + 1}`} className={inp} value={l.description ?? ""} onChange={(e) => setLine(i, "description", e.target.value)} /></td>
                    {PMT_COLS.map((c) => <td key={c} className="py-1 pr-1"><input aria-label={`${COL_LABEL[c]} ${i + 1}`} className={`${inp} text-right`} inputMode="text" value={l[c] ?? ""} onChange={(e) => setLine(i, c, e.target.value)} /></td>)}
                    <td className="py-1 pr-1"><input aria-label={`Bukti ${i + 1}`} className={inp} value={l.proof ?? ""} onChange={(e) => setLine(i, "proof", e.target.value)} /></td>
                    <td className="py-1 pt-2"><button type="button" aria-label={`Hapus baris ${i + 1}`} disabled={lines.length === 1} onClick={() => setLines((x) => x.filter((_, j) => j !== i))} className="rounded-md px-2 py-1 text-xl text-danger hover:bg-danger-bg disabled:opacity-30">×</button></td>
                  </tr>
                ))}
                <tr className="border-t-2 border-line font-bold">
                  <td /><td /><td className="py-3 text-right text-lg">Total</td>
                  {PMT_COLS.map((c) => <td key={c} className="py-3 pr-3 text-right">{fmtRupiah(t[c])}</td>)}<td /><td />
                </tr>
              </tbody>
            </table>
          </div>
          <div className="mt-3 flex flex-wrap gap-3">
            <button type="button" onClick={() => setLines((x) => [...x, blankLine(x[x.length - 1]?.entry_date ?? "")])} className="rounded-md border-2 border-brand px-5 py-2.5 text-lg font-semibold text-brand hover:bg-background">+ Tambah baris</button>
            <button type="button" onClick={() => setLines((x) => [...x, { ...blankLine(x[x.length - 1]?.entry_date ?? ""), description: "Penyetoran" }])} className="rounded-md border-2 border-line px-5 py-2.5 text-lg font-semibold hover:bg-background">+ Penyetoran</button>
          </div>
          <p className="mt-2 text-sm text-muted">Pengeluaran kas ditulis dengan tanda minus di kolom Cash, misalnya -200.000.</p>
        </section>

        <section>
          <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
            <h2 className="text-sm font-bold uppercase tracking-widest text-muted">Piutang</h2>
            <button type="button" onClick={pullRecv} disabled={busy} className="rounded-md border-2 border-brand px-4 py-2 font-semibold text-brand hover:bg-background disabled:opacity-60">Tarik piutang saat ini</button>
          </div>
          <div className="space-y-2">
            {recv.map((r, i) => (
              <div key={i} className="flex gap-2">
                <input aria-label={`Nama piutang ${i + 1}`} className={`${inp} max-w-sm`} placeholder="Nama pelanggan" value={r.name ?? ""} onChange={(e) => setRecvRow(i, "name", e.target.value)} />
                <input aria-label={`Jumlah piutang ${i + 1}`} className={`${inp} max-w-[11rem] text-right`} value={r.amount ?? ""} onChange={(e) => setRecvRow(i, "amount", e.target.value)} />
                <button type="button" aria-label={`Hapus piutang ${i + 1}`} onClick={() => setRecv((x) => x.filter((_, j) => j !== i))} className="rounded-md px-3 text-xl text-danger hover:bg-danger-bg">×</button>
              </div>
            ))}
          </div>
          <button type="button" onClick={() => setRecv((x) => [...x, { name: "", amount: "" }])} className="mt-3 rounded-md border-2 border-line px-5 py-2.5 text-lg font-semibold hover:bg-background">+ Tambah piutang manual</button>
        </section>

        <section className="grid gap-2 rounded-lg bg-background p-4 text-lg md:max-w-xl">
          <p className="flex justify-between"><span>Uang cash yang harus disetor</span><b>{fmtRupiah(t.mustDeposit)}</b></p>
          <p className="flex justify-between"><span>Total piutang</span><b>{fmtRupiah(t.receivables)}</b></p>
          <p className="flex justify-between border-t border-line pt-2 text-xl"><span>Total Pendapatan</span><b>{fmtRupiah(t.income)}</b></p>
        </section>

        {msg && <p role="status" className="rounded-md bg-warn-bg px-4 py-3">{msg}</p>}
        {state.error && <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-lg text-danger">{state.error}</p>}
        <div className="flex gap-3">
          <button type="submit" disabled={pending} className="rounded-md bg-brand px-8 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Menyimpan..." : "Simpan laporan"}</button>
          <Link href={cancelHref} className="rounded-md border-2 border-line px-8 py-3 text-lg font-semibold hover:bg-background">Batal</Link>
        </div>
      </div>
    </form>
  );
}
