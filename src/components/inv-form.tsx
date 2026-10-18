"use client";

import Link from "next/link";
import { useActionState, useMemo, useState } from "react";
import { saveDoc, type DocFormState } from "@/app/(app)/d/actions";
import type { InvPl } from "@/lib/docs/ro-lists";
import type { RoProduct } from "@/components/ro-form";
import { parseQty } from "@/lib/docs/parse";
import { parseMoney } from "@/lib/pricing/schema";
import { fmtRupiah } from "@/lib/docs/format";
import { terbilangRupiah } from "@/lib/docs/terbilang";

type Row = Record<string, string>;
const inp = "w-full rounded-md border-2 border-line bg-white px-3 py-2.5 text-lg";
const ro_inp = `${inp} bg-background text-muted`;
const lab = "mb-1 block text-sm font-semibold uppercase tracking-wide text-muted";
const blank = (): Row => ({ product_id: "", _text: "", qty: "", unit_price: "", description: "" });

// Usulan nomor surat jalan: DO-{kode pelanggan}-{urut}-{bulan}-{tahun}, mengikuti nomor invoice.
function suggestSj(invNo: string, code: string) {
  const m = /^INV-(\d{3}-[IVX]+-\d{2})$/.exec(invNo);
  return m && code ? `DO-${code}-${m[1]}` : "";
}

