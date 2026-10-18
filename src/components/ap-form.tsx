"use client";

import Link from "next/link";
import { useActionState, useMemo, useState } from "react";
import { saveDoc, type DocFormState } from "@/app/(app)/d/actions";
import { parseMoney } from "@/lib/pricing/schema";
import { parseQty } from "@/lib/docs/parse";
import { fmtRupiah } from "@/lib/docs/format";
import { AP_COST_UNIT, AP_UNIT, apNumberPreview, apTotals, syncApItems, type ApItemRow } from "@/lib/docs/ap";
import type { ApLists } from "@/lib/docs/ap-lists";

type Row = Record<string, string>;
type Item = ApItemRow;
type Init = { header: Row; cows: string[]; items: Item[]; nonk: Row[]; costs: Row[] };

const inp = "w-full rounded-md border-2 border-line bg-white px-2 py-2 text-base disabled:bg-background disabled:text-muted";
const lab = "mb-1 block text-sm font-semibold uppercase tracking-wide text-muted";
const money = (v: string) => { const n = parseMoney((v ?? "").trim()); return typeof n === "number" ? n : 0; };
const qty = (v: string) => { const n = parseQty((v ?? "").trim()); return typeof n === "number" ? n : 0; };
const fmtIn = (n: number) => n.toLocaleString("id-ID");
const fmtQ = (n: number) => String(Math.round(n * 1000) / 1000).replace(".", ",");
const TABS = [["ringkas", "Ringkasan"], ["item", "Hasil Penjualan Item"], ["nonk", "Penjualan Non-Karkas"], ["biaya", "Biaya"]] as const;

