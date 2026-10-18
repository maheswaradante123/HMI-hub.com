"use client";

import Link from "next/link";
import { useActionState, useMemo, useState } from "react";
import { saveCw } from "@/app/(app)/d/actions";
import type { DocFormState } from "@/app/(app)/d/actions";
import { parseQty } from "@/lib/docs/parse";
import { CW_CATS, cwNumberPreview, cwTotals, type CwCat, type CwRow } from "@/lib/docs/cw";
import type { CwLists } from "@/lib/docs/cw-lists";

type Head = Record<string, string>;
type Init = { header: Head; items: CwRow[] };

const inp = "w-full rounded-md border-2 border-line bg-white px-2 py-2 text-base disabled:bg-background disabled:text-muted";
const lab = "mb-1 block text-sm font-semibold uppercase tracking-wide text-muted";
const qty = (v: string) => { const n = parseQty((v ?? "").trim()); return typeof n === "number" ? n : 0; };
const fmtQ = (n: number) => n.toLocaleString("id-ID", { minimumFractionDigits: 3, maximumFractionDigits: 3 });

export const CW_BLANK_ROWS: CwRow[] = [{ name: "", cat: "Daging", weight: "" }, { name: "", cat: "Daging", weight: "" }, { name: "", cat: "Tulang", weight: "" }];

