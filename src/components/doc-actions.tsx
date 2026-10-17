"use client";

import { useActionState } from "react";
import { changeDocStatus, closePr, type DocActionState } from "@/app/(app)/d/actions";
import { RULE_STYLE } from "@/lib/docs/rules";

function Btn({ slug, id, to, label, needsNote }: { slug: string; id: string; to: string; label: string; needsNote: boolean }) {
  const [state, action, pending] = useActionState<DocActionState, FormData>(changeDocStatus.bind(null, slug, id, to), {});
  const danger = ["CANCELLED", "VOID", "REJECTED"].includes(to);
  return (
    <form action={action} className="space-y-2">
      {needsNote && (
        <div>
          <label htmlFor={`note-${to}`} className="mb-1 block font-semibold">{danger ? "Alasan (wajib)" : "Catatan (wajib)"}</label>
          <textarea id={`note-${to}`} name="note" rows={2} className="w-full rounded-md border-2 border-line bg-white px-3 py-2.5 text-lg" />
        </div>
      )}
      {state.error && <p role="alert" className="rounded-md bg-danger-bg px-3 py-2 text-danger">{state.error}</p>}
      <button type="submit" disabled={pending} className={`rounded-md px-5 py-3 text-lg font-semibold disabled:opacity-60 ${RULE_STYLE(to)}`}>
        {pending ? "Memproses..." : label}
      </button>
    </form>
  );
}

export function DocActions({ slug, id, rules }: { slug: string; id: string; rules: { to: string; label: string; needsNote: boolean }[] }) {
  if (rules.length === 0) return null;
  const forward = rules.filter((r) => !["CANCELLED", "VOID", "REJECTED"].includes(r.to));
  const negative = rules.filter((r) => ["CANCELLED", "VOID", "REJECTED"].includes(r.to));
  return (
    <div className="grid gap-6 md:grid-cols-2">
      <div className="space-y-4">{forward.map((r) => <Btn key={r.to} slug={slug} id={id} to={r.to} label={r.label} needsNote={r.needsNote} />)}</div>
      <div className="space-y-4">{negative.map((r) => <Btn key={r.to} slug={slug} id={id} to={r.to} label={r.label} needsNote={r.needsNote} />)}</div>
    </div>
  );
}

export function PrintButton() {
  return (
    <button type="button" onClick={() => window.print()} className="no-print rounded-md border-2 border-line px-5 py-2.5 text-lg font-semibold hover:bg-background">
      Cetak
    </button>
  );
}

export function StatusBadgeDoc({ status, label, style }: { status: string; label: string; style: string }) {
  return <span data-status={status} className={`inline-block rounded px-2.5 py-1 text-base font-semibold ${style}`}>{label}</span>;
}

export function ClosePrButton({ prId }: { prId: string }) {
  const [state, action, pending] = useActionState<DocActionState, FormData>(closePr.bind(null, prId), {});
  return (
    <form action={action} className="space-y-2">
      <label htmlFor="close-note" className="block font-semibold">Catatan penutupan (boleh dikosongkan)</label>
      <textarea id="close-note" name="note" rows={2} className="w-full max-w-xl rounded-md border-2 border-line bg-white px-3 py-2.5 text-lg" />
      {state.error && <p role="alert" className="rounded-md bg-danger-bg px-3 py-2 text-danger">{state.error}</p>}
      <button type="submit" disabled={pending} className="rounded-md bg-brand px-5 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Memproses..." : "Tutup PR (selesai)"}</button>
    </form>
  );
}