export function ApForm({ id, initial, lists, number, cancelHref }: { id: string; initial: Init; lists: ApLists; number: string; cancelHref: string }) {
  const [state, action, pending] = useActionState<DocFormState, FormData>(saveDoc.bind(null, "ap", id), {});
  const restored = useMemo(() => {
    if (!state.payload) return null;
    try {
      const p = JSON.parse(state.payload);
      const c = p.children ?? {};
      return { header: (p.header ?? {}) as Row, cows: ((c.cows ?? []) as Row[]).map((x) => x.cw_id), items: (c.items ?? []) as Item[], nonk: (c.nonk ?? []) as Row[], costs: (c.costs ?? []) as Row[] } satisfies Init;
    } catch { return null; }
  }, [state.payload]);
  const start = restored ?? initial;
  const [tab, setTab] = useState<(typeof TABS)[number][0]>("ringkas");
  const [h, setH] = useState<Row>(start.header);
  const [cows, setCows] = useState<string[]>(start.cows);
  const [items, setItems] = useState<Item[]>(start.items);
  const [nonk, setNonk] = useState<Row[]>(start.nonk.length ? start.nonk : [{ name: "", weight: "", unit_price: "" }]);
  const [costs, setCosts] = useState<Row[]>(start.costs.length ? start.costs : [{ cost_type_id: "", amount: "", note: "" }]);
  const [manual, setManual] = useState<boolean>((start.header.manual_total_cost ?? "") !== "");
  const [pick, setPick] = useState("");

  const cowOf = (cid: string) => lists.cows.find((c) => c.id === cid);
  const prod = (pid: string) => lists.products.find((p) => p.id === pid);
  const setHead = (k: string, v: string) => setH((x) => ({ ...x, [k]: v }));

  const changeCows = (ids: string[]) => {
    setCows(ids); setItems((p) => syncApItems(ids, lists.cows, lists.products, p));
    const first = cowOf(ids[0]);
    if (first) setH((x) => ({ ...x, supplier_id: x.supplier_id || first.supplier_id, cow_type_id: x.cow_type_id || first.cow_type_id }));
  };
  const setItem = (i: number, patch: Partial<Item>) => setItems((r) => r.map((x, j) => (j === i ? { ...x, ...patch } : x)));
  const setNon = (i: number, k: string, v: string) => setNonk((r) => r.map((x, j) => (j === i ? { ...x, [k]: v } : x)));
  const setCost = (i: number, k: string, v: string) => setCosts((r) => r.map((x, j) => (j === i ? { ...x, [k]: v } : x)));

  const carcass = cows.reduce((s, cid) => s + (cowOf(cid)?.carcass ?? 0), 0);
  const t = apTotals({
    items: items.map((r) => ({ qty: qty(r.weight), price: money(r.unit_price), meat: prod(r.product_id)?.meat ?? false })),
    nonk: nonk.map((r) => ({ qty: r.weight?.trim() ? qty(r.weight) : null, price: money(r.unit_price) })),
    costs: costs.map((r) => money(r.amount)), cowPrice: money(h.total_purchase ?? ""), manualTotal: manual && (h.manual_total_cost ?? "").trim() ? money(h.manual_total_cost) : null,
    carcass, lower: h.lower_side?.trim() ? qty(h.lower_side) : null, upper: h.upper_side?.trim() ? qty(h.upper_side) : null,
  });

  const supplierName = lists.suppliers.find((s) => s.id === h.supplier_id)?.name ?? "";
  const cowCode = lists.cowTypes.find((s) => s.id === h.cow_type_id)?.code ?? "";
  const year = (h.analysis_date ?? "").slice(2, 4);
  const preview = number || apNumberPreview(year === lists.seqYear ? lists.nextSeq : null, supplierName, cowCode, h.analysis_date ?? "");

  const payload = JSON.stringify({
    header: { ...h, manual_total_cost: manual ? h.manual_total_cost ?? "" : "" },
    children: { cows: cows.map((cw_id) => ({ cw_id })), items, nonk, costs },
  });
  const free = lists.cows.filter((c) => !cows.includes(c.id));
  const usedProducts = new Set(items.map((r) => r.product_id));

  return (
    <form action={action} noValidate className="max-w-[1400px]">
      <input type="hidden" name="payload" value={payload} />
      <div className="rounded-2xl border border-line bg-white p-6 shadow-sm">
        <div role="tablist" aria-label="Bagian analisa" className="mb-6 flex flex-wrap gap-2 border-b border-line pb-3">
          {TABS.map(([k, label]) => (
            <button key={k} type="button" role="tab" aria-selected={tab === k} onClick={() => setTab(k)}
              className={`rounded-full px-5 py-2 text-lg font-semibold ${tab === k ? "bg-brand text-white" : "border-2 border-line hover:bg-background"}`}>{label}</button>
          ))}
        </div>

        {tab === "ringkas" && (
          <div className="space-y-6">
            <div className="grid gap-4 md:grid-cols-3">
              <div><label className={lab}>Nomor</label><input className={`${inp} bg-background text-muted`} readOnly value={preview || "Otomatis saat disimpan"} /></div>
              <div><label className={lab} htmlFor="ap-date">Tanggal *</label><input id="ap-date" type="date" className={inp} value={h.analysis_date ?? ""} onChange={(e) => setHead("analysis_date", e.target.value)} /></div>
              <div><label className={lab} htmlFor="ap-price">Harga sapi (Rp) *</label><input id="ap-price" inputMode="numeric" className={`${inp} text-right`} value={h.total_purchase ?? ""} onChange={(e) => setHead("total_purchase", e.target.value)} /><p className="mt-1 text-sm text-muted">Otomatis menjadi komponen Total Biaya.</p></div>
              <div><label className={lab} htmlFor="ap-sup">Supplier *</label>
                <select id="ap-sup" className={inp} value={h.supplier_id ?? ""} onChange={(e) => setHead("supplier_id", e.target.value)}><option value="">Pilih supplier…</option>{lists.suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select></div>
              <div><label className={lab} htmlFor="ap-type">Jenis sapi *</label>
                <select id="ap-type" className={inp} value={h.cow_type_id ?? ""} onChange={(e) => setHead("cow_type_id", e.target.value)}><option value="">Pilih jenis…</option>{lists.cowTypes.map((s) => <option key={s.id} value={s.id}>{s.code}{s.name !== s.code ? ` - ${s.name}` : ""}</option>)}</select></div>
              <div><label className={lab} htmlFor="ap-top">TOP (jatuh tempo)</label><input id="ap-top" type="date" className={inp} value={h.top_date ?? ""} onChange={(e) => setHead("top_date", e.target.value)} /></div>
              <div><label className={lab} htmlFor="ap-inv">Nomor invoice supplier</label><input id="ap-inv" className={inp} value={h.supplier_invoice ?? ""} onChange={(e) => setHead("supplier_invoice", e.target.value)} /></div>
              <div><label className={lab} htmlFor="ap-low">Lower Side (Kg, opsional)</label><input id="ap-low" inputMode="decimal" className={`${inp} text-right`} value={h.lower_side ?? ""} onChange={(e) => setHead("lower_side", e.target.value)} /></div>
              <div><label className={lab} htmlFor="ap-up">Upper Side (Kg, opsional)</label><input id="ap-up" inputMode="decimal" className={`${inp} text-right`} value={h.upper_side ?? ""} onChange={(e) => setHead("upper_side", e.target.value)} /></div>
              <div className="md:col-span-3"><label className={lab} htmlFor="ap-note">Catatan</label><input id="ap-note" className={inp} value={h.notes ?? ""} onChange={(e) => setHead("notes", e.target.value)} /></div>
            </div>

            <section>
              <h2 className="mb-3 text-sm font-bold uppercase tracking-widest text-muted">Sapi yang dianalisa (dari Penimbangan Karkas)</h2>
              <div className="flex flex-wrap items-center gap-3">
                {cows.length === 0 && <span className="text-muted">Belum ada sapi dipilih</span>}
                {cows.map((cid) => (
                  <span key={cid} className="inline-flex items-center gap-2 rounded-full bg-background px-4 py-2 text-lg font-semibold">
                    {cowOf(cid)?.cow_number ?? "sapi"} <span className="text-sm font-normal text-muted">{fmtQ(cowOf(cid)?.carcass ?? 0)} Kg karkas</span>
                    <button type="button" aria-label={`Lepas sapi ${cowOf(cid)?.cow_number ?? ""}`} onClick={() => changeCows(cows.filter((x) => x !== cid))} className="rounded px-1 text-xl text-danger hover:bg-danger-bg">×</button>
                  </span>
                ))}
                <select aria-label="Tambah sapi" className={`${inp} w-auto min-w-64`} value={pick} onChange={(e) => setPick(e.target.value)}>
                  <option value="">＋ pilih sapi yang sudah final…</option>
                  {free.map((c) => <option key={c.id} value={c.id}>{c.cow_number} ({c.doc_number})</option>)}
                </select>
                <button type="button" disabled={!pick} onClick={() => { changeCows([...cows, pick]); setPick(""); }} className="rounded-md border-2 border-brand px-5 py-2.5 font-semibold text-brand hover:bg-background disabled:opacity-50">Tambahkan</button>
              </div>
              {free.length === 0 && cows.length === 0 && <p className="mt-2 text-muted">Belum ada Penimbangan Karkas berstatus Final yang tersedia.</p>}
            </section>

            <Summary t={t} lower={h.lower_side?.trim() ? qty(h.lower_side) : null} upper={h.upper_side?.trim() ? qty(h.upper_side) : null} />
          </div>
        )}

        {tab === "item" && (
          <div>
            <p className="mb-3 rounded-md bg-background px-4 py-3">Quantity tertaut ke Penimbangan Karkas sapi yang dipilih (tidak bisa diketik). Isi harga jual tiap item. Item di luar penimbangan boleh ditambah manual.</p>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[820px] text-left">
                <thead><tr className="text-sm uppercase tracking-wide text-muted"><th className="w-10 pb-2">No</th><th className="pb-2">Jenis Item</th><th className="w-40 pb-2 text-right">Quantity ({AP_UNIT})</th><th className="w-44 pb-2 text-right">Harga Jual / {AP_UNIT}</th><th className="w-44 pb-2 text-right">Total</th><th className="w-12" /></tr></thead>
                <tbody>
                  {items.map((r, i) => (
                    <tr key={i} className="align-top">
                      <td className="py-1 pr-1 pt-3 text-muted">{i + 1}</td>
                      <td className="py-1 pr-1">
                        {r.linked ? <span className="inline-block pt-2 text-lg">{prod(r.product_id)?.name} <span className="rounded bg-background px-2 py-0.5 text-sm text-muted">dari karkas</span></span> : (
                          <select aria-label={`Item ${i + 1}`} className={inp} value={r.product_id} onChange={(e) => { const p = prod(e.target.value); setItem(i, { product_id: e.target.value, price_source: p?.price != null ? "PRICING" : "TYPED", unit_price: r.unit_price || (p?.price != null ? fmtIn(p.price) : "") }); }}>
                            <option value="">Pilih produk…</option>
                            {lists.products.filter((p) => p.id === r.product_id || !usedProducts.has(p.id)).map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                          </select>
                        )}
                      </td>
                      <td className="py-1 pr-1">{r.linked ? <span className="block bg-yellow-50 px-2 py-2 text-right tabular-nums">{r.weight}</span> : <input aria-label={`Quantity ${i + 1}`} inputMode="decimal" className={`${inp} text-right`} value={r.weight} onChange={(e) => setItem(i, { weight: e.target.value })} />}</td>
                      <td className="py-1 pr-1"><input aria-label={`Harga jual ${i + 1}`} inputMode="numeric" className={`${inp} text-right`} value={r.unit_price} onChange={(e) => setItem(i, { unit_price: e.target.value, price_source: "TYPED" })} /></td>
                      <td className="py-1 pr-2 pt-3 text-right tabular-nums">{fmtRupiah(qty(r.weight) * money(r.unit_price))}</td>
                      <td className="py-1 pt-2">{!r.linked && <button type="button" aria-label={`Hapus item ${i + 1}`} onClick={() => setItems((x) => x.filter((_, j) => j !== i))} className="rounded-md px-2 py-1 text-xl text-danger hover:bg-danger-bg">×</button>}</td>
                    </tr>
                  ))}
                  {items.length === 0 && <tr><td colSpan={6} className="py-6 text-center text-muted">Pilih sapi di tab Ringkasan, hasil potongannya muncul di sini.</td></tr>}
                </tbody>
                <tfoot><tr className="font-semibold"><td colSpan={4} className="pt-3 text-right">Perkiraan hasil penjualan item</td><td className="pt-3 pr-2 text-right tabular-nums">{fmtRupiah(t.sell)}</td><td /></tr></tfoot>
              </table>
            </div>
            <button type="button" onClick={() => setItems((x) => [...x, { product_id: "", weight: "", unit_price: "", price_source: "TYPED", linked: false }])} className="mt-3 rounded-md border-2 border-brand px-5 py-2.5 text-lg font-semibold text-brand hover:bg-background">+ Tambah item manual</button>
          </div>
        )}

        {tab === "nonk" && (
          <div>
            <datalist id="ap-nonk-names">{lists.nonkNames.map((n) => <option key={n} value={n} />)}</datalist>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[760px] text-left">
                <thead><tr className="text-sm uppercase tracking-wide text-muted"><th className="w-10 pb-2">No</th><th className="pb-2">Jenis (Babat, Kulit, Kepala …)</th><th className="w-40 pb-2 text-right">Quantity ({AP_UNIT})</th><th className="w-44 pb-2 text-right">Harga / {AP_UNIT}</th><th className="w-44 pb-2 text-right">Total</th><th className="w-12" /></tr></thead>
                <tbody>
                  {nonk.map((r, i) => (
                    <tr key={i} className="align-top">
                      <td className="py-1 pr-1 pt-3 text-muted">{i + 1}</td>
                      <td className="py-1 pr-1"><input list="ap-nonk-names" aria-label={`Jenis non-karkas ${i + 1}`} className={inp} value={r.name ?? ""} onChange={(e) => setNon(i, "name", e.target.value)} /></td>
                      <td className="py-1 pr-1"><input aria-label={`Quantity non-karkas ${i + 1}`} inputMode="decimal" className={`${inp} text-right`} value={r.weight ?? ""} onChange={(e) => setNon(i, "weight", e.target.value)} /></td>
                      <td className="py-1 pr-1"><input aria-label={`Harga non-karkas ${i + 1}`} inputMode="numeric" className={`${inp} text-right`} value={r.unit_price ?? ""} onChange={(e) => setNon(i, "unit_price", e.target.value)} /></td>
                      <td className="py-1 pr-2 pt-3 text-right tabular-nums">{fmtRupiah(qty(r.weight ?? "") * money(r.unit_price ?? ""))}</td>
                      <td className="py-1 pt-2"><button type="button" aria-label={`Hapus baris non-karkas ${i + 1}`} disabled={nonk.length === 1} onClick={() => setNonk((x) => x.filter((_, j) => j !== i))} className="rounded-md px-2 py-1 text-xl text-danger hover:bg-danger-bg disabled:opacity-30">×</button></td>
                    </tr>
                  ))}
                </tbody>
                <tfoot><tr className="font-semibold"><td colSpan={4} className="pt-3 text-right">Penjualan non-karkas</td><td className="pt-3 pr-2 text-right tabular-nums">{fmtRupiah(t.non)}</td><td /></tr></tfoot>
              </table>
            </div>
            <button type="button" onClick={() => setNonk((x) => [...x, { name: "", weight: "", unit_price: "" }])} className="mt-3 rounded-md border-2 border-brand px-5 py-2.5 text-lg font-semibold text-brand hover:bg-background">+ Tambah baris</button>
            <p className="mt-2 text-sm text-muted">Penjualan non-karkas diisi manual. Quantity boleh kosong bila belum ditimbang.</p>
          </div>
        )}

        {tab === "biaya" && (
          <div>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[720px] text-left">
                <thead><tr className="text-sm uppercase tracking-wide text-muted"><th className="w-10 pb-2">No</th><th className="pb-2">Jenis Biaya</th><th className="w-28 pb-2">Satuan</th><th className="w-52 pb-2 text-right">Total (Rp)</th><th className="w-12" /></tr></thead>
                <tbody>
                  {costs.map((r, i) => (
                    <tr key={i} className="align-top">
                      <td className="py-1 pr-1 pt-3 text-muted">{i + 1}</td>
                      <td className="py-1 pr-1"><select aria-label={`Jenis biaya ${i + 1}`} className={inp} value={r.cost_type_id ?? ""} onChange={(e) => setCost(i, "cost_type_id", e.target.value)}><option value="">Pilih jenis biaya…</option>{lists.costTypes.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select></td>
                      <td className="py-1 pr-1 pt-3 text-muted">{AP_COST_UNIT}</td>
                      <td className="py-1 pr-1"><input aria-label={`Total biaya ${i + 1}`} inputMode="numeric" className={`${inp} text-right`} value={r.amount ?? ""} onChange={(e) => setCost(i, "amount", e.target.value)} /></td>
                      <td className="py-1 pt-2"><button type="button" aria-label={`Hapus biaya ${i + 1}`} disabled={costs.length === 1} onClick={() => setCosts((x) => x.filter((_, j) => j !== i))} className="rounded-md px-2 py-1 text-xl text-danger hover:bg-danger-bg disabled:opacity-30">×</button></td>
                    </tr>
                  ))}
                </tbody>
                <tfoot>
                  <tr className="font-semibold"><td colSpan={3} className="pt-3 text-right">SubTotal biaya operasional</td><td className="pt-3 pr-2 text-right tabular-nums">{fmtRupiah(t.ops)}</td><td /></tr>
                  <tr className="font-semibold"><td colSpan={3} className="text-right">Total biaya (harga sapi + operasional)</td><td className="pr-2 text-right tabular-nums">{fmtRupiah(t.totalCost)}</td><td /></tr>
                </tfoot>
              </table>
            </div>
            <button type="button" onClick={() => setCosts((x) => [...x, { cost_type_id: "", amount: "", note: "" }])} className="mt-3 rounded-md border-2 border-brand px-5 py-2.5 text-lg font-semibold text-brand hover:bg-background">+ Tambah biaya</button>
            <div className="mt-5 max-w-md">
              <label className="flex items-center gap-3 text-lg"><input type="checkbox" className="h-5 w-5" checked={manual} onChange={(e) => setManual(e.target.checked)} /> Isi Total Biaya secara manual</label>
              {manual
                ? <input aria-label="Total biaya manual" inputMode="numeric" className={`${inp} mt-2 text-right`} placeholder="Total biaya" value={h.manual_total_cost ?? ""} onChange={(e) => setHead("manual_total_cost", e.target.value)} />
                : <p className="mt-1 text-sm text-muted">Bawaan: harga sapi + biaya operasional, dihitung otomatis.</p>}
            </div>
          </div>
        )}

        <div className="mt-8 grid gap-3 rounded-lg bg-background p-4 md:grid-cols-3">
          {[["Total penjualan", fmtRupiah(t.all)], ["Total biaya", fmtRupiah(t.totalCost)], ["Keuntungan", fmtRupiah(t.profit)]].map(([k, v]) => (
            <p key={k} className="flex justify-between gap-3 text-lg"><span className="text-muted">{k}</span><b className={`tabular-nums ${k === "Keuntungan" && t.profit < 0 ? "text-danger" : ""}`}>{v}</b></p>
          ))}
        </div>

        {state.error && <p role="alert" className="mt-4 rounded-md bg-danger-bg px-4 py-3 text-lg text-danger">{state.error}</p>}
        <div className="mt-6 flex gap-3">
          <button type="submit" disabled={pending} className="rounded-md bg-brand px-8 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Menyimpan..." : "Simpan analisa"}</button>
          <Link href={cancelHref} className="rounded-md border-2 border-line px-8 py-3 text-lg font-semibold hover:bg-background">Batal</Link>
        </div>
      </div>
    </form>
  );
}

export function Summary({ t, lower, upper }: { t: ReturnType<typeof apTotals>; lower: number | null; upper: number | null }) {
  const row = (k: string, v: string) => <p key={k} className="flex justify-between gap-6"><span className="text-muted">{k}</span><b className="tabular-nums">{v}</b></p>;
  return (
    <section className="grid gap-2 rounded-lg bg-background p-4 text-lg md:max-w-xl" aria-label="Hasil analisa">
      {row("Keuntungan", fmtRupiah(t.profit))}
      {row("Daging (Kg)", fmtQ(t.meat))}
      {row("Karkas (Kg)", fmtQ(t.carcass))}
      {row("Persentase", t.meatPct === null ? "-" : `${t.meatPct.toFixed(2)}%`)}
      {row("Harga karkas / Kg", t.hargaKarkas === null ? "-" : fmtRupiah(Math.round(t.hargaKarkas)))}
      {lower !== null && row("Lower Side", `${fmtQ(lower)} Kg${t.lowerRatio !== null ? ` (${(t.lowerRatio * 100).toFixed(2)}%)` : ""}`)}
      {upper !== null && row("Upper Side", `${fmtQ(upper)} Kg${t.upperRatio !== null ? ` (${(t.upperRatio * 100).toFixed(2)}%)` : ""}`)}
    </section>
  );
}
