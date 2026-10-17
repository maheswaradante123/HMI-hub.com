"use client";

import { useActionState } from "react";
import { saveTax, type TaxState } from "@/app/(app)/pengaturan-pajak/actions";

const inputCls = "w-full rounded-md border-2 border-line bg-white px-4 py-3 text-lg";
export function TaxForm({ label, rate }: { label: string; rate: string }) {
  const [state, action, pending] = useActionState<TaxState, FormData>(saveTax, {});
  return (
    <form action={action} className="max-w-md space-y-5" noValidate>
      <div><label htmlFor="label" className="mb-1 block text-lg font-semibold">Nama pajak</label><input id="label" name="label" defaultValue={label} className={inputCls} /></div>
      <div><label htmlFor="rate" className="mb-1 block text-lg font-semibold">Tarif (%)</label><input id="rate" name="rate" defaultValue={rate} inputMode="decimal" className={inputCls} /></div>
      {state.error && <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-danger">{state.error}</p>}
      {state.ok && <p role="status" className="rounded-md bg-warn-bg px-4 py-3">Pengaturan pajak tersimpan.</p>}
      <button type="submit" disabled={pending} className="rounded-md bg-brand px-8 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Menyimpan..." : "Simpan"}</button>
    </form>
  );
}
