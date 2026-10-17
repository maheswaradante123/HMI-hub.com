"use client";

import Link from "next/link";
import { useActionState, useMemo, useState } from "react";
import { saveDoc, type DocFormState } from "@/app/(app)/d/actions";
import { RO_DELIVERY, RO_PACK, RO_PAYMENT } from "@/lib/docs/config";
import { parseQty } from "@/lib/docs/parse";
import { parseMoney } from "@/lib/pricing/schema";
import { fmtRupiah } from "@/lib/docs/format";

export type RoCustomer = { id: string; name: string; code: string; phone: string; address: string; term: number };
export type RoProduct = { id: string; code: string; name: string; unit: string };
type Row = Record<string, string>;
export type RoValues = { header: Row; items: Row[] };

const inp = "w-full rounded-md border-2 border-line bg-white px-3 py-2.5 text-lg";
const lab = "mb-1 block text-sm font-semibold uppercase tracking-wide text-muted";
const blankItem = (): Row => ({ product_id: "", _text: "", qty: "", unit_price: "", cut_type: "", packaging: "", notes: "" });

function addDays(iso: string, n: number) {
  const d = new Date(`${iso}T00:00:00Z`);
  if (Number.isNaN(d.getTime())) return "";
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}
const suggestEst = (send: string, pay: string) => (!send ? "" : pay === "Tempo" ? addDays(send, 30) : send);

