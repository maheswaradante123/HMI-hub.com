"use client";

import Link from "next/link";
import { useActionState, useMemo, useState, useTransition } from "react";
import { pullPrItems, saveDoc, type DocFormState, type PrItemPull } from "@/app/(app)/d/actions";
import { parseMoney } from "@/lib/pricing/schema";
import { fmtRupiah } from "@/lib/docs/format";
import { JCP_AC, JCP_CODES, JCP_FLAGS, JCP_FLAG_BG, JCP_SUMMARY_LABELS, jcpTotals, planAmount, realAmount } from "@/lib/docs/jcp";

type Row = Record<string, string>;
const inp = "w-full rounded-md border-2 border-line bg-white px-2 py-2 text-base disabled:bg-background disabled:text-muted";
const lab = "mb-1 block text-sm font-semibold uppercase tracking-wide text-muted";
const money = (v: string) => { const n = parseMoney((v ?? "").trim()); return typeof n === "number" ? n : 0; };
const qty = (v: string) => { const n = Number(String(v ?? "").replace(",", ".")); return Number.isFinite(n) ? n : 0; };
const maybe = (v: string, f: (s: string) => number) => ((v ?? "").trim() === "" ? null : f(v));
const fmtIn = (n: number) => n.toLocaleString("id-ID");
const fmtQ = (n: number) => String(n).replace(".", ",");
const blank = (date = ""): Row => ({ trans_date: date, ac: "OPR", code: "", description: "", price: "", qty: "1", unit: "", flag: "NONE", pr_item_id: "", real_price: "", real_qty: "", proof: "" });

