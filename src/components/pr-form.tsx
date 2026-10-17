"use client";

import Link from "next/link";
import { useActionState, useState } from "react";
import { savePr, type PrFormState } from "@/app/(app)/purchase-request/actions";

type Opt = { id: string; name: string; unit_id?: string | null };
type Row = {
  key: number;
  product_id: string;
  item_name: string;
  qty: string;
  unit_id: string;
  estimated_price: string;
  notes: string;
};
const inputCls = "w-full rounded-md border-2 border-line bg-white px-3 py-2.5 text-lg";

export function PrForm({
  id,
  products,
  units,
  initial,
}: {
  id: string | null;
  products: Opt[];
  units: Opt[];
  initial: { reason: string; priority: string; rows: Omit<Row, "key">[] };
}) {
  const [state, action, pending] = useActionState<PrFormState, FormData>(savePr.bind(null, id), {});
  const blank = (key: number): Row => ({
    key, product_id: "", item_name: "", qty: "", unit_id: "", estimated_price: "", notes: "",
  });
  const [rows, setRows] = useState<Row[]>(
    initial.rows.length ? initial.rows.map((r, i) => ({ ...r, key: i })) : [blank(0)],
  );
  const [nextKey, setNextKey] = useState(Math.max(initial.rows.length, 1));

  const update = (key: number, patch: Partial<Row>) =>
    setRows((rs) => rs.map((r) => (r.key === key ? { ...r, ...patch } : r)));

  const pickProduct = (key: number, productId: string) => {
    const p = products.find((x) => x.id === productId);
    update(key, {
      product_id: productId,
      ...(p ? { item_name: p.name, unit_id: p.unit_id ?? "" } : {}),
    });
  };

  return (
    <form action={action} className="max-w-5xl space-y-6" noValidate>
      <div className="grid gap-5 md:grid-cols-3">
        <div className="md:col-span-2">
          <label htmlFor="reason" className="mb-1 block text-lg font-semibold">
            Alasan pembelian <span className="text-danger">*</span>
          </label>
          <textarea
            id="reason" name="reason" rows={3} className={inputCls}
            defaultValue={state.values?.reason ?? initial.reason}
          />
        </div>
        <div>
          <label htmlFor="priority" className="mb-1 block text-lg font-semibold">
            Prioritas
          </label>
          <select id="priority" name="priority" className={inputCls} defaultValue={state.values?.priority ?? initial.priority}>
            <option value="LOW">Rendah</option>
            <option value="NORMAL">Normal</option>
            <option value="HIGH">Tinggi</option>
          </select>
        </div>
      </div>

      <fieldset>
        <legend className="mb-2 text-xl font-bold">Barang yang diminta</legend>
        <div className="space-y-4">
          {rows.map((r, i) => (
            <div key={r.key} className="rounded-lg border border-line bg-surface p-4">
              <div className="mb-3 flex items-center justify-between">
                <p className="text-lg font-semibold">Barang {i + 1}</p>
                {rows.length > 1 && (
                  <button
                    type="button"
                    onClick={() => setRows((rs) => rs.filter((x) => x.key !== r.key))}
                    className="rounded-md border-2 border-line px-3 py-1.5 font-semibold hover:bg-background"
                  >
                    Hapus barang ini
                  </button>
                )}
              </div>
              <div className="grid gap-4 md:grid-cols-6">
                <div className="md:col-span-3">
                  <label htmlFor={`product-${r.key}`} className="mb-1 block font-semibold">
                    Pilih dari daftar produk (boleh dikosongkan)
                  </label>
                  <select
                    id={`product-${r.key}`} name="product_id" className={inputCls}
                    value={r.product_id} onChange={(e) => pickProduct(r.key, e.target.value)}
                  >
                    <option value="">Barang lain (ketik sendiri)</option>
                    {products.map((p) => (
                      <option key={p.id} value={p.id}>{p.name}</option>
                    ))}
                  </select>
                </div>
                <div className="md:col-span-3">
                  <label htmlFor={`name-${r.key}`} className="mb-1 block font-semibold">
                    Nama barang <span className="text-danger">*</span>
                  </label>
                  <input
                    id={`name-${r.key}`} name="item_name" className={inputCls} autoComplete="off"
                    value={r.item_name} onChange={(e) => update(r.key, { item_name: e.target.value })}
                  />
                </div>
                <div className="md:col-span-2">
                  <label htmlFor={`qty-${r.key}`} className="mb-1 block font-semibold">
                    Jumlah <span className="text-danger">*</span>
                  </label>
                  <input
                    id={`qty-${r.key}`} name="qty" inputMode="decimal" className={inputCls}
                    value={r.qty} onChange={(e) => update(r.key, { qty: e.target.value })}
                  />
                </div>
                <div className="md:col-span-2">
                  <label htmlFor={`unit-${r.key}`} className="mb-1 block font-semibold">
                    Satuan <span className="text-danger">*</span>
                  </label>
                  <select
                    id={`unit-${r.key}`} name="unit_id" className={inputCls}
                    value={r.unit_id} onChange={(e) => update(r.key, { unit_id: e.target.value })}
                  >
                    <option value="">Pilih...</option>
                    {units.map((u) => (
                      <option key={u.id} value={u.id}>{u.name}</option>
                    ))}
                  </select>
                </div>
                <div className="md:col-span-2">
                  <label htmlFor={`price-${r.key}`} className="mb-1 block font-semibold">
                    Estimasi harga per satuan (Rp)
                  </label>
                  <input
                    id={`price-${r.key}`} name="estimated_price" inputMode="numeric" className={inputCls}
                    value={r.estimated_price} onChange={(e) => update(r.key, { estimated_price: e.target.value })}
                  />
                </div>
                <div className="md:col-span-6">
                  <label htmlFor={`notes-${r.key}`} className="mb-1 block font-semibold">
                    Catatan barang
                  </label>
                  <input
                    id={`notes-${r.key}`} name="notes" className={inputCls} autoComplete="off"
                    value={r.notes} onChange={(e) => update(r.key, { notes: e.target.value })}
                  />
                </div>
              </div>
            </div>
          ))}
        </div>
        <button
          type="button"
          onClick={() => {
            setRows((rs) => [...rs, blank(nextKey)]);
            setNextKey((k) => k + 1);
          }}
          className="mt-4 rounded-md border-2 border-brand px-5 py-2.5 text-lg font-semibold text-brand hover:bg-background"
        >
          + Tambah barang
        </button>
      </fieldset>

      {state.error && (
        <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-danger">
          {state.error}
        </p>
      )}

      <div className="flex flex-wrap gap-3">
        <button
          type="submit" name="intent" value="submit" disabled={pending}
          className="rounded-md bg-brand px-6 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60"
        >
          {pending ? "Menyimpan..." : "Simpan dan ajukan"}
        </button>
        <button
          type="submit" name="intent" value="draft" disabled={pending}
          className="rounded-md border-2 border-line px-6 py-3 text-lg font-semibold hover:bg-background disabled:opacity-60"
        >
          Simpan sebagai draf
        </button>
        <Link
          href={id ? `/purchase-request/${id}` : "/purchase-request"}
          className="rounded-md px-6 py-3 text-lg font-semibold underline"
        >
          Batal
        </Link>
      </div>
    </form>
  );
}
