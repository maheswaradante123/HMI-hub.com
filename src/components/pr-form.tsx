"use client";

import Link from "next/link";
import { useActionState, useState } from "react";
import { addPrItems, type PrFormState } from "@/app/(app)/purchase-request/actions";
import { PR_AC, PR_CODES, PR_PAY } from "@/lib/pr/lines";
import { parseMoney } from "@/lib/pricing/schema";

type Row = { key: number; ac: string; code: string; item_name: string; price: string; qty: string; unit: string; pay_method: string };
const inputCls = "w-full rounded-md border-2 border-line bg-white px-2 py-2 text-base";
const rupiah = (n: number) => "Rp " + Math.round(n).toLocaleString("id-ID");
const amount = (r: Row) => {
  const p = parseMoney(r.price.trim()); const q = Number(r.qty.replace(/\./g, "").replace(",", "."));
  return (typeof p === "number" ? p : 0) * (Number.isFinite(q) ? q : 0);
};

export function PrForm({ defaultAc, weekText, existing }: { defaultAc: string; weekText: string; existing: boolean }) {
  const [state, action, pending] = useActionState<PrFormState, FormData>(addPrItems, {});
  const blank = (key: number): Row => ({ key, ac: defaultAc, code: "BP", item_name: "", price: "", qty: "", unit: "pcs", pay_method: "tf" });
  const [rows, setRows] = useState<Row[]>(() =>
    state.rows?.length ? state.rows.map((r, i) => ({ key: i, ac: r.ac, code: r.code, item_name: r.item_name, price: r.price, qty: r.qty, unit: r.unit, pay_method: r.pay_method })) : [blank(0)]);
  const [nextKey, setNextKey] = useState(Math.max(rows.length, 1));
  const update = (key: number, patch: Partial<Row>) => setRows((rs) => rs.map((r) => (r.key === key ? { ...r, ...patch } : r)));
  const total = rows.reduce((s, r) => s + amount(r), 0);

  return (
    <form action={action} className="space-y-5" noValidate>
      <p className="text-muted">
        {existing ? "Barang masuk ke lembar PR minggu ini yang sudah ada." : "Lembar PR minggu ini akan dibuat otomatis."} {weekText} Setiap barang berstatus <b>Draft</b> sampai Purchasing mengajukannya ke Owner.
        A/C = siapa yang meminta; Kode biaya = jenis pengeluaran; Pembelian = cara bayar (boleh diketik, mis. “tf arfan”).
      </p>
      {state.error && <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-danger">{state.error}</p>}
      <datalist id="pr-codes">{PR_CODES.map((c) => <option key={c} value={c} />)}</datalist>
      <datalist id="pr-pay">{PR_PAY.map((c) => <option key={c} value={c} />)}</datalist>
      <div className="overflow-x-auto rounded-lg border border-line bg-surface">
        <table className="w-full min-w-[1000px] text-left">
          <thead className="border-b border-line bg-background">
            <tr>{["A/C", "Kode biaya", "Description", "Harga (Rp)", "Qty", "Satuan", "Amount", "Pembelian", ""].map((h) => <th key={h} scope="col" className="px-2 py-2 text-sm font-semibold uppercase tracking-wide text-muted">{h}</th>)}</tr>
          </thead>
          <tbody>
            {rows.map((r, i) => (
              <tr key={r.key} className="border-b border-line last:border-b-0 align-top">
                <td className="px-2 py-2"><select name="ac" aria-label={`A/C baris ${i + 1}`} value={r.ac} onChange={(e) => update(r.key, { ac: e.target.value })} className={inputCls}>{PR_AC.map((a) => <option key={a.value} value={a.value}>{a.value}</option>)}</select></td>
                <td className="px-2 py-2"><input name="code" aria-label={`Kode biaya baris ${i + 1}`} list="pr-codes" value={r.code} onChange={(e) => update(r.key, { code: e.target.value.toUpperCase() })} className={`${inputCls} w-24`} /></td>
                <td className="px-2 py-2"><input name="item_name" aria-label={`Description baris ${i + 1}`} value={r.item_name} onChange={(e) => update(r.key, { item_name: e.target.value })} className={`${inputCls} min-w-[240px]`} placeholder="mis. Rumput Prio (21 April)" autoComplete="off" /></td>
                <td className="px-2 py-2"><input name="price" aria-label={`Harga baris ${i + 1}`} inputMode="decimal" value={r.price} onChange={(e) => update(r.key, { price: e.target.value })} className={`${inputCls} w-32`} /></td>
                <td className="px-2 py-2"><input name="qty" aria-label={`Qty baris ${i + 1}`} inputMode="decimal" value={r.qty} onChange={(e) => update(r.key, { qty: e.target.value })} className={`${inputCls} w-24`} /></td>
                <td className="px-2 py-2"><input name="unit" aria-label={`Satuan baris ${i + 1}`} value={r.unit} onChange={(e) => update(r.key, { unit: e.target.value })} className={`${inputCls} w-24`} /></td>
                <td className="px-2 py-3 text-right tabular-nums whitespace-nowrap">{rupiah(amount(r))}</td>
                <td className="px-2 py-2"><input name="pay_method" aria-label={`Pembelian baris ${i + 1}`} list="pr-pay" value={r.pay_method} onChange={(e) => update(r.key, { pay_method: e.target.value })} className={`${inputCls} w-36`} /></td>
                <td className="px-2 py-2">{rows.length > 1 && <button type="button" onClick={() => setRows((rs) => rs.filter((x) => x.key !== r.key))} aria-label={`Hapus baris ${i + 1}`} className="rounded-md border-2 border-line px-3 py-1.5 font-semibold hover:bg-background">×</button>}</td>
              </tr>
            ))}
          </tbody>
          <tfoot><tr><td colSpan={6} className="px-2 py-3 text-right font-semibold">Total</td><td className="px-2 py-3 text-right font-bold tabular-nums whitespace-nowrap">{rupiah(total)}</td><td colSpan={2} /></tr></tfoot>
        </table>
      </div>
      <div className="flex flex-wrap gap-3">
        <button type="button" onClick={() => { setRows((rs) => [...rs, blank(nextKey)]); setNextKey((k) => k + 1); }} className="rounded-md border-2 border-line px-5 py-3 text-lg font-semibold hover:bg-background">+ Tambah barang</button>
        <button type="submit" disabled={pending} className="rounded-md bg-brand px-6 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Menyimpan..." : "Simpan sebagai Draft"}</button>
        <Link href="/purchase-request" className="rounded-md border-2 border-line px-6 py-3 text-lg font-semibold hover:bg-background">Batal</Link>
      </div>
    </form>
  );
}
