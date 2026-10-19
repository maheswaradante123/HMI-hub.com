"use client";

import Link from "next/link";
import { useActionState, useState } from "react";
import { recordMovement, type StockFormState } from "@/app/(app)/stok/actions";

const inputCls = "w-full rounded-md border-2 border-line bg-white px-4 py-3 text-lg";
const TYPES = [
  { v: "OPENING", l: "Stok awal" },
  { v: "IN_PURCHASE", l: "Pembelian masuk (dengan harga beli)" },
  { v: "ADJUST_IN", l: "Penyesuaian tambah (wajib alasan)" },
  { v: "ADJUST_OUT", l: "Penyesuaian kurang (wajib alasan)" },
];

export function StockForm({ products, warehouses, lots, canCost, today, initialProduct }: {
  products: { id: string; label: string; unit: string; unitName: string }[]; warehouses: { id: string; name: string }[]; lots: string[]; canCost: boolean; today: string; initialProduct: string;
}) {
  const [state, action, pending] = useActionState<StockFormState, FormData>(recordMovement, {});
  const v = state.values ?? { product: initialProduct, warehouse: warehouses[0]?.id ?? "", type: "OPENING", qty: "", lot: "", cost: "", date: today, note: "" };
  const [type, setType] = useState(v.type);
  const [productId, setProductId] = useState(v.product);
  const unit = products.find((p) => p.id === productId);
  const gram = unit?.unit === "GRAM";
  return (
    <form action={action} className="max-w-2xl space-y-5" noValidate>
      <div>
        <label htmlFor="product" className="mb-1 block text-lg font-semibold">Produk <span className="text-danger">*</span></label>
        <select id="product" name="product" value={productId} onChange={(e) => setProductId(e.target.value)} className={inputCls}>
          <option value="">Pilih...</option>
          {products.map((p) => <option key={p.id} value={p.id}>{p.label}</option>)}
        </select>
      </div>
      <div>
        <label htmlFor="warehouse" className="mb-1 block text-lg font-semibold">Gudang <span className="text-danger">*</span></label>
        <select id="warehouse" name="warehouse" defaultValue={v.warehouse} className={inputCls}>
          <option value="">Pilih...</option>
          {warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
        </select>
      </div>
      <div>
        <label htmlFor="type" className="mb-1 block text-lg font-semibold">Jenis pencatatan <span className="text-danger">*</span></label>
        <select id="type" name="type" value={type} onChange={(e) => setType(e.target.value)} className={inputCls}>
          {TYPES.filter((t) => canCost || t.v !== "IN_PURCHASE").map((t) => <option key={t.v} value={t.v}>{t.l}</option>)}
        </select>
      </div>
      <div>
        <label htmlFor="qty" className="mb-1 block text-lg font-semibold">Jumlah{unit?.unitName ? ` (${unit.unitName})` : ""} <span className="text-danger">*</span></label>
        <input id="qty" name="qty" defaultValue={v.qty} inputMode={gram ? "numeric" : "decimal"} autoComplete="off" className={inputCls} />
        <p className="mt-1 text-sm text-muted">{gram ? "Dalam gram, bilangan bulat. Contoh: 14620 (sama dengan 14,62 kg)" : "Contoh: 12,5"}</p>
      </div>
      <div>
        <label htmlFor="lot" className="mb-1 block text-lg font-semibold">Kode sapi <span className="font-normal text-muted">(opsional)</span></label>
        <input id="lot" name="lot" list="stock-lots" defaultValue={v.lot} autoComplete="off" maxLength={40} className={`${inputCls} uppercase`} />
        <datalist id="stock-lots">{lots.map((l) => <option key={l} value={l} />)}</datalist>
        <p className="mt-1 text-sm text-muted">Isi bila stok ini berasal dari, atau diambil dari, sapi tertentu. Untuk pengurangan tanpa kode sapi, jumlahnya dihitung dari sapi yang masuk lebih dulu.</p>
      </div>
      {canCost && type === "IN_PURCHASE" && (
        <div>
          <label htmlFor="cost" className="mb-1 block text-lg font-semibold">Harga beli per {unit?.unitName ? unit.unitName.toLowerCase() : "satuan"} <span className="text-danger">*</span></label>
          <input id="cost" name="cost" defaultValue={v.cost} inputMode="decimal" autoComplete="off" className={inputCls} />
          <p className="mt-1 text-sm text-muted">Harga ini dipakai sebagai harga beli terakhir untuk nilai stok.</p>
        </div>
      )}
      <div>
        <label htmlFor="date" className="mb-1 block text-lg font-semibold">Tanggal</label>
        <input id="date" name="date" type="date" defaultValue={v.date} className={inputCls} />
      </div>
      <div>
        <label htmlFor="note" className="mb-1 block text-lg font-semibold">Catatan / alasan</label>
        <textarea id="note" name="note" rows={2} defaultValue={v.note} className={inputCls} />
      </div>
      {state.error && <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-lg text-danger">{state.error}</p>}
      <div className="flex gap-3">
        <button type="submit" disabled={pending} className="rounded-md bg-brand px-8 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Menyimpan..." : "Simpan"}</button>
        <Link href="/stok" className="rounded-md border-2 border-line px-8 py-3 text-lg font-semibold hover:bg-background">Batal</Link>
      </div>
    </form>
  );
}
