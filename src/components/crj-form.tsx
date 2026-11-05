"use client";

import Link from "next/link";
import { useActionState, useMemo, useState, useTransition } from "react";
import { pullCrj, saveDoc, type DocFormState } from "@/app/(app)/d/actions";
import { parseMoney } from "@/lib/pricing/schema";
import { fmtRupiah } from "@/lib/docs/format";
import { CRJ_PULLABLE, CRJ_SOURCES, CRJ_SOURCE_LABEL, sumBy, type CrjPullRow } from "@/lib/docs/crj";

type Row = Record<string, string>;
export type CrjAccount = { id: string; name: string };
const inp = "w-full rounded-md border-2 border-line bg-white px-2 py-2 text-base";
const lab = "mb-1 block text-sm font-semibold uppercase tracking-wide text-muted";
const money = (v: string) => { const n = parseMoney((v ?? "").trim()); return typeof n === "number" ? n : 0; };
const fmtIn = (n: number) => n.toLocaleString("id-ID");
const blank = (date = ""): Row => ({ source: "OTHER", trans_date: date, description: "", account_id: "", amount: "", proof: "", invoice_id: "", ncs_id: "", qurban_order_id: "", qurban_bill_id: "", src_ref: "" });
const REF_BY_SOURCE: Record<string, string> = { QURBAN_CLOSING: "qurban_order_id", QURBAN_CARE: "qurban_bill_id", HOREKA: "invoice_id", NONKARKAS: "ncs_id" };
const keyOf = (source: string, r: { ref_id?: string; src_ref?: string }) => `${source}|${REF_BY_SOURCE[source] ? r.ref_id : r.src_ref}`;
const rowKey = (l: Row) => `${l.source}|${REF_BY_SOURCE[l.source] ? l[REF_BY_SOURCE[l.source]] : l.src_ref}`;

