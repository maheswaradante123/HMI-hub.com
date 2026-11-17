"use client";

import { useActionState, useState } from "react";
import { createOrder, type QState } from "@/app/(app)/qurban/actions";
import { Field, fieldCls } from "./qform";

type Cls = { min_kg: number; max_kg: number | null; buy_price: number; care_price: number; buyback_price: number };
type Row = { id: number; w: string; head: boolean; hp: string };
const rp = (n: number) => "Rp " + Math.round(n).toLocaleString("id-ID");

export function OrderForm({ classes, today, careEnd }: { classes: Cls[]; today: string; careEnd: string }) {
  const [state, run, pending] = useActionState<QState, FormData>(createOrder, {});
  // Setiap baris = satu sapi. Id baris tetap supaya isian tidak tertukar saat ada baris dihapus.
  const [rows, setRows] = useState<Row[]>([{ id: 1, w: "", head: false, hp: "" }]);
  const [next, setNext] = useState(2);
  const sorted = [...classes].sort((a, b) => b.min_kg - a.min_kg);
  const clsOf = (w: string) => { const n = Number(w.replace(",", ".")); return n > 0 ? sorted.find((c) => c.min_kg <= n) : undefined; };
  const filled = rows.filter((r) => (r.head ? r.hp.trim() : r.w.trim())).length;
  const upd = (id: number, patch: Partial<Row>) => setRows(rows.map((x) => (x.id === id ? { ...x, ...patch } : x)));

  return (
    <form action={run} className="max-w-3xl space-y-5" noValidate>
      <p className="rounded-md bg-warn-bg px-4 py-3">Untuk proforma cukup nama panggilan pelanggan. Nama lengkap, KTP, dan alamat diisi nanti saat membuat Surat Perjanjian.</p>
      <input type="hidden" name="rows" value={rows.map((r) => r.id).join(",")} />
      <div className="grid gap-5 sm:grid-cols-2">
        <Field id="nick" label="Nama panggilan pelanggan"><input id="nick" name="nick" className={fieldCls} autoComplete="off" /></Field>
        <Field id="start" label="Mulai pemeliharaan" hint={`Perawatan dihitung sampai ${careEnd.split("-").reverse().join("-")}.`}><input id="start" name="start" type="date" defaultValue={today} className={fieldCls} /></Field>
      </div>
      <fieldset>
        <legend className="mb-1 font-semibold">Sapi yang dipesan</legend>
        <p className="mb-3 text-muted">Pelanggan beli satu sapi? Isi satu baris saja. Beli beberapa sapi sekaligus? Tambah baris, semuanya jadi satu proforma dan satu invoice. Sapi lain yang dibeli di hari berbeda bisa digabung belakangan dari halaman pesanan.</p>
        <ul className="space-y-3">
          {rows.map((r, i) => {
            const c = clsOf(r.w); const n = Number(r.w.replace(",", "."));
            return (
              <li key={r.id} className="rounded-lg border border-line bg-surface p-4">
                <div className="grid items-end gap-4 sm:grid-cols-[1fr_1fr_auto]">
                  <Field id={`cow_${r.id}`} label={`Nomor sapi${rows.length > 1 ? ` ${i + 1}` : ""}`}><input id={`cow_${r.id}`} name={`cow_${r.id}`} className={fieldCls} autoComplete="off" /></Field>
                  {r.head ? (
                    <Field id={`weight_${r.id}`} label="Bobot awal (Kg), boleh dikosongkan" hint="Hanya dicatat, tidak memengaruhi harga."><input id={`weight_${r.id}`} name={`weight_${r.id}`} inputMode="decimal" value={r.w} onChange={(e) => upd(r.id, { w: e.target.value })} className={fieldCls} placeholder="contoh 280" /></Field>
                  ) : (
                    <Field id={`weight_${r.id}`} label="Hasil timbang (Kg)"><input id={`weight_${r.id}`} name={`weight_${r.id}`} inputMode="decimal" value={r.w} onChange={(e) => upd(r.id, { w: e.target.value })} className={fieldCls} placeholder="contoh 612,5" /></Field>
                  )}
                  {rows.length > 1 && <button type="button" onClick={() => setRows(rows.filter((x) => x.id !== r.id))} className="rounded-md border-2 border-line px-4 py-2.5 text-lg font-semibold text-danger">Hapus</button>}
                </div>
                <label className="mt-3 flex items-center gap-3 text-lg"><input type="checkbox" name={`head_${r.id}`} checked={r.head} onChange={(e) => upd(r.id, { head: e.target.checked })} className="h-5 w-5" /><span><b>Jual per ekor (sapi jogrok)</b> — harga tidak dihitung dari timbangan</span></label>
                {r.head && (
                  <div className="mt-3 grid gap-4 sm:grid-cols-3">
                    <Field id={`hp_${r.id}`} label="Harga sapi per ekor (Rp)"><input id={`hp_${r.id}`} name={`hp_${r.id}`} inputMode="numeric" value={r.hp} onChange={(e) => upd(r.id, { hp: e.target.value })} className={fieldCls} placeholder="contoh 18000000" /></Field>
                    <Field id={`cp_${r.id}`} label="Perawatan per hari (Rp)"><input id={`cp_${r.id}`} name={`cp_${r.id}`} inputMode="numeric" className={fieldCls} placeholder="contoh 25000" /></Field>
                    <Field id={`bb_${r.id}`} label="Beli kembali per ekor (Rp)"><input id={`bb_${r.id}`} name={`bb_${r.id}`} inputMode="numeric" className={fieldCls} placeholder="contoh 15000000" /></Field>
                  </div>
                )}
                <p aria-live="polite" className="mt-2 text-muted">
                  {r.head ? "Sapi jogrok: harga, tarif perawatan, dan nilai beli kembali diisi manual per ekor." : c ? <>Kelas {c.min_kg}{c.max_kg ? `–${c.max_kg}` : "+"} Kg · beli {rp(c.buy_price)}/Kg · perawatan {rp(c.care_price)}/hari · beli kembali {rp(c.buyback_price)}/Kg · <b>harga sapi {rp(c.buy_price * n)}</b></> : n > 0 ? "Bobot di bawah 350 Kg tidak ada di daftar harga." : "Isi hasil timbang untuk melihat kelas dan harga."}
                </p>
              </li>
            );
          })}
        </ul>
        <button type="button" onClick={() => { setRows([...rows, { id: next, w: "", head: false, hp: "" }]); setNext(next + 1); }} className="mt-3 rounded-md border-2 border-brand px-5 py-2.5 text-lg font-semibold text-brand">+ Tambah sapi</button>
      </fieldset>
      <fieldset>
        <legend className="mb-2 font-semibold">Cara bayar perawatan{rows.length > 1 ? " (berlaku untuk semua sapi di atas)" : ""}</legend>
        <label className="mb-2 flex items-start gap-3 text-lg"><input type="radio" name="mode" value="FULL" defaultChecked className="mt-1.5 h-5 w-5" /><span><b>Lunas di awal</b> — tarif perawatan tetap sesuai kelas saat beli, semua bulan sampai akhir masa perawatan ada di invoice.</span></label>
        <label className="flex items-start gap-3 text-lg"><input type="radio" name="mode" value="MONTHLY" className="mt-1.5 h-5 w-5" /><span><b>Bayar per bulan</b> — invoice awal hanya sapi dan bulan pertama; tiap bulan ditagih dengan tarif sesuai kelas bobot timbang terakhir.</span></label>
      </fieldset>
      {state.error && <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-danger">{state.error}</p>}
      <button type="submit" disabled={pending} className="rounded-md bg-brand px-8 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Menyimpan..." : filled > 1 ? `Buat proforma ${filled} sapi` : "Buat proforma"}</button>
    </form>
  );
}
