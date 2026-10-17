"use client";

import { useActionState, type ReactNode } from "react";
import type { QState } from "@/app/(app)/qurban/actions";

type Action = (prev: QState, f: FormData) => Promise<QState>;

// Formulir kecil untuk satu aksi Qurban: kolom isian, tombol, pesan hasil.
export function QForm({
  action, label, children, danger, inline,
}: { action: Action; label: string; children?: ReactNode; danger?: boolean; inline?: boolean }) {
  const [state, run, pending] = useActionState<QState, FormData>(action, {});
  return (
    <form action={run} className={inline ? "flex flex-wrap items-end gap-3" : "space-y-3"}>
      {children}
      <button
        type="submit"
        disabled={pending}
        className={`rounded-md px-5 py-2.5 text-lg font-semibold disabled:opacity-60 ${danger ? "bg-danger text-white" : "bg-brand text-white hover:bg-brand-dark"}`}
      >
        {pending ? "Memproses..." : label}
      </button>
      {state.error && <p role="alert" className="w-full rounded-md bg-danger-bg px-3 py-2 text-danger">{state.error}</p>}
      {state.ok && <p role="status" className="w-full rounded-md bg-warn-bg px-3 py-2">{state.ok}</p>}
    </form>
  );
}

export const fieldCls = "w-full rounded-md border-2 border-line bg-white px-3 py-2.5 text-lg";
export function Field({ label, id, children, hint }: { label: string; id: string; children: ReactNode; hint?: string }) {
  return (
    <div>
      <label htmlFor={id} className="mb-1 block font-semibold">{label}</label>
      {children}
      {hint && <p className="mt-1 text-sm text-muted">{hint}</p>}
    </div>
  );
}
