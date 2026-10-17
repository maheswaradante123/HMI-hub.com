"use client";

import Link from "next/link";
import { useActionState } from "react";
import { setPrice, voidPrice, type PriceFormState, type VoidState } from "@/app/(app)/pricing-toko/actions";

const inputCls = "w-full rounded-md border-2 border-line bg-white px-4 py-3 text-lg";

export function PriceForm({
  productId,
  showCost,
  suppliers,
  initial,
  minDate,
}: {
  productId: string;
  showCost: boolean;
  suppliers: { id: string; name: string }[];
  initial: { sell: string; buy: string; supplier: string; from: string; note: string };
  minDate: string | null;
}) {
  const [state, action, pending] = useActionState<PriceFormState, FormData>(setPrice.bind(null, productId), {});
  const v = state.values ?? initial;
  return (
    <form action={action} className="max-w-2xl space-y-5" noValidate>
      <div>
        <label htmlFor="sell" className="mb-1 block text-lg font-semibold">Harga jual (Rp)</label>
        <input id="sell" name="sell" inputMode="numeric" autoComplete="off" defaultValue={v.sell} className={inputCls} />
        <p className="mt-1 text-sm text-muted">Contoh: 118.000</p>
      </div>
      {showCost && (
        <>
          <div>
            <label htmlFor="buy" className="mb-1 block text-lg font-semibold">Harga beli (Rp)</label>
            <input id="buy" name="buy" inputMode="numeric" autoComplete="off" defaultValue={v.buy} className={inputCls} />
          </div>
          <div>
            <label htmlFor="supplier" className="mb-1 block text-lg font-semibold">Supplier</label>
            <select id="supplier" name="supplier" defaultValue={v.supplier} className={inputCls}>
              <option value="">Tidak dipilih</option>
              {suppliers.map((s) => (
                <option key={s.id} value={s.id}>{s.name}</option>
              ))}
            </select>
          </div>
        </>
      )}
      <div>
        <label htmlFor="from" className="mb-1 block text-lg font-semibold">Tanggal berlaku</label>
        <input id="from" name="from" type="date" defaultValue={v.from} min={minDate ?? undefined} className={inputCls} />
        <p className="mt-1 text-sm text-muted">
          Harga lama tetap tersimpan di riwayat dan otomatis berakhir sehari sebelum tanggal ini.
          {minDate && " Tanggal harus setelah tanggal berlaku harga terakhir."}
        </p>
      </div>
      <div>
        <label htmlFor="note" className="mb-1 block text-lg font-semibold">Catatan</label>
        <input id="note" name="note" autoComplete="off" defaultValue={v.note} className={inputCls} />
      </div>

      {state.error && (
        <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-danger">{state.error}</p>
      )}
      <div className="flex gap-3">
        <button type="submit" disabled={pending} className="rounded-md bg-brand px-6 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">
          {pending ? "Menyimpan..." : "Simpan harga"}
        </button>
        <Link href={`/pricing-toko/${productId}`} className="rounded-md border-2 border-line px-6 py-3 text-lg font-semibold hover:bg-background">
          Batal
        </Link>
      </div>
    </form>
  );
}

export function VoidForm({ productId, priceId }: { productId: string; priceId: string }) {
  const [state, action, pending] = useActionState<VoidState, FormData>(voidPrice.bind(null, productId, priceId), {});
  return (
    <form action={action} className="mt-2 space-y-2">
      <label htmlFor={`void-${priceId}`} className="block font-semibold">Alasan pembatalan (wajib)</label>
      <input id={`void-${priceId}`} name="reason" autoComplete="off" className="w-full max-w-md rounded-md border-2 border-line bg-white px-3 py-2 text-lg" />
      {state.error && <p role="alert" className="rounded-md bg-danger-bg px-3 py-2 text-danger">{state.error}</p>}
      <button type="submit" disabled={pending} className="rounded-md border-2 border-danger px-4 py-2 font-semibold text-danger hover:bg-danger-bg disabled:opacity-60">
        {pending ? "Memproses..." : "Batalkan harga ini"}
      </button>
    </form>
  );
}
