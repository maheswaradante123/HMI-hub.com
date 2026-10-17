"use client";

import { useActionState, useState } from "react";
import { createOrder, type QState } from "@/app/(app)/qurban/actions";
import { Field, fieldCls } from "./qform";

type Cls = { min_kg: number; max_kg: number | null; buy_price: number; care_price: number; buyback_price: number };
const rp = (n: number) => "Rp " + Math.round(n).toLocaleString("id-ID");

export function OrderForm({ classes, today, careEnd }: { classes: Cls[]; today: string; careEnd: string }) {
  const [state, run, pending] = useActionState<QState, FormData>(createOrder, {});
  const [w, setW] = useState("");
  const wn = Number(w.replace(",", "."));
  const cls = wn > 0 ? [...classes].sort((a, b) => b.min_kg - a.min_kg).find((c) => c.min_kg <= wn) : undefined;

  return (
    <form action={run} className="max-w-2xl space-y-5" noValidate>
      <p className="rounded-md bg-warn-bg px-4 py-3">Untuk proforma cukup nama panggilan pelanggan. Nama lengkap, KTP, dan alamat diisi nanti saat membuat Surat Perjanjian.</p>
      <div className="grid gap-5 sm:grid-cols-2">
        <Field id="nick" label="Nama panggilan pelanggan"><input id="nick" name="nick" className={fieldCls} autoComplete="off" /></Field>
        <Field id="cow" label="Nomor sapi" hint="Boleh sama dengan sapi pelanggan lain."><input id="cow" name="cow" className={fieldCls} autoComplete="off" /></Field>
        <Field id="weight" label="Hasil timbang (Kg)"><input id="weight" name="weight" inputMode="decimal" value={w} onChange={(e) => setW(e.target.value)} className={fieldCls} placeholder="contoh 612,5" /></Field>
        <Field id="start" label="Mulai pemeliharaan" hint={`Perawatan dihitung sampai ${careEnd.split("-").reverse().join("-")}.`}><input id="start" name="start" type="date" defaultValue={today} className={fieldCls} /></Field>
      </div>
      <fieldset>
        <legend className="mb-2 font-semibold">Cara bayar perawatan</legend>
        <label className="mb-2 flex items-start gap-3 text-lg"><input type="radio" name="mode" value="FULL" defaultChecked className="mt-1.5 h-5 w-5" /><span><b>Lunas di awal</b> — tarif perawatan tetap sesuai kelas saat beli, semua bulan sampai akhir masa perawatan ada di invoice.</span></label>
        <label className="flex items-start gap-3 text-lg"><input type="radio" name="mode" value="MONTHLY" className="mt-1.5 h-5 w-5" /><span><b>Bayar per bulan</b> — invoice awal hanya sapi dan bulan pertama; tiap bulan ditagih dengan tarif sesuai kelas bobot timbang terakhir.</span></label>
      </fieldset>
      <div aria-live="polite" className="rounded-lg border border-line bg-surface p-4">
        {cls ? (
          <>
            <p className="font-semibold">Kelas {cls.min_kg}{cls.max_kg ? `–${cls.max_kg}` : "+"} Kg</p>
            <p>Harga beli {rp(cls.buy_price)}/Kg · perawatan {rp(cls.care_price)}/hari · beli kembali {rp(cls.buyback_price)}/Kg</p>
            <p className="mt-1 text-muted">Harga sapi: {rp(cls.buy_price * wn)}</p>
          </>
        ) : <p className="text-muted">{wn > 0 ? "Bobot di bawah 350 Kg tidak ada di daftar harga." : "Isi hasil timbang untuk melihat kelas dan harga."}</p>}
      </div>
      {state.error && <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-danger">{state.error}</p>}
      <button type="submit" disabled={pending} className="rounded-md bg-brand px-8 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Menyimpan..." : "Buat proforma"}</button>
    </form>
  );
}