export function CrjForm({ id, initial, number, cancelHref, accounts }: {
  id: string; initial: { header: Row; lines: Row[] }; number: string; cancelHref: string; accounts: CrjAccount[];
}) {
  const [state, action, pending] = useActionState<DocFormState, FormData>(saveDoc.bind(null, "jcr", id), {});
  const restored = useMemo(() => {
    if (!state.payload) return null;
    try { const p = JSON.parse(state.payload); return { header: (p.header ?? {}) as Row, lines: (p.children?.lines ?? []) as Row[] }; } catch { return null; }
  }, [state.payload]);
  const [h, setH] = useState<Row>(restored?.header ?? initial.header);
  const [lines, setLines] = useState<Row[]>(restored?.lines ?? (initial.lines.length ? initial.lines : [blank(initial.header.period_to)]));
  const [msg, setMsg] = useState("");
  const [pull, setPull] = useState<{ source: string; rows: CrjPullRow[] } | null>(null);
  const [pick, setPick] = useState<Set<number>>(new Set());
  const [busy, start] = useTransition();
  const accName = useMemo(() => new Map(accounts.map((a) => [a.id, a.name])), [accounts]);

  const setLine = (i: number, k: string, v: string) => setLines((r) => r.map((x, j) => (j === i ? { ...x, [k]: v } : x)));
  const filled = lines.filter((l) => l.description.trim() || l.amount.trim());
  const total = filled.reduce((s, l) => s + money(l.amount), 0);
  const perSource = sumBy(filled, (l) => l.source, (l) => money(l.amount));
  const perAccount = sumBy(filled, (l) => accName.get(l.account_id) ?? "(rekening belum dipilih)", (l) => money(l.amount));

  const openPull = (source: string) => start(async () => {
    setMsg("");
    const res = await pullCrj(source, h.period_from ?? "", h.period_to ?? "");
    if (res.error) { setMsg(res.error); setPull(null); return; }
    const used = new Set(lines.map(rowKey));
    const rows = (res.rows ?? []).filter((r) => !used.has(keyOf(source, r)));
    setPull({ source, rows }); setPick(new Set(rows.map((_, i) => i)));
    if (!rows.length) setMsg(`Tidak ada ${CRJ_SOURCE_LABEL[source].toLowerCase()} yang bisa ditarik untuk periode ini (atau semuanya sudah ada di jurnal ini atau jurnal lain).`);
  });
  const addPicked = () => {
    if (!pull) return;
    const add = pull.rows.filter((_, i) => pick.has(i)).map((r) => {
      const base = { ...blank(r.trans_date), source: pull.source, description: r.description, amount: fmtIn(r.amount), account_id: r.account_id, src_ref: r.src_ref };
      const refCol = REF_BY_SOURCE[pull.source];
      return refCol ? { ...base, [refCol]: r.ref_id, src_ref: "" } : base;
    });
    setLines([...lines.filter((l) => l.description.trim() || l.amount.trim()), ...add]);
    setMsg(`${add.length} baris ditambahkan dari ${CRJ_SOURCE_LABEL[pull.source]}.`); setPull(null);
  };

  const payload = JSON.stringify({ header: h, children: { lines } });
  return (
    <form action={action} noValidate className="max-w-[1500px]">
      <input type="hidden" name="payload" value={payload} />
      <div className="space-y-8 rounded-2xl border border-line bg-white p-6 shadow-sm">
        <section>
          <h2 className="mb-4 text-sm font-bold uppercase tracking-widest text-muted">Jurnal penerimaan</h2>
          <div className="grid gap-4 md:grid-cols-4">
            <div><label className={lab}>Nomor</label><input className={`${inp} bg-background text-muted`} readOnly value={number || "Otomatis saat disimpan"} /></div>
            <div><label className={lab} htmlFor="cr-from">Periode dari *</label><input id="cr-from" type="date" className={inp} value={h.period_from ?? ""} onChange={(e) => setH((x) => ({ ...x, period_from: e.target.value }))} /></div>
            <div><label className={lab} htmlFor="cr-to">Periode sampai *</label><input id="cr-to" type="date" className={inp} value={h.period_to ?? ""} onChange={(e) => setH((x) => ({ ...x, period_to: e.target.value }))} /></div>
            <div><label className={lab} htmlFor="cr-note">Catatan</label><input id="cr-note" className={inp} value={h.notes ?? ""} onChange={(e) => setH((x) => ({ ...x, notes: e.target.value }))} /></div>
          </div>
        </section>

        <section>
          <h2 className="mb-1 text-sm font-bold uppercase tracking-widest text-muted">Tarik dari</h2>
          <p className="mb-3 text-muted">Closing, pemeliharaan, dan semua kolom Pemasukan Toko (QRIS, Debit, TF Rek HMI, Disetor) mengikuti periode di atas. QRIS atau Debit yang belum dipecah per bank di Pemasukan Toko tidak ikut tertarik. Tempo Horeka menampilkan semua invoice yang masih ada sisa tagihan.</p>
          <div className="flex flex-wrap gap-2">
            {CRJ_PULLABLE.map((s) => (
              <button key={s.value} type="button" onClick={() => openPull(s.value)} disabled={busy} className="rounded-md border-2 border-brand px-4 py-2 font-semibold text-brand hover:bg-background disabled:opacity-60">{s.label}</button>
            ))}
          </div>
          {pull && pull.rows.length > 0 && (
            <div className="mt-4 rounded-lg border-2 border-brand p-4">
              <p className="mb-2 font-semibold">{CRJ_SOURCE_LABEL[pull.source]}: pilih baris yang masuk jurnal ini</p>
              <ul className="max-h-80 space-y-1 overflow-auto">
                {pull.rows.map((r, i) => (
                  <li key={i}>
                    <label className="flex items-start gap-3 py-1">
                      <input type="checkbox" className="mt-1 h-5 w-5" checked={pick.has(i)} onChange={(e) => setPick((s) => { const n = new Set(s); if (e.target.checked) n.add(i); else n.delete(i); return n; })} />
                      <span>{r.trans_date} · {r.description} · <b>{fmtRupiah(r.amount)}</b>{r.account_id ? ` · ${accName.get(r.account_id) ?? ""}` : ""}</span>
                    </label>
                  </li>
                ))}
              </ul>
              <div className="mt-3 flex gap-3">
                <button type="button" onClick={addPicked} disabled={!pick.size} className="rounded-md bg-brand px-5 py-2.5 font-semibold text-white disabled:opacity-60">Tambahkan yang dicentang</button>
                <button type="button" onClick={() => setPull(null)} className="rounded-md border-2 border-line px-5 py-2.5 font-semibold hover:bg-background">Tutup</button>
              </div>
            </div>
          )}
        </section>

        <section>
          <h2 className="mb-3 text-sm font-bold uppercase tracking-widest text-muted">Baris penerimaan</h2>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[1250px] text-left">
              <thead><tr className="text-sm uppercase tracking-wide text-muted">
                <th className="w-8 pb-2">No</th><th className="w-44 pb-2">Sumber</th><th className="w-36 pb-2">Tanggal</th><th className="pb-2">Keterangan</th>
                <th className="w-56 pb-2">Rekening/Kas *</th><th className="w-40 pb-2 text-right">Jumlah</th><th className="w-44 pb-2">Bukti</th><th className="w-10" />
              </tr></thead>
              <tbody>
                {lines.map((l, i) => {
                  const locked = l.source !== "OTHER"; // baris tarikan: sumber dan keterangan tetap, jumlah tetap boleh disesuaikan (bayar sebagian)
                  return (
                    <tr key={i} className="align-top">
                      <td className="py-1 pr-1 pt-3 text-muted">{i + 1}</td>
                      <td className="py-1 pr-1">
                        <select aria-label={`Sumber ${i + 1}`} disabled={locked} className={inp} value={l.source} onChange={(e) => setLine(i, "source", e.target.value)}>
                          {CRJ_SOURCES.filter((s) => !locked || s.value === l.source || s.value === "OTHER").map((s) => <option key={s.value} value={s.value}>{s.short}</option>)}
                        </select>
                      </td>
                      <td className="py-1 pr-1"><input type="date" aria-label={`Tanggal ${i + 1}`} className={inp} value={l.trans_date ?? ""} onChange={(e) => setLine(i, "trans_date", e.target.value)} /></td>
                      <td className="py-1 pr-1"><input aria-label={`Keterangan ${i + 1}`} className={inp} value={l.description ?? ""} onChange={(e) => setLine(i, "description", e.target.value)} /></td>
                      <td className="py-1 pr-1">
                        <select aria-label={`Rekening ${i + 1}`} className={`${inp} ${l.account_id ? "" : "border-danger"}`} value={l.account_id ?? ""} onChange={(e) => setLine(i, "account_id", e.target.value)}>
                          <option value="">Pilih rekening/kas</option>
                          {accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
                        </select>
                      </td>
                      <td className="py-1 pr-1"><input aria-label={`Jumlah ${i + 1}`} inputMode="decimal" className={`${inp} text-right`} value={l.amount ?? ""} onChange={(e) => setLine(i, "amount", e.target.value)} /></td>
                      <td className="py-1 pr-1"><input aria-label={`Bukti ${i + 1}`} className={inp} value={l.proof ?? ""} onChange={(e) => setLine(i, "proof", e.target.value)} /></td>
                      <td className="py-1 pt-2"><button type="button" aria-label={`Hapus baris ${i + 1}`} disabled={lines.length === 1} onClick={() => setLines((x) => x.filter((_, j) => j !== i))} className="rounded-md px-2 py-1 text-xl text-danger hover:bg-danger-bg disabled:opacity-30">×</button></td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          <div className="mt-3">
            <button type="button" onClick={() => setLines((x) => [...x, blank(h.period_to)])} className="rounded-md border-2 border-brand px-5 py-2.5 text-lg font-semibold text-brand hover:bg-background">+ Tambah baris lain</button>
          </div>
        </section>

        <section className="grid gap-6 rounded-lg bg-background p-4 text-lg md:grid-cols-2">
          <div>
            <p className="mb-1 text-sm font-bold uppercase tracking-widest text-muted">Per sumber</p>
            {perSource.length === 0 ? <p className="text-muted">Belum ada baris.</p> : perSource.map(([k, v]) => <p key={k} className="flex justify-between"><span>{CRJ_SOURCE_LABEL[k] ?? k}</span><b>{fmtRupiah(v)}</b></p>)}
          </div>
          <div>
            <p className="mb-1 text-sm font-bold uppercase tracking-widest text-muted">Per rekening/kas</p>
            {perAccount.length === 0 ? <p className="text-muted">Belum ada baris.</p> : perAccount.map(([k, v]) => <p key={k} className="flex justify-between"><span>{k}</span><b>{fmtRupiah(v)}</b></p>)}
          </div>
          <p className="flex justify-between border-t border-line pt-2 text-xl md:col-span-2"><span>Total diterima</span><b>{fmtRupiah(total)}</b></p>
        </section>

        {msg && <p role="status" className="rounded-md bg-warn-bg px-4 py-3">{msg}</p>}
        {state.error && <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-lg text-danger">{state.error}</p>}
        <div className="flex gap-3">
          <button type="submit" disabled={pending} className="rounded-md bg-brand px-8 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Menyimpan..." : "Simpan jurnal"}</button>
          <Link href={cancelHref} className="rounded-md border-2 border-line px-8 py-3 text-lg font-semibold hover:bg-background">Batal</Link>
        </div>
      </div>
    </form>
  );
}