export function CwForm({ id, initial, lists, number, cancelHref }: { id: string; initial: Init; lists: CwLists; number: string; cancelHref: string }) {
  const [state, action, pending] = useActionState<DocFormState, FormData>(saveCw.bind(null, id), {});
  const restored = useMemo(() => {
    if (!state.payload) return null;
    try {
      const p = JSON.parse(state.payload);
      return { header: (p.header ?? {}) as Head, items: ((p.items ?? []) as CwRow[]) } satisfies Init;
    } catch { return null; }
  }, [state.payload]);
  const start = restored ?? initial;
  const [h, setH] = useState<Head>(start.header);
  const [rows, setRows] = useState<CwRow[]>(start.items.length ? start.items : CW_BLANK_ROWS);
  const setHead = (k: string, v: string) => setH((x) => ({ ...x, [k]: v }));

  const master = useMemo(() => new Map(lists.masterItems.map((m) => [m.name.toLowerCase(), m.cat])), [lists.masterItems]);
  const masterCat = (name: string): CwCat | undefined => master.get(name.trim().toLowerCase());
  const setRow = (i: number, patch: Partial<CwRow>) => setRows((r) => r.map((x, j) => (j === i ? { ...x, ...patch } : x)));
  const setName = (i: number, name: string) => { const m = masterCat(name); setRow(i, m ? { name, cat: m } : { name }); };

  const carcass = qty(h.carcass_weight ?? "");
  const t = cwTotals(rows.map((r) => ({ cat: r.cat, weight: qty(r.weight) })), carcass);
  const preview = number || cwNumberPreview(lists.nextNumber, h.cow_number ?? "", h.weigh_date ?? "");
  const payload = JSON.stringify({ header: h, items: rows });
  const kpis: [string, string][] = [["Total hasil", `${fmtQ(t.total)} Kg`], ...CW_CATS.map((k) => [k, fmtQ(t.byCat[k])] as [string, string]), ["% daging terhadap karkas", t.meatPct === null ? "-" : `${t.meatPct.toFixed(2).replace(".", ",")}%`]];

  return (
    <form action={action} noValidate className="max-w-[1100px]">
      <input type="hidden" name="payload" value={payload} />
      <div className="rounded-2xl border border-line bg-white p-6 shadow-sm">
        <div className="grid gap-4 md:grid-cols-3">
          <div><label className={lab}>Nomor</label><input className={`${inp} bg-background text-muted`} readOnly value={preview || "Otomatis saat disimpan"} /></div>
          <div><label className={lab} htmlFor="cw-date">Tanggal *</label><input id="cw-date" type="date" className={inp} value={h.weigh_date ?? ""} onChange={(e) => setHead("weigh_date", e.target.value)} /></div>
          <div><label className={lab} htmlFor="cw-cow">Kode sapi *</label><input id="cw-cow" className={`${inp} uppercase`} placeholder="mis. AMF014" value={h.cow_number ?? ""} onChange={(e) => setHead("cow_number", e.target.value.toUpperCase())} /></div>
          <div><label className={lab} htmlFor="cw-sup">Supplier</label>
            <select id="cw-sup" className={inp} value={h.supplier_id ?? ""} onChange={(e) => setHead("supplier_id", e.target.value)}><option value="">Pilih supplier…</option>{lists.suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select></div>
          <div><label className={lab} htmlFor="cw-type">Jenis sapi <span className="font-normal normal-case">— opsional</span></label>
            <select id="cw-type" className={inp} value={h.cow_type_id ?? ""} onChange={(e) => setHead("cow_type_id", e.target.value)}><option value="">Tidak diisi</option>{lists.cowTypes.map((s) => <option key={s.id} value={s.id}>{s.code}{s.name !== s.code ? ` - ${s.name}` : ""}</option>)}</select></div>
          <div><label className={lab} htmlFor="cw-wh">Gudang penerima daging *</label>
            <select id="cw-wh" className={inp} value={h.warehouse_id ?? ""} onChange={(e) => setHead("warehouse_id", e.target.value)}>{lists.warehouses.length !== 1 && <option value="">Pilih gudang…</option>}{lists.warehouses.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select></div>
          <div><label className={lab} htmlFor="cw-live">Berat hidup (Kg) <span className="font-normal normal-case">— opsional</span></label><input id="cw-live" inputMode="decimal" className={`${inp} text-right`} value={h.live_weight ?? ""} onChange={(e) => setHead("live_weight", e.target.value)} /></div>
          <div><label className={lab} htmlFor="cw-car">Berat karkas (Kg) *</label><input id="cw-car" inputMode="decimal" className={`${inp} text-right`} value={h.carcass_weight ?? ""} onChange={(e) => setHead("carcass_weight", e.target.value)} /></div>
          <div><label className={lab} htmlFor="cw-note">Catatan</label><input id="cw-note" className={inp} value={h.notes ?? ""} onChange={(e) => setHead("notes", e.target.value)} /></div>
        </div>

        <h2 className="mb-2 mt-8 text-sm font-bold uppercase tracking-widest text-muted">Hasil potong</h2>
        <p className="mb-3 rounded-md bg-background px-4 py-3">Tidak ada item bawaan. Pilih dari daftar atau ketik nama sendiri, lalu tentukan kategorinya. Nama yang sudah ada di master memakai kategori master.</p>
        <datalist id="cw-items">{lists.masterItems.map((m) => <option key={m.name} value={m.name}>{m.cat}</option>)}</datalist>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[720px] text-left">
            <thead><tr className="text-sm uppercase tracking-wide text-muted"><th className="w-10 pb-2">#</th><th className="pb-2">Item</th><th className="w-44 pb-2">Kategori</th><th className="w-44 pb-2 text-right">Berat (Kg)</th><th className="w-12" /></tr></thead>
            <tbody>
              {rows.map((r, i) => {
                const locked = masterCat(r.name);
                return (
                  <tr key={i} className="align-top">
                    <td className="py-1 pr-1 pt-3 text-muted">{i + 1}</td>
                    <td className="py-1 pr-1"><input list="cw-items" aria-label={`Item ${i + 1}`} placeholder="Pilih / ketik nama item" className={inp} value={r.name} onChange={(e) => setName(i, e.target.value)} /></td>
                    <td className="py-1 pr-1">
                      <select aria-label={`Kategori ${i + 1}`} className={inp} value={locked ?? r.cat} disabled={!!locked} onChange={(e) => setRow(i, { cat: e.target.value as CwCat })}>{CW_CATS.map((k) => <option key={k}>{k}</option>)}</select>
                      {locked && <span className="text-xs text-muted">dari master</span>}
                    </td>
                    <td className="py-1 pr-1"><input aria-label={`Berat ${i + 1}`} inputMode="decimal" className={`${inp} text-right`} value={r.weight} onChange={(e) => setRow(i, { weight: e.target.value })} /></td>
                    <td className="py-1 pt-2"><button type="button" aria-label={`Hapus item ${i + 1}`} disabled={rows.length === 1} onClick={() => setRows((x) => x.filter((_, j) => j !== i))} className="rounded-md px-2 py-1 text-xl text-danger hover:bg-danger-bg disabled:opacity-30">×</button></td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <button type="button" onClick={() => setRows((x) => [...x, { name: "", cat: "Daging", weight: "" }])} className="mt-3 rounded-md border-2 border-brand px-5 py-2.5 text-lg font-semibold text-brand hover:bg-background">+ Tambah item</button>

        <div className="mt-6 grid gap-3 rounded-lg bg-background p-4 sm:grid-cols-2 md:grid-cols-3" aria-label="Ringkasan hasil potong">
          {kpis.map(([k, v]) => <p key={k} className="flex justify-between gap-3 text-lg"><span className="text-muted">{k}</span><b className="tabular-nums">{v}</b></p>)}
        </div>
        {t.over && <p role="status" className="mt-3 rounded-md bg-warn-bg px-4 py-3">Total hasil potong ({fmtQ(t.total)} Kg) melebihi berat karkas ({fmtQ(carcass)} Kg). Penimbangan tidak bisa disimpan sebelum diperbaiki.</p>}
        <p className="mt-3 text-sm text-muted">Item daging, tulang dan jeroan yang belum ada di master ditambahkan otomatis saat disimpan. Finalisasi memasukkan stok per item (daging, tulang, jeroan) atas nama kode sapi ini; item Non-Karkas dicatat tetapi tidak masuk stok.</p>

        {state.error && <p role="alert" className="mt-4 rounded-md bg-danger-bg px-4 py-3 text-lg text-danger">{state.error}</p>}
        <div className="mt-6 flex flex-wrap gap-3">
          <button type="submit" name="mode" value="final" disabled={pending} className="rounded-md bg-brand px-8 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Menyimpan..." : "Finalisasi & masuk stok"}</button>
          <button type="submit" name="mode" value="draft" disabled={pending} className="rounded-md border-2 border-brand px-8 py-3 text-lg font-semibold text-brand hover:bg-background disabled:opacity-60">Simpan draf</button>
          <Link href={cancelHref} className="rounded-md border-2 border-line px-8 py-3 text-lg font-semibold hover:bg-background">Batal</Link>
        </div>
      </div>
    </form>
  );
}
