"use client";

import { useActionState } from "react";
import { setCustomerPrice, voidCustomerPrice, type CPState } from "@/app/(app)/harga-customer/actions";

const inputCls = "w-full rounded-md border-2 border-line bg-white px-3 py-2.5 text-lg";

export function CustomerPriceForm({ customerId, products, today }: { customerId: string; products: { id: string; label: string }[]; today: string }) {
  const [state, action, pending] = useActionState<CPState, FormData>(setCustomerPrice.bind(null, customerId), {});
  const v = state.values ?? { product: "", price: "", from: today, note: "" };
  return (
    <form action={action} className="grid gap-4 rounded-lg border border-line bg-surface p-5 md:grid-cols-4" noValidate>
      <div className="md:col-span-2">
        <label htmlFor="product" className="mb-1 block font-semibold">Produk</label>
        <select id="product" name="product" defaultValue={v.product} className={inputCls}>
          <option value="">Pilih...</option>
          {products.map((p) => <option key={p.id} value={p.id}>{p.label}</option>)}
        </select>
      </div>
      <div>
        <label htmlFor="price" className="mb-1 block font-semibold">Harga per satuan</label>
        <input id="price" name="price" defaultValue={v.price} inputMode="decimal" autoComplete="off" className={inputCls} />
      </div>
      <div>
        <label htmlFor="from" className="mb-1 block font-semibold">Berlaku mulai</label>
        <input id="from" name="from" type="date" defaultValue={v.from} className={inputCls} />
      </div>
      <div className="md:col-span-3">
        <label htmlFor="note" className="mb-1 block font-semibold">Catatan</label>
        <input id="note" name="note" defaultValue={v.note} className={inputCls} />
      </div>
      <div className="flex items-end">
        <button type="submit" disabled={pending} className="w-full rounded-md bg-brand px-6 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Menyimpan..." : "Simpan harga"}</button>
      </div>
      {state.error && <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-danger md:col-span-4">{state.error}</p>}
    </form>
  );
}

export function VoidCustomerPrice({ customerId, priceId }: { customerId: string; priceId: string }) {
  const [state, action, pending] = useActionState<CPState, FormData>(voidCustomerPrice.bind(null, customerId, priceId), {});
  return (
    <form action={action} className="flex flex-wrap items-center gap-2">
      <label htmlFor={`r-${priceId}`} className="sr-only">Alasan pembatalan</label>
      <input id={`r-${priceId}`} name="reason" placeholder="Alasan pembatalan" className="rounded-md border-2 border-line bg-white px-3 py-2" />
      <button type="submit" disabled={pending} className="rounded-md border-2 border-danger px-4 py-2 font-semibold text-danger hover:bg-danger-bg disabled:opacity-60">{pending ? "..." : "Batalkan"}</button>
      {state.error && <span role="alert" className="text-danger">{state.error}</span>}
    </form>
  );
}
