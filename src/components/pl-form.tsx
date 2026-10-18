"use client";

import Link from "next/link";
import { useActionState, useMemo, useState } from "react";
import { saveDoc, type DocFormState } from "@/app/(app)/d/actions";
import type { PlRo } from "@/lib/docs/ro-lists";
import type { RoProduct } from "@/components/ro-form";
import { parseQty } from "@/lib/docs/parse";

type Row = Record<string, string>;
const inp = "w-full rounded-md border-2 border-line bg-white px-3 py-2.5 text-lg";
const ro_inp = `${inp} bg-background text-muted`;
const lab = "mb-1 block text-sm font-semibold uppercase tracking-wide text-muted";
const blank = (product_id = "", text = ""): Row => ({ product_id, _text: text, qty: "", gross_weight: "", notes: "" });
const kg = (n: number) => n.toLocaleString("id-ID", { minimumFractionDigits: 3, maximumFractionDigits: 3 });
const num = (v: string) => { const n = parseQty(v ?? ""); return typeof n === "number" ? n : 0; };

export function PlForm({ id, initial, ros, products, warehouses, number, cancelHref }: {
  id: string; initial: { header: Row; items: Row[] }; ros: PlRo[]; products: RoProduct[]; warehouses: { id: string; name: string }[]; number: string; cancelHref: string;
}) {
  const [state, action, pending] = useActionState<DocFormState, FormData>(saveDoc.bind(null, "pl", id), {});
  const restored = useMemo(() => {
    if (!state.payload) return null;
    try { const p = JSON.parse(state.payload); return { header: (p.header ?? {}) as Row, items: (p.children?.items ?? []) as Row[] }; } catch { return null; }
  }, [state.payload]);
  const nameOf = (pid: string) => products.find((p) => p.id === pid)?.name ?? "";
  const withText = (rows: Row[]) => rows.map((r) => ({ ...r, _text: r._text ?? nameOf(r.product_id) }));
  const [h, setH] = useState<Row>(restored?.header ?? initial.header);
  const [items, setItems] = useState<Row[]>(withText(restored?.items?.length ? restored.items : initial.items.length ? initial.items : [blank()]));
  const [paste, setPaste] = useState<string | null>(null);
  const ro = ros.find((r) => r.id === h.ro_id);

  const pickRo = (rid: string) => {
    const r = ros.find((x) => x.id === rid);
    setH((x) => ({ ...x, ro_id: rid, customer_id: r?.customerId ?? "", phone: x.phone || r?.phone || "" }));
  };
  const set = (k: string, v: string) => setH((x) => ({ ...x, [k]: v }));
  const setItem = (i: number, patch: Row) => setItems((r) => r.map((x, j) => (j === i ? { ...x, ...patch } : x)));
  const typeProduct = (i: number, text: string) => {
    const t = text.trim().toLowerCase();
    const hit = products.find((p) => p.name.toLowerCase() === t || `${p.code} - ${p.name}`.toLowerCase() === t);
    setItem(i, { _text: text, product_id: hit?.id ?? "" });
  };
  const last = items[items.length - 1];
  const more = (n: number) => setItems((x) => [...x, ...Array.from({ length: n }, () => blank(last?.product_id ?? "", last?._text ?? ""))]);
  const applyPaste = () => {
    const lines = (paste ?? "").split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
    const base = last ?? blank();
    const rows = lines.map((l) => { const [n, g] = l.split(/\t|;/); return { ...blank(base.product_id, base._text), qty: (n ?? "").trim(), gross_weight: (g ?? "").trim() }; });
    if (rows.length) setItems((x) => [...x.filter((r) => r.qty.trim() || r.gross_weight.trim()), ...rows]);
    setPaste(null);
  };
  const tNet = items.reduce((s, r) => s + num(r.qty), 0);
  const tGross = items.reduce((s, r) => s + num(r.gross_weight), 0);
  const cleaned = items.filter((r) => r.qty.trim() || r.gross_weight.trim());
  const payload = JSON.stringify({ header: h, children: { items: cleaned.map(({ _text, ...r }) => { void _text; return r; }) } });

  return (
    <form action={action} noValidate className="max-w-5xl">
      <input type="hidden" name="payload" value={payload} />
      <datalist id="pl-products">{products.map((p) => <option key={p.id} value={p.name}>{p.code}</option>)}</datalist>
      <div className="space-y-8 rounded-2xl border border-line bg-white p-6 shadow-sm">
        <section>
          <h2 className="mb-4 text-sm font-bold uppercase tracking-widest text-muted">Data Packing List</h2>
          <div className="grid gap-4 md:grid-cols-2">
            <div><label className={lab}>Nomor</label><input className={ro_inp} readOnly value={number || "Otomatis saat disimpan"} /></div>
            <div><label className={lab} htmlFor="pl-date">Tanggal *</label><input id="pl-date" type="date" className={inp} value={h.pack_date ?? ""} onChange={(e) => set("pack_date", e.target.value)} /></div>
            <div className="md:col-span-2">
              <label className={lab} htmlFor="pl-ro">Mengacu RO nomor *</label>
              <select id="pl-ro" className={inp} value={h.ro_id ?? ""} onChange={(e) => pickRo(e.target.value)}>
                <option value="">— pilih RO —</option>
                {ros.map((r) => <option key={r.id} value={r.id}>{r.no} — {r.customer}</option>)}
              </select>
              <p className="mt-1 text-sm text-muted">Wajib. Nomor RO hanya tercatat di sistem, tidak dicetak di file Excel.</p>
            </div>
            <div><label className={lab}>Kepada</label><input className={ro_inp} readOnly placeholder="Mengikuti RO" value={ro?.customer ?? ""} /></div>
            <div><label className={lab} htmlFor="pl-phone">No. telepon</label><input id="pl-phone" className={inp} inputMode="tel" value={h.phone ?? ""} onChange={(e) => set("phone", e.target.value)} /></div>
            <div>
              <label className={lab} htmlFor="pl-wh">Gudang asal stok *</label>
              <select id="pl-wh" className={inp} value={h.warehouse_id ?? ""} onChange={(e) => set("warehouse_id", e.target.value)}>
                <option value="">Pilih gudang...</option>{warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
              </select>
              <p className="mt-1 text-sm text-muted">Stok berkurang dari gudang ini saat ditandai selesai dikemas.</p>
            </div>
          </div>
        </section>

        <section>
          <h2 className="mb-4 text-sm font-bold uppercase tracking-widest text-muted">Daftar item</h2>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[640px] text-left">
              <thead><tr className="text-sm uppercase tracking-wide text-muted"><th className="w-16 pb-2">No item</th><th className="pb-2">Jenis item</th><th className="w-40 pb-2 text-right">Net weight (kg)</th><th className="w-40 pb-2 text-right">Gross weight (kg)</th><th className="w-10" /></tr></thead>
              <tbody>
                {items.map((r, i) => (
                  <tr key={i} className="align-top">
                    <td className="py-1 pr-2 pt-4 text-muted">{String(i + 1).padStart(2, "0")}</td>
                    <td className="py-1 pr-2">
                      <input list="pl-products" aria-label={`Jenis item ${i + 1}`} className={inp} placeholder="mis. Daging" value={r._text ?? ""} onChange={(e) => typeProduct(i, e.target.value)} />
                      {r._text && !r.product_id && <p className="mt-1 text-sm text-danger">Pilih produk dari daftar yang ada.</p>}
                    </td>
                    <td className="py-1 pr-2"><input aria-label={`Net ${i + 1}`} className={`${inp} text-right`} inputMode="decimal" value={r.qty ?? ""} onChange={(e) => setItem(i, { qty: e.target.value })} /></td>
                    <td className="py-1 pr-2"><input aria-label={`Gross ${i + 1}`} className={`${inp} text-right`} inputMode="decimal" value={r.gross_weight ?? ""} onChange={(e) => setItem(i, { gross_weight: e.target.value })} /></td>
                    <td className="py-1 pt-3"><button type="button" aria-label={`Hapus baris ${i + 1}`} disabled={items.length === 1} onClick={() => setItems((x) => x.filter((_, j) => j !== i))} className="rounded-md px-3 py-1.5 text-xl text-danger hover:bg-danger-bg disabled:opacity-30">×</button></td>
                  </tr>
                ))}
                <tr className="border-t-2 border-line font-bold"><td /><td className="py-3 text-lg">Total</td><td className="py-3 pr-5 text-right text-lg">{kg(tNet)}</td><td className="py-3 pr-5 text-right text-lg">{kg(tGross)}</td><td /></tr>
              </tbody>
            </table>
          </div>
          <div className="mt-3 flex flex-wrap gap-3">
            <button type="button" onClick={() => more(1)} className="rounded-md border-2 border-brand px-5 py-2.5 text-lg font-semibold text-brand hover:bg-background">+ Tambah baris</button>
            <button type="button" onClick={() => more(5)} className="rounded-md border-2 border-brand px-5 py-2.5 text-lg font-semibold text-brand hover:bg-background">+ 5 baris</button>
            <button type="button" onClick={() => setPaste(paste === null ? "" : null)} className="rounded-md border-2 border-line px-5 py-2.5 text-lg font-semibold hover:bg-background">Tempel dari Excel…</button>
          </div>
          {paste !== null && (
            <div className="mt-3">
              <label className={lab} htmlFor="pl-paste">Tempel kolom Net dan Gross (satu baris satu kemasan, dipisah tab)</label>
              <textarea id="pl-paste" rows={5} className={inp} placeholder={"4,110\t4,135"} value={paste} onChange={(e) => setPaste(e.target.value)} />
              <button type="button" onClick={applyPaste} className="mt-2 rounded-md bg-brand px-5 py-2.5 font-semibold text-white">Isi baris</button>
              <p className="mt-1 text-sm text-muted">Baris yang ditempel memakai jenis item dari baris terakhir.</p>
            </div>
          )}
        </section>

        <section className="grid gap-4 md:grid-cols-2">
          <div><label className={lab} htmlFor="pl-sup">Pengawas</label><input id="pl-sup" className={inp} value={h.supervisor ?? ""} onChange={(e) => set("supervisor", e.target.value)} /></div>
          <div><label className={lab} htmlFor="pl-note">Note</label><input id="pl-note" className={inp} value={h.notes ?? ""} onChange={(e) => set("notes", e.target.value)} /></div>
          <p className="text-sm text-muted md:col-span-2">Tanda tangan Packing List: Pengawas dan Pembeli/Penerima.</p>
        </section>

        {state.error && <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-lg text-danger">{state.error}</p>}
        <div className="flex gap-3">
          <button type="submit" disabled={pending || !h.ro_id} className="rounded-md bg-brand px-8 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Menyimpan..." : h.ro_id ? "Simpan Packing List" : "Pilih RO dahulu"}</button>
          <Link href={cancelHref} className="rounded-md border-2 border-line px-8 py-3 text-lg font-semibold hover:bg-background">Batal</Link>
        </div>
      </div>
    </form>
  );
}
