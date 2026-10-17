"use client";

import { useActionState } from "react";
import { changeStatus, setItemSupplier, type ActionState } from "@/app/(app)/purchase-request/actions";

const btn = "rounded-md px-5 py-3 text-lg font-semibold disabled:opacity-60";

function StatusButton({
  prId, to, label, className, withNote, noteLabel,
}: {
  prId: string; to: string; label: string; className: string; withNote?: boolean; noteLabel?: string;
}) {
  const [state, action, pending] = useActionState<ActionState, FormData>(changeStatus.bind(null, prId, to), {});
  return (
    <form action={action} className="space-y-2">
      {withNote && (
        <div>
          <label htmlFor={`note-${to}`} className="mb-1 block font-semibold">{noteLabel}</label>
          <textarea id={`note-${to}`} name="note" rows={2} className="w-full rounded-md border-2 border-line bg-white px-3 py-2.5 text-lg" />
        </div>
      )}
      {state.error && <p role="alert" className="rounded-md bg-danger-bg px-3 py-2 text-danger">{state.error}</p>}
      <button type="submit" disabled={pending} className={`${btn} ${className}`}>
        {pending ? "Memproses..." : label}
      </button>
    </form>
  );
}

export function PrActions({
  prId, status, canApprove, canProcess,
}: {
  prId: string; status: string; canApprove: boolean; canProcess: boolean;
}) {
  const primary = "bg-brand text-white hover:bg-brand-dark";
  const danger = "border-2 border-danger text-danger hover:bg-danger-bg";
  const neutral = "border-2 border-line hover:bg-background";
  return (
    <div className="space-y-4">
      {canApprove && (status === "SUBMITTED" || status === "UNDER_REVIEW") && (
        <div className="grid gap-5 md:grid-cols-2">
          <div className="space-y-3">
            {status === "SUBMITTED" && (
              <StatusButton prId={prId} to="UNDER_REVIEW" label="Mulai tinjau" className={neutral} />
            )}
            <StatusButton prId={prId} to="APPROVED" label="Setujui PR" className={primary} withNote noteLabel="Catatan (boleh dikosongkan)" />
          </div>
          <StatusButton prId={prId} to="REJECTED" label="Tolak PR" className={danger} withNote noteLabel="Alasan penolakan (wajib)" />
        </div>
      )}
      {canProcess && status === "APPROVED" && (
        <StatusButton prId={prId} to="ORDERED" label="Tandai sudah dipesan" className={primary} />
      )}
      {canProcess && status === "ORDERED" && (
        <StatusButton prId={prId} to="RECEIVED" label="Tandai barang sudah diterima" className={primary} />
      )}
    </div>
  );
}

export function SupplierPicker({
  prId, itemId, current, suppliers,
}: {
  prId: string; itemId: string; current: string | null; suppliers: { id: string; name: string }[];
}) {
  const [state, action, pending] = useActionState<ActionState, FormData>(setItemSupplier.bind(null, prId, itemId), {});
  return (
    <form action={action} className="flex flex-wrap items-center gap-2">
      <label htmlFor={`sup-${itemId}`} className="sr-only">Supplier</label>
      <select id={`sup-${itemId}`} name="supplier_id" defaultValue={current ?? ""} className="rounded-md border-2 border-line bg-white px-3 py-2 text-lg">
        <option value="">Pilih supplier...</option>
        {suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
      </select>
      <button type="submit" disabled={pending} className="rounded-md border-2 border-line px-4 py-2 font-semibold hover:bg-background disabled:opacity-60">
        {pending ? "..." : "Simpan"}
      </button>
      {state.error && <span role="alert" className="text-danger">{state.error}</span>}
    </form>
  );
}