export function RoForm({ id, initial, customers, products, createdBy, number, cancelHref }: {
  id: string; initial: RoValues; customers: RoCustomer[]; products: RoProduct[]; createdBy: string; number: string; cancelHref: string;
}) {
  const [state, action, pending] = useActionState<DocFormState, FormData>(saveDoc.bind(null, "ro", id), {});
  const restored = useMemo<{ header: Row; items: Row[] } | null>(() => {
    if (!state.payload) return null;
    try { const p = JSON.parse(state.payload); return { header: p.header ?? {}, items: p.children?.items ?? [] }; } catch { return null; }
  }, [state.payload]);
  const withText = (rows: Row[]) => rows.map((r) => ({ ...r, _text: r._text ?? products.find((p) => p.id === r.product_id)?.name ?? "" }));
  const [h, setH] = useState<Row>(restored?.header ?? initial.header);
  const [items, setItems] = useState<Row[]>(withText(restored?.items?.length ? restored.items : initial.items.length ? initial.items : [blankItem()]));
  const [estTouched, setEstTouched] = useState(Boolean(initial.header.est_pay_date));

  const setHead = (name: string, v: string) => setH((x) => {
    const n = { ...x, [name]: v };
    if (!estTouched && (name === "delivery_date" || name === "payment_method")) n.est_pay_date = suggestEst(n.delivery_date ?? "", n.payment_method ?? "");
    return n;
  });
  const pickCustomer = (cid: string) => {
    const cu = customers.find((x) => x.id === cid);
    setH((x) => ({
      ...x, customer_id: cid,
      phone: x.phone || cu?.phone || "", delivery_address: x.delivery_address || cu?.address || "",
      payment_method: x.payment_method || (cu && cu.term > 0 ? "Tempo" : x.payment_method || ""),
    }));
  };
  const setItem = (i: number, patch: Row) => setItems((r) => r.map((x, j) => (j === i ? { ...x, ...patch } : x)));
  const typeProduct = (i: number, text: string) => {
    const t = text.trim().toLowerCase();
    const hit = products.find((p) => `${p.code} - ${p.name}`.toLowerCase() === t || p.name.toLowerCase() === t);
    setItem(i, { _text: text, product_id: hit?.id ?? "" });
  };

  const amount = (r: Row) => {
    const q = parseQty(r.qty ?? ""); const p = parseMoney(r.unit_price ?? "");
    return typeof q === "number" && typeof p === "number" ? q * p : 0;
  };
  const total = items.reduce((s, r) => s + amount(r), 0);
  const unitOf = (r: Row) => products.find((p) => p.id === r.product_id)?.unit ?? "";
  const payload = JSON.stringify({ header: h, children: { items: items.map(({ _text, ...r }) => { void _text; return r; }) } });

  return (
    <form action={action} noValidate className="max-w-6xl">
      <input type="hidden" name="payload" value={payload} />
      <div className="space-y-8 rounded-2xl border border-line bg-white p-6 shadow-sm">
        <section>
          <h2 className="mb-4 text-sm font-bold uppercase tracking-widest text-muted">Data pesanan</h2>
          <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-5">
            <div><label className={lab}>Nomor RO</label><input className={`${inp} bg-background text-muted`} readOnly value={number} /></div>
            <div><label className={lab} htmlFor="ro-order">Tanggal pesanan *</label><input id="ro-order" type="date" className={inp} value={h.order_date ?? ""} onChange={(e) => setHead("order_date", e.target.value)} /></div>
            <div className="xl:col-span-1">
              <label className={lab} htmlFor="ro-cust">Pelanggan *</label>
              <select id="ro-cust" className={inp} value={h.customer_id ?? ""} onChange={(e) => pickCustomer(e.target.value)}>
                <option value="">Pilih pelanggan...</option>
                {customers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
              </select>
              <p className="mt-1 text-sm text-muted">Pelanggan baru ditambahkan di <Link className="underline" href="/data/customer">Master Data › Customer</Link>.</p>
            </div>
            <div><label className={lab} htmlFor="ro-name">Nama pemesan</label><input id="ro-name" className={inp} value={h.orderer_name ?? ""} onChange={(e) => setHead("orderer_name", e.target.value)} /></div>
            <div><label className={lab} htmlFor="ro-phone">Nomor telepon</label><input id="ro-phone" className={inp} inputMode="tel" value={h.phone ?? ""} onChange={(e) => setHead("phone", e.target.value)} /></div>
            <div><label className={lab}>Dibuat oleh</label><input className={`${inp} bg-background text-muted`} readOnly value={createdBy} /></div>
            <div className="md:col-span-2"><label className={lab} htmlFor="ro-addr">Alamat pengiriman</label><textarea id="ro-addr" rows={2} className={inp} value={h.delivery_address ?? ""} onChange={(e) => setHead("delivery_address", e.target.value)} /></div>
            <div><label className={lab} htmlFor="ro-send">Tanggal kirim</label><input id="ro-send" type="date" className={inp} value={h.delivery_date ?? ""} onChange={(e) => setHead("delivery_date", e.target.value)} /></div>
            <div><label className={lab} htmlFor="ro-time">Waktu pengiriman</label><input id="ro-time" type="time" className={inp} value={h.delivery_time ?? ""} onChange={(e) => setHead("delivery_time", e.target.value)} /></div>
            <div>
              <label className={lab} htmlFor="ro-pay">Metode pembayaran</label>
              <select id="ro-pay" className={inp} value={h.payment_method ?? ""} onChange={(e) => setHead("payment_method", e.target.value)}>
                <option value="">Pilih...</option>{RO_PAYMENT.map((o) => <option key={o}>{o}</option>)}
              </select>
            </div>
            <div>
              <label className={lab} htmlFor="ro-est">Estimasi tanggal dibayar</label>
              <input id="ro-est" type="date" className={inp} value={h.est_pay_date ?? ""} onChange={(e) => { setEstTouched(true); setH((x) => ({ ...x, est_pay_date: e.target.value })); }} />
              <p className="mt-1 text-sm text-muted">Disarankan dari metode bayar; boleh diubah.</p>
            </div>
            <div>
              <label className={lab} htmlFor="ro-dm">Metode pengiriman</label>
              <select id="ro-dm" className={inp} value={h.delivery_method ?? ""} onChange={(e) => setHead("delivery_method", e.target.value)}>
                <option value="">Pilih...</option>{RO_DELIVERY.map((o) => <option key={o}>{o}</option>)}
              </select>
            </div>
          </div>
        </section>

        <section>
          <h2 className="mb-4 text-sm font-bold uppercase tracking-widest text-muted">Produk</h2>
          <datalist id="ro-products">{products.map((p) => <option key={p.id} value={p.name}>{p.code}</option>)}</datalist>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[960px] text-left">
              <thead>
                <tr className="text-sm uppercase tracking-wide text-muted">
                  <th className="w-8 pb-2">#</th><th className="pb-2">Nama produk</th><th className="w-24 pb-2">Qty</th><th className="w-20 pb-2">Satuan</th>
                  <th className="pb-2">Jenis potongan</th><th className="pb-2">Jenis pengemasan</th><th className="w-36 pb-2">Harga / Kg</th><th className="w-36 pb-2 text-right">Jumlah</th><th className="w-10" />
                </tr>
              </thead>
              <tbody>
                {items.map((r, i) => (
                  <tr key={i} className="align-top">
                    <td className="py-1 pr-2 pt-4 text-muted">{i + 1}</td>
                    <td className="py-1 pr-2">
                      <input list="ro-products" aria-label={`Nama produk ${i + 1}`} className={inp} placeholder="Ketik atau pilih produk" value={r._text ?? ""} onChange={(e) => typeProduct(i, e.target.value)} />
                      {r._text && !r.product_id && <p className="mt-1 text-sm text-danger">Belum ada di daftar produk. Pilih dari saran atau tambahkan di Master Data › Produk.</p>}
                    </td>
                    <td className="py-1 pr-2"><input aria-label={`Qty ${i + 1}`} className={inp} inputMode="decimal" value={r.qty ?? ""} onChange={(e) => setItem(i, { qty: e.target.value })} /></td>
                    <td className="py-1 pr-2 pt-4 text-lg">{unitOf(r)}</td>
                    <td className="py-1 pr-2"><input aria-label={`Jenis potongan ${i + 1}`} className={inp} placeholder="mis. Slice 2 mm" value={r.cut_type ?? ""} onChange={(e) => setItem(i, { cut_type: e.target.value })} /></td>
                    <td className="py-1 pr-2">
                      <select aria-label={`Pengemasan ${i + 1}`} className={inp} value={r.packaging ?? ""} onChange={(e) => setItem(i, { packaging: e.target.value })}>
                        <option value="">Pilih...</option>{RO_PACK.map((o) => <option key={o}>{o}</option>)}
                      </select>
                    </td>
                    <td className="py-1 pr-2"><input aria-label={`Harga ${i + 1}`} className={inp} inputMode="decimal" placeholder="otomatis" value={r.unit_price ?? ""} onChange={(e) => setItem(i, { unit_price: e.target.value })} /></td>
                    <td className="py-1 pr-2 pt-4 text-right text-lg font-semibold">{amount(r) ? fmtRupiah(amount(r)) : "—"}</td>
                    <td className="py-1 pt-3">
                      <button type="button" aria-label={`Hapus produk ${i + 1}`} disabled={items.length === 1} onClick={() => setItems((x) => x.filter((_, j) => j !== i))}
                        className="rounded-md px-3 py-1.5 text-xl text-danger hover:bg-danger-bg disabled:opacity-30">×</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
            <button type="button" onClick={() => setItems((x) => [...x, blankItem()])} className="rounded-md border-2 border-brand px-5 py-2.5 text-lg font-semibold text-brand hover:bg-background">+ Tambah produk</button>
            <p className="text-xl font-bold">Total: {fmtRupiah(total)} <span className="text-sm font-normal text-muted">(harga kosong dihitung otomatis saat disimpan)</span></p>
          </div>
        </section>

        <section>
          <label className={lab} htmlFor="ro-notes">Catatan</label>
          <textarea id="ro-notes" rows={2} className={inp} value={h.notes ?? ""} onChange={(e) => setHead("notes", e.target.value)} />
        </section>

        {state.error && <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-lg text-danger">{state.error}</p>}
        <div className="flex gap-3">
          <button type="submit" disabled={pending} className="rounded-md bg-brand px-8 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Menyimpan..." : "Simpan RO"}</button>
          <Link href={cancelHref} className="rounded-md border-2 border-line px-8 py-3 text-lg font-semibold hover:bg-background">Batal</Link>
        </div>
      </div>
    </form>
  );
}