export function JcpForm({ id, status, initial, number, cancelHref }: {
  id: string; status: string; initial: { header: Row; lines: Row[] }; number: string; cancelHref: string;
}) {
  const locked = status === "ACC"; // setelah ACC Owner: hanya realisasi dan bukti
  const [state, action, pending] = useActionState<DocFormState, FormData>(saveDoc.bind(null, "jcp", id), {});
  const restored = useMemo(() => {
    if (!state.payload) return null;
    try { const p = JSON.parse(state.payload); return { header: (p.header ?? {}) as Row, lines: (p.children?.lines ?? []) as Row[] }; } catch { return null; }
  }, [state.payload]);
  const [h, setH] = useState<Row>(restored?.header ?? initial.header);
  const [lines, setLines] = useState<Row[]>(restored?.lines ?? (initial.lines.length ? initial.lines : [blank(initial.header.journal_date)]));
  const [msg, setMsg] = useState("");
  const [pull, setPull] = useState<PrItemPull[] | null>(null);
  const [pick, setPick] = useState<Set<string>>(new Set());
  const [paste, setPaste] = useState<string | null>(null);
  const [busy, start] = useTransition();

  const setLine = (i: number, k: string, v: string) => setLines((r) => r.map((x, j) => (j === i ? { ...x, [k]: v } : x)));
  const num = lines.map((l) => ({ price: money(l.price), qty: qty(l.qty), flag: l.flag, real_price: maybe(l.real_price, money), real_qty: maybe(l.real_qty, qty) }));
  const t = jcpTotals(num);

  const openPull = () => start(async () => {
    setMsg("");
    const res = await pullPrItems();
    if (res.error) { setMsg(res.error); return; }
    const used = new Set(lines.map((l) => l.pr_item_id).filter(Boolean));
    const items = (res.items ?? []).filter((x) => !used.has(x.pr_item_id));
    setPull(items); setPick(new Set(items.map((x) => x.pr_item_id)));
    if (!items.length) setMsg("Tidak ada item Purchase Request yang siap ditarik (harus berstatus Approved, Order atau Received dan belum ada di jurnal lain).");
  });
  const addPicked = () => {
    const add = (pull ?? []).filter((x) => pick.has(x.pr_item_id)).map((x) => ({ ...blank(h.journal_date), ac: x.ac, code: x.code, description: x.item_name, price: x.price ? fmtIn(x.price) : "", qty: fmtQ(x.qty), unit: x.unit, pr_item_id: x.pr_item_id }));
    const kept = lines.filter((l) => l.description.trim() || l.price.trim());
    setLines([...kept, ...add]); setPull(null); setMsg(`${add.length} item ditambahkan dari Purchase Request.`);
  };
  const applyPaste = () => {
    const rows = (paste ?? "").split(/\r?\n/).map((l) => l.split("\t")).filter((c) => c.some((x) => x.trim()));
    const add = rows.map((c) => ({ ...blank(h.journal_date), trans_date: /^\d{4}-\d{2}-\d{2}$/.test((c[0] ?? "").trim()) ? c[0].trim() : h.journal_date, ac: (c[1] ?? "").trim() || "OPR", code: (c[2] ?? "").trim(), description: (c[3] ?? "").trim(), price: (c[4] ?? "").replace(/[^\d.,]/g, ""), qty: (c[5] ?? "").replace(/[^\d.,]/g, "") || "1", unit: (c[6] ?? "").trim() }));
    setLines((x) => [...x.filter((l) => l.description.trim() || l.price.trim()), ...add]); setPaste(null);
  };

  const payload = JSON.stringify({ header: h, children: { lines } });
  return (
    <form action={action} noValidate className="max-w-[1600px]">
      <input type="hidden" name="payload" value={payload} />
      <div className="space-y-8 rounded-2xl border border-line bg-white p-6 shadow-sm">
        <section>
          <h2 className="mb-4 text-sm font-bold uppercase tracking-widest text-muted">Jurnal</h2>
          <div className="grid gap-4 md:grid-cols-4">
            <div><label className={lab}>Nomor</label><input className={`${inp} bg-background text-muted`} readOnly value={number || "Otomatis saat disimpan"} /></div>
            <div><label className={lab} htmlFor="jc-date">Tanggal jurnal *</label><input id="jc-date" type="date" className={inp} disabled={locked} value={h.journal_date ?? ""} onChange={(e) => setH((x) => ({ ...x, journal_date: e.target.value }))} /></div>
            <div className="md:col-span-2"><label className={lab} htmlFor="jc-pay">Keterangan pembayaran</label><input id="jc-pay" className={inp} value={h.pay_note ?? ""} onChange={(e) => setH((x) => ({ ...x, pay_note: e.target.value }))} /></div>
            <div><label className={lab} htmlFor="jc-in">Initiator</label><input id="jc-in" className={inp} value={h.initiator_name ?? ""} onChange={(e) => setH((x) => ({ ...x, initiator_name: e.target.value }))} /></div>
            <div><label className={lab} htmlFor="jc-int">Jabatan initiator</label><input id="jc-int" className={inp} value={h.initiator_title ?? ""} onChange={(e) => setH((x) => ({ ...x, initiator_title: e.target.value }))} /></div>
            <div><label className={lab} htmlFor="jc-ap">Approval</label><input id="jc-ap" className={inp} value={h.approver_name ?? ""} onChange={(e) => setH((x) => ({ ...x, approver_name: e.target.value }))} /></div>
            <div><label className={lab} htmlFor="jc-apt">Jabatan approval</label><input id="jc-apt" className={inp} value={h.approver_title ?? ""} onChange={(e) => setH((x) => ({ ...x, approver_title: e.target.value }))} /></div>
            <div className="md:col-span-4"><label className={lab} htmlFor="jc-note">Note</label><input id="jc-note" className={inp} value={h.notes ?? ""} onChange={(e) => setH((x) => ({ ...x, notes: e.target.value }))} /></div>
          </div>
        </section>

        <section>
          <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
            <h2 className="text-sm font-bold uppercase tracking-widest text-muted">Baris jurnal</h2>
            {!locked && <button type="button" onClick={openPull} disabled={busy} className="rounded-md border-2 border-brand px-4 py-2 font-semibold text-brand hover:bg-background disabled:opacity-60">Tarik dari Purchase Request</button>}
          </div>
          {locked && <p className="mb-3 rounded-md bg-warn-bg px-4 py-3">Jurnal sudah di-ACC Owner. Kolom rencana terkunci; isi harga, qty, dan bukti realisasi sesuai pembayaran sebenarnya. Kolom yang dikosongkan dianggap sama dengan rencana saat realisasi diselesaikan.</p>}
          {pull && pull.length > 0 && (
            <div className="mb-4 rounded-lg border-2 border-brand p-4">
              <p className="mb-2 font-semibold">Pilih item Purchase Request yang akan dibayar minggu ini</p>
              <ul className="max-h-72 space-y-1 overflow-auto">
                {pull.map((x) => (
                  <li key={x.pr_item_id}>
                    <label className="flex items-center gap-3 py-1">
                      <input type="checkbox" className="h-5 w-5" checked={pick.has(x.pr_item_id)} onChange={(e) => setPick((s) => { const n = new Set(s); if (e.target.checked) n.add(x.pr_item_id); else n.delete(x.pr_item_id); return n; })} />
                      <span><b>{x.pr_number}</b> · {x.item_name} · {fmtQ(x.qty)} {x.unit} · {fmtRupiah(x.price * x.qty)}</span>
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
          <datalist id="jcp-ac">{JCP_AC.map((a) => <option key={a} value={a} />)}</datalist>
          <datalist id="jcp-code">{JCP_CODES.map((a) => <option key={a} value={a} />)}</datalist>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[1700px] text-left">
              <thead><tr className="text-sm uppercase tracking-wide text-muted">
                <th className="w-8 pb-2">No</th><th className="w-36 pb-2">Tanggal</th><th className="w-24 pb-2">A/C</th><th className="w-24 pb-2">Kode</th><th className="pb-2">Description</th>
                <th className="w-32 pb-2 text-right">Price</th><th className="w-24 pb-2 text-right">Qty</th><th className="w-24 pb-2">Unit</th><th className="w-36 pb-2 text-right">Amount</th><th className="w-56 pb-2">Jenis baris</th>
                <th className="w-32 pb-2 text-right">Real. Price</th><th className="w-24 pb-2 text-right">Real. Qty</th><th className="w-36 pb-2 text-right">Real. Amount</th><th className="w-44 pb-2">Bukti</th><th className="w-10" />
              </tr></thead>
              <tbody>
                {lines.map((l, i) => {
                  const ra = realAmount(num[i], false);
                  return (
                    <tr key={i} className={`align-top ${JCP_FLAG_BG[l.flag] ?? ""}`}>
                      <td className="py-1 pr-1 pt-3 text-muted">{i + 1}</td>
                      <td className="py-1 pr-1"><input type="date" aria-label={`Tanggal ${i + 1}`} disabled={locked} className={inp} value={l.trans_date ?? ""} onChange={(e) => setLine(i, "trans_date", e.target.value)} /></td>
                      <td className="py-1 pr-1"><input list="jcp-ac" aria-label={`A/C ${i + 1}`} disabled={locked} className={inp} value={l.ac ?? ""} onChange={(e) => setLine(i, "ac", e.target.value.toUpperCase())} /></td>
                      <td className="py-1 pr-1"><input list="jcp-code" aria-label={`Kode ${i + 1}`} disabled={locked} className={inp} value={l.code ?? ""} onChange={(e) => setLine(i, "code", e.target.value.toUpperCase())} /></td>
                      <td className="py-1 pr-1"><input aria-label={`Description ${i + 1}`} disabled={locked} className={inp} value={l.description ?? ""} onChange={(e) => setLine(i, "description", e.target.value)} /></td>
                      <td className="py-1 pr-1"><input aria-label={`Price ${i + 1}`} disabled={locked} inputMode="decimal" className={`${inp} text-right`} value={l.price ?? ""} onChange={(e) => setLine(i, "price", e.target.value)} /></td>
                      <td className="py-1 pr-1"><input aria-label={`Qty ${i + 1}`} disabled={locked} inputMode="decimal" className={`${inp} text-right`} value={l.qty ?? ""} onChange={(e) => setLine(i, "qty", e.target.value)} /></td>
                      <td className="py-1 pr-1"><input aria-label={`Unit ${i + 1}`} disabled={locked} className={inp} value={l.unit ?? ""} onChange={(e) => setLine(i, "unit", e.target.value)} /></td>
                      <td className="py-1 pr-2 pt-3 text-right tabular-nums">{fmtRupiah(planAmount(num[i]))}</td>
                      <td className="py-1 pr-1"><select aria-label={`Jenis baris ${i + 1}`} disabled={locked} className={inp} value={l.flag} onChange={(e) => setLine(i, "flag", e.target.value)}>{JCP_FLAGS.map((f) => <option key={f.value} value={f.value}>{f.label}</option>)}</select></td>
                      <td className="py-1 pr-1"><input aria-label={`Real price ${i + 1}`} inputMode="decimal" className={`${inp} text-right`} value={l.real_price ?? ""} onChange={(e) => setLine(i, "real_price", e.target.value)} /></td>
                      <td className="py-1 pr-1"><input aria-label={`Real qty ${i + 1}`} inputMode="decimal" className={`${inp} text-right`} value={l.real_qty ?? ""} onChange={(e) => setLine(i, "real_qty", e.target.value)} /></td>
                      <td className="py-1 pr-2 pt-3 text-right tabular-nums">{ra === null ? "-" : fmtRupiah(ra)}</td>
                      <td className="py-1 pr-1"><input aria-label={`Bukti ${i + 1}`} className={inp} value={l.proof ?? ""} onChange={(e) => setLine(i, "proof", e.target.value)} /></td>
                      <td className="py-1 pt-2">{!locked && <button type="button" aria-label={`Hapus baris ${i + 1}`} disabled={lines.length === 1} onClick={() => setLines((x) => x.filter((_, j) => j !== i))} className="rounded-md px-2 py-1 text-xl text-danger hover:bg-danger-bg disabled:opacity-30">×</button>}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          {!locked && (
            <div className="mt-3 flex flex-wrap gap-3">
              <button type="button" onClick={() => setLines((x) => [...x, blank(x[x.length - 1]?.trans_date || h.journal_date)])} className="rounded-md border-2 border-brand px-5 py-2.5 text-lg font-semibold text-brand hover:bg-background">+ Tambah baris</button>
              <button type="button" onClick={() => setPaste(paste === null ? "" : null)} className="rounded-md border-2 border-line px-5 py-2.5 text-lg font-semibold hover:bg-background">Tempel dari Excel…</button>
            </div>
          )}
          {paste !== null && (
            <div className="mt-3">
              <label className={lab} htmlFor="jc-paste">Tempel kolom: Tanggal (YYYY-MM-DD), A/C, Kode, Description, Price, Qty, Unit (dipisah tab)</label>
              <textarea id="jc-paste" rows={5} className={inp} placeholder={"2026-04-04\tOPR\tBP\tKonsentrat\t200000\t140\tsak"} value={paste} onChange={(e) => setPaste(e.target.value)} />
              <button type="button" onClick={applyPaste} className="mt-2 rounded-md bg-brand px-5 py-2.5 font-semibold text-white">Isi baris</button>
            </div>
          )}
        </section>

        <section className="grid gap-2 rounded-lg bg-background p-4 text-lg md:max-w-xl">
          {JCP_SUMMARY_LABELS.map(([k, label]) => <p key={k} className="flex justify-between"><span>{label}</span><b>{fmtRupiah(t[k])}</b></p>)}
          <p className="text-sm text-muted">Penjumlahan per jenis baris: Normal dan Over Budget dihitung sebagai kebutuhan kas, baris merah (ditolak) dan kuning (dibayar non rekening CPJ) tidak, baris biru muda adalah uang masuk.</p>
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