export function InvForm({ id, initial, pls, products, taxRate, number, cancelHref }: {
  id: string; initial: { header: Row; items: Row[] }; pls: InvPl[]; products: RoProduct[]; taxRate: number; number: string; cancelHref: string;
}) {
  const [state, action, pending] = useActionState<DocFormState, FormData>(saveDoc.bind(null, "inv", id), {});
  const restored = useMemo(() => {
    if (!state.payload) return null;
    try { const p = JSON.parse(state.payload); return { header: (p.header ?? {}) as Row, items: (p.children?.items ?? []) as Row[] }; } catch { return null; }
  }, [state.payload]);
  const nameOf = (pid: string) => products.find((p) => p.id === pid)?.name ?? "";
  const withText = (rows: Row[]) => rows.map((r) => ({ ...r, _text: r._text ?? nameOf(r.product_id) }));
  const [h, setH] = useState<Row>(restored?.header ?? initial.header);
  const [items, setItems] = useState<Row[]>(withText(restored?.items?.length ? restored.items : initial.items.length ? initial.items : [blank()]));
  const pl = pls.find((p) => p.id === h.pl_id);

  const set = (k: string, v: string) => setH((x) => ({ ...x, [k]: v }));
  const pickPl = (pid: string) => {
    const p = pls.find((x) => x.id === pid);
    setH((x) => ({
      ...x, pl_id: pid, customer_id: p?.customerId ?? "", buyer_name: p?.customer ?? "", phone: p?.phone ?? "",
      delivery_note_no: x.delivery_note_no || (p ? suggestSj(number, p.code) : ""),
    }));
    // Isi rincian dari Packing List lewat halaman baru agar jumlah dan harga RO ikut terbawa.
    if (pid && !id) window.location.assign(`/d/inv/baru?pl=${pid}`);
  };
  const setItem = (i: number, patch: Row) => setItems((r) => r.map((x, j) => (j === i ? { ...x, ...patch } : x)));
  const typeProduct = (i: number, text: string) => {
    const t = text.trim().toLowerCase();
    const hit = products.find((p) => p.name.toLowerCase() === t || `${p.code} - ${p.name}`.toLowerCase() === t);
    setItem(i, { _text: text, product_id: hit?.id ?? "" });
  };
  const amount = (r: Row) => {
    const q = parseQty(r.qty ?? ""); const p = parseMoney(r.unit_price ?? "");
    return typeof q === "number" && typeof p === "number" ? q * p : 0;
  };
  const sub = items.reduce((s, r) => s + amount(r), 0);
  const tax = Math.round((sub * taxRate) / 100);
  const total = sub + tax;
  const dpN = parseMoney(h.down_payment ?? "");
  const dp = typeof dpN === "number" ? dpN : 0;
  const rest = total - dp;
  const payload = JSON.stringify({ header: h, children: { items: items.map(({ _text, ...r }) => { void _text; return r; }) } });

  return (
    <form action={action} noValidate className="max-w-5xl">
      <input type="hidden" name="payload" value={payload} />
      <datalist id="inv-products">{products.map((p) => <option key={p.id} value={p.name}>{p.code}</option>)}</datalist>
      <div className="space-y-8 rounded-2xl border border-line bg-white p-6 shadow-sm">
        <section>
          <h2 className="mb-4 text-sm font-bold uppercase tracking-widest text-muted">Data invoice</h2>
          <div className="grid gap-4 md:grid-cols-2">
            <div><label className={lab}>Nomor invoice</label><input className={ro_inp} readOnly value={number || "Otomatis saat disimpan"} /></div>
            <div><label className={lab} htmlFor="inv-date">Tanggal *</label><input id="inv-date" type="date" className={inp} value={h.invoice_date ?? ""} onChange={(e) => set("invoice_date", e.target.value)} /></div>
            <div className="md:col-span-2">
              <label className={lab} htmlFor="inv-pl">Packing List *</label>
              <select id="inv-pl" className={inp} disabled={Boolean(id)} value={h.pl_id ?? ""} onChange={(e) => pickPl(e.target.value)}>
                <option value="">— pilih Packing List —</option>
                {pls.map((p) => <option key={p.id} value={p.id}>{p.no} — {p.customer} ({p.net.toLocaleString("id-ID", { maximumFractionDigits: 3 })} Kg)</option>)}
              </select>
              <p className="mt-1 text-sm text-muted">Pilih Packing List: penerima, telepon dan berat terisi otomatis.</p>
            </div>
            <div><label className={lab} htmlFor="inv-to">Kepada</label><input id="inv-to" className={inp} value={h.buyer_name ?? ""} onChange={(e) => set("buyer_name", e.target.value)} /></div>
            <div><label className={lab} htmlFor="inv-phone">No. telepon pembeli</label><input id="inv-phone" className={inp} inputMode="tel" value={h.phone ?? ""} onChange={(e) => set("phone", e.target.value)} /></div>
            <div>
              <label className={lab} htmlFor="inv-sj">Surat jalan (nomor)</label>
              <input id="inv-sj" className={inp} placeholder={pl ? suggestSj(number, pl.code) : "mis. DO-HBR-003-X-26"} value={h.delivery_note_no ?? ""} onChange={(e) => set("delivery_note_no", e.target.value)} />
              <p className="mt-1 text-sm text-muted">Diisi manual; usulan otomatis mengikuti nomor invoice.</p>
            </div>
            <div>
              <label className={lab} htmlFor="inv-due">Jatuh tempo</label>
              <input id="inv-due" type="date" className={inp} value={h.due_date ?? ""} onChange={(e) => set("due_date", e.target.value)} />
              <p className="mt-1 text-sm text-muted">Kosongkan agar mengikuti termin pembayaran pelanggan.</p>
            </div>
          </div>
        </section>

        <section>
          <h2 className="mb-4 text-sm font-bold uppercase tracking-widest text-muted">Rincian</h2>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[760px] text-left">
              <thead><tr className="text-sm uppercase tracking-wide text-muted"><th className="w-8 pb-2">No</th><th className="pb-2">Deskripsi</th><th className="w-28 pb-2 text-right">Qty</th><th className="w-20 pb-2">Satuan</th><th className="w-40 pb-2 text-right">Harga / satuan</th><th className="w-36 pb-2 text-right">Total</th><th className="w-10" /></tr></thead>
              <tbody>
                {items.map((r, i) => (
                  <tr key={i} className="align-top">
                    <td className="py-1 pr-2 pt-4 text-muted">{i + 1}</td>
                    <td className="py-1 pr-2">
                      <input list="inv-products" aria-label={`Deskripsi ${i + 1}`} className={inp} value={r._text ?? ""} onChange={(e) => typeProduct(i, e.target.value)} />
                      {r._text && !r.product_id && <p className="mt-1 text-sm text-danger">Pilih produk dari daftar yang ada.</p>}
                    </td>
                    <td className="py-1 pr-2"><input aria-label={`Qty ${i + 1}`} className={`${inp} text-right`} inputMode="decimal" value={r.qty ?? ""} onChange={(e) => setItem(i, { qty: e.target.value })} /></td>
                    <td className="py-1 pr-2 pt-4 text-lg">{products.find((p) => p.id === r.product_id)?.unit ?? ""}</td>
                    <td className="py-1 pr-2"><input aria-label={`Harga ${i + 1}`} className={`${inp} text-right`} inputMode="decimal" placeholder="otomatis" value={r.unit_price ?? ""} onChange={(e) => setItem(i, { unit_price: e.target.value })} /></td>
                    <td className="py-1 pr-2 pt-4 text-right text-lg font-semibold">{amount(r) ? fmtRupiah(amount(r)) : "—"}</td>
                    <td className="py-1 pt-3"><button type="button" aria-label={`Hapus baris ${i + 1}`} disabled={items.length === 1} onClick={() => setItems((x) => x.filter((_, j) => j !== i))} className="rounded-md px-3 py-1.5 text-xl text-danger hover:bg-danger-bg disabled:opacity-30">×</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <button type="button" onClick={() => setItems((x) => [...x, blank()])} className="mt-3 rounded-md border-2 border-brand px-5 py-2.5 text-lg font-semibold text-brand hover:bg-background">+ Tambah baris</button>
        </section>

        <section className="grid gap-4 md:grid-cols-2">
          <div><label className={lab} htmlFor="inv-dp">Uang muka</label><input id="inv-dp" className={inp} inputMode="numeric" value={h.down_payment ?? ""} onChange={(e) => set("down_payment", e.target.value)} />
            <p className="mt-1 text-sm text-muted">Uang muka langsung dihitung sebagai pembayaran saat invoice diterbitkan.</p></div>
          <div><label className={lab}>Total pembelanjaan{taxRate > 0 ? ` (termasuk pajak ${taxRate}%)` : ""}</label><input className={ro_inp} readOnly value={fmtRupiah(total)} /></div>
          <div><label className={lab}>Kekurangan</label><input className={ro_inp} readOnly value={fmtRupiah(Math.max(rest, 0))} /></div>
          <div><label className={lab}>Terbilang</label><input className={ro_inp} readOnly value={terbilangRupiah(Math.max(rest, 0))} /></div>
          {rest < 0 && <p className="text-danger md:col-span-2">Uang muka melebihi total invoice.</p>}
          <div className="md:col-span-2"><label className={lab} htmlFor="inv-bank">Pembayaran melalui</label><input id="inv-bank" className={inp} value={h.bank_info ?? ""} onChange={(e) => set("bank_info", e.target.value)} /></div>
          <div><label className={lab} htmlFor="inv-sign">Penandatangan</label><input id="inv-sign" list="inv-signers" className={inp} value={h.signer ?? ""} onChange={(e) => set("signer", e.target.value)} /><datalist id="inv-signers"><option value="Ahmad Hunain" /><option value="Misbahudin" /></datalist></div>
          <label className="flex items-center gap-3 pt-6 text-lg"><input type="checkbox" className="size-5" checked={h.use_signature !== "false"} onChange={(e) => set("use_signature", e.target.checked ? "true" : "false")} /> Tempel tanda tangan digital</label>
          <div className="md:col-span-2"><label className={lab} htmlFor="inv-note">Catatan</label><input id="inv-note" className={inp} value={h.notes ?? ""} onChange={(e) => set("notes", e.target.value)} /></div>
        </section>

        {state.error && <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-lg text-danger">{state.error}</p>}
        <div className="flex gap-3">
          <button type="submit" disabled={pending || !h.pl_id} className="rounded-md bg-brand px-8 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Menyimpan..." : h.pl_id ? "Simpan Invoice" : "Pilih Packing List dahulu"}</button>
          <Link href={cancelHref} className="rounded-md border-2 border-line px-8 py-3 text-lg font-semibold hover:bg-background">Batal</Link>
        </div>
      </div>
    </form>
  );
}
