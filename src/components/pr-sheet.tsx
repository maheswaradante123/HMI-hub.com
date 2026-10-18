"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { Fragment, useState, useTransition, type ReactNode } from "react";
import { movePrItems, updatePrItem } from "@/app/(app)/purchase-request/actions";
import { LINE_LABEL, LINE_STYLE, MOVE_FROM, MOVE_LABEL, PR_AC, PR_CODES, PR_PAY, isDead, type LineStatus } from "@/lib/pr/lines";

export type SheetItem = {
  id: string; ac: string; code: string; desc: string; price: number; qty: number; unit: string; status: string;
  requester: string; requesterId: string; pay: string; proof: string; cpj: string; date: string;
};
export type SheetFlags = { canEdit: boolean; canApprove: boolean; canDelete: boolean; canCreateJournal: boolean; userId: string; legacy: boolean };

const rp = (n: number) => "Rp " + Math.round(n).toLocaleString("id-ID");
const qtyFmt = (n: number) => n.toLocaleString("id-ID", { maximumFractionDigits: 3 });
const inp = "w-full rounded-md border-2 border-line bg-white px-2 py-1.5 text-base";
const MOVES = ["SUBMITTED", "APPROVED", "REJECTED", "ORDERED", "RECEIVED", "CANCELLED"] as const;

export function PrSheet({ sheetId, items, flags }: { sheetId: string; items: SheetItem[]; flags: SheetFlags }) {
  const router = useRouter();
  const [sel, setSel] = useState<Set<string>>(new Set());
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [rejecting, setRejecting] = useState(false);
  const [note, setNote] = useState("");
  const [editing, setEditing] = useState<string | null>(null);
  const [draft, setDraft] = useState<Record<string, string>>({});
  const [pending, start] = useTransition();

  const chosen = items.filter((i) => sel.has(i.id));
  const total = items.reduce((s, i) => s + (isDead(i.status) ? 0 : i.price * i.qty), 0);
  const allowed = (to: string) => {
    if (flags.legacy) return false;
    const from = MOVE_FROM[to] ?? [];
    const rows = chosen.filter((i) => from.includes(i.status as LineStatus));
    if (rows.length === 0) return false;
    if (to === "SUBMITTED" || to === "ORDERED" || to === "RECEIVED") return flags.canEdit;
    if (to === "APPROVED" || to === "REJECTED") return flags.canApprove;
    return rows.some((i) => flags.canDelete || (i.status === "DRAFT" && i.requesterId === flags.userId));
  };
  const journalable = chosen.filter((i) => ["APPROVED", "ORDERED", "RECEIVED"].includes(i.status) && !i.cpj);

  const run = (to: string, withNote = "") => start(async () => {
    setMsg(null);
    const res = await movePrItems(sheetId, chosen.map((i) => i.id), to, withNote);
    if (res.error) { setMsg({ ok: false, text: res.error }); return; }
    setMsg({ ok: true, text: res.message ?? "Selesai." });
    setSel(new Set()); setRejecting(false); setNote("");
    router.refresh();
  });

  const startEdit = (i: SheetItem) => {
    setEditing(i.id); setMsg(null);
    setDraft({ ac: i.ac, code: i.code, item_name: i.desc, price: String(i.price).replace(".", ","), qty: String(i.qty).replace(".", ","), unit: i.unit, pay_method: i.pay, proof: i.proof });
  };
  const canEditMain = (i: SheetItem) => !flags.legacy && i.status === "DRAFT" && (flags.canEdit || i.requesterId === flags.userId);
  const canEditProcess = (i: SheetItem) => !flags.legacy && !isDead(i.status) && (flags.canEdit || (i.status === "DRAFT" && i.requesterId === flags.userId));
  const saveEdit = (i: SheetItem) => start(async () => {
    const fields: Record<string, string> = {};
    if (canEditMain(i)) Object.assign(fields, { ac: draft.ac, code: draft.code, item_name: draft.item_name, price: draft.price, qty: draft.qty, unit: draft.unit });
    if (canEditProcess(i)) Object.assign(fields, { pay_method: draft.pay_method, proof: draft.proof });
    const res = await updatePrItem(sheetId, i.id, fields);
    if (res.error) { setMsg({ ok: false, text: res.error }); return; }
    setMsg({ ok: true, text: "Perubahan tersimpan." }); setEditing(null); router.refresh();
  });

  return (
    <div>
      {flags.legacy && <p className="mb-3 rounded-md bg-warn-bg px-4 py-3">Lembar ini dibuat dengan alur lama (satu status untuk seluruh PR), jadi barangnya tidak bisa diproses per barang.</p>}
      <div className="mb-3 flex flex-wrap items-center gap-3" aria-live="polite">
        <span className="text-muted">{chosen.length} dicentang</span>
        {MOVES.filter((to) => allowed(to) && to !== "REJECTED").map((to) => (
          <button key={to} type="button" disabled={pending} onClick={() => run(to)}
            className={`rounded-md px-4 py-2 font-semibold disabled:opacity-60 ${to === "CANCELLED" ? "border-2 border-danger text-danger hover:bg-danger-bg" : to === "SUBMITTED" || to === "APPROVED" ? "bg-brand text-white hover:bg-brand-dark" : "border-2 border-line hover:bg-background"}`}>
            {MOVE_LABEL[to]}
          </button>
        ))}
        {allowed("REJECTED") && !rejecting && <button type="button" onClick={() => setRejecting(true)} className="rounded-md border-2 border-danger px-4 py-2 font-semibold text-danger hover:bg-danger-bg">Tolak</button>}
        {flags.canCreateJournal && journalable.length > 0 && (
          <Link href={`/d/jcp/baru?pr=${journalable.map((i) => i.id).join(",")}`} className="rounded-md border-2 border-brand px-4 py-2 font-semibold text-brand hover:bg-background">Buat CPJ dari yang dicentang ({journalable.length})</Link>
        )}
      </div>
      {rejecting && (
        <div className="mb-3 flex flex-wrap items-end gap-3 rounded-lg border border-line bg-background p-3">
          <div className="min-w-[260px] flex-1">
            <label htmlFor="rej-note" className="mb-1 block font-semibold">Alasan penolakan <span className="text-danger">*</span></label>
            <input id="rej-note" value={note} onChange={(e) => setNote(e.target.value)} className={inp} />
          </div>
          <button type="button" disabled={pending || !note.trim()} onClick={() => run("REJECTED", note)} className="rounded-md bg-danger px-4 py-2 font-semibold text-white disabled:opacity-60">Tolak barang</button>
          <button type="button" onClick={() => setRejecting(false)} className="rounded-md border-2 border-line px-4 py-2 font-semibold hover:bg-background">Batal</button>
        </div>
      )}
      {msg && <p role={msg.ok ? "status" : "alert"} className={`mb-3 rounded-md px-4 py-3 ${msg.ok ? "bg-green-100 text-green-900" : "bg-danger-bg text-danger"}`}>{msg.text}</p>}

      <datalist id="pr-codes">{PR_CODES.map((c) => <option key={c} value={c} />)}</datalist>
      <datalist id="pr-pay">{PR_PAY.map((c) => <option key={c} value={c} />)}</datalist>
      <div className="overflow-x-auto rounded-lg border border-line bg-surface">
        <table className="w-full min-w-[1100px] text-left">
          <thead className="border-b border-line bg-background">
            <tr>
              <th scope="col" className="w-10 px-3 py-3"><span className="sr-only">Pilih</span></th>
              {["A/C", "No", "Kode", "Description", "Price", "Qty", "Unit", "Amount", "Status", "Peminta", "Pembelian", "CPJ", ""].map((h, k) => (
                <th key={k} scope="col" className={`px-3 py-3 text-sm font-semibold uppercase tracking-wide text-muted ${["Price", "Qty", "Amount"].includes(h) ? "text-right" : ""}`}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {items.map((i, n) => {
              const dim = isDead(i.status) ? "opacity-60" : "";
              const closed = i.status === "CLOSED" || i.status === "CANCELLED";
              const editable = canEditMain(i) || canEditProcess(i);
              return (
                <FragmentRow key={i.id}>
                  <tr className={`border-b border-line align-top ${dim}`}>
                    <td className="px-3 py-3"><input type="checkbox" className="h-5 w-5" checked={sel.has(i.id)} disabled={closed || flags.legacy} aria-label={`Pilih barang ${n + 1}`}
                      onChange={(e) => setSel((s) => { const x = new Set(s); if (e.target.checked) x.add(i.id); else x.delete(i.id); return x; })} /></td>
                    <td className="px-3 py-3 font-semibold italic">{i.ac}</td>
                    <td className="px-3 py-3">{n + 1}</td>
                    <td className="px-3 py-3 font-semibold">{i.code}</td>
                    <td className="px-3 py-3">{i.desc}</td>
                    <td className="px-3 py-3 text-right tabular-nums whitespace-nowrap">{rp(i.price)}</td>
                    <td className="px-3 py-3 text-right tabular-nums">{qtyFmt(i.qty)}</td>
                    <td className="px-3 py-3">{i.unit}</td>
                    <td className="px-3 py-3 text-right tabular-nums whitespace-nowrap">{rp(i.price * i.qty)}</td>
                    <td className="px-3 py-3"><span className={`inline-block whitespace-nowrap rounded-full px-3 py-0.5 text-sm font-semibold ${LINE_STYLE[i.status as LineStatus] ?? ""}`}>{LINE_LABEL[i.status as LineStatus] ?? i.status}</span></td>
                    <td className="px-3 py-3">{i.requester}</td>
                    <td className="px-3 py-3">{i.pay}{i.proof && <span className="mt-1 block text-sm text-muted">Bukti: {i.proof}</span>}</td>
                    <td className="px-3 py-3">{i.cpj ? <Link href="/d/jcp" className="text-brand underline">{i.cpj}</Link> : <span className="text-muted">-</span>}</td>
                    <td className="px-3 py-3">{editable && <button type="button" onClick={() => (editing === i.id ? setEditing(null) : startEdit(i))} className="rounded-md border-2 border-line px-3 py-1 font-semibold hover:bg-background">Ubah</button>}</td>
                  </tr>
                  {editing === i.id && (
                    <tr className="border-b border-line bg-background">
                      <td />
                      <td colSpan={13} className="px-3 py-4">
                        <div className="grid gap-3 md:grid-cols-6">
                          {canEditMain(i) && (<>
                            <div><label className="mb-1 block text-sm font-semibold">A/C</label><select className={inp} value={draft.ac} onChange={(e) => setDraft({ ...draft, ac: e.target.value })}>{PR_AC.map((a) => <option key={a.value} value={a.value}>{a.value}</option>)}</select></div>
                            <div><label className="mb-1 block text-sm font-semibold">Kode</label><input className={inp} list="pr-codes" value={draft.code} onChange={(e) => setDraft({ ...draft, code: e.target.value.toUpperCase() })} /></div>
                            <div className="md:col-span-4"><label className="mb-1 block text-sm font-semibold">Description</label><input className={inp} value={draft.item_name} onChange={(e) => setDraft({ ...draft, item_name: e.target.value })} /></div>
                            <div><label className="mb-1 block text-sm font-semibold">Harga</label><input className={inp} inputMode="decimal" value={draft.price} onChange={(e) => setDraft({ ...draft, price: e.target.value })} /></div>
                            <div><label className="mb-1 block text-sm font-semibold">Qty</label><input className={inp} inputMode="decimal" value={draft.qty} onChange={(e) => setDraft({ ...draft, qty: e.target.value })} /></div>
                            <div><label className="mb-1 block text-sm font-semibold">Satuan</label><input className={inp} value={draft.unit} onChange={(e) => setDraft({ ...draft, unit: e.target.value })} /></div>
                          </>)}
                          {canEditProcess(i) && (<>
                            <div className="md:col-span-2"><label className="mb-1 block text-sm font-semibold">Pembelian</label><input className={inp} list="pr-pay" value={draft.pay_method} onChange={(e) => setDraft({ ...draft, pay_method: e.target.value })} /></div>
                            <div className="md:col-span-3"><label className="mb-1 block text-sm font-semibold">Attachment of Proof (nama file bukti)</label><input className={inp} value={draft.proof} onChange={(e) => setDraft({ ...draft, proof: e.target.value })} /></div>
                          </>)}
                        </div>
                        <div className="mt-3 flex gap-3">
                          <button type="button" disabled={pending} onClick={() => saveEdit(i)} className="rounded-md bg-brand px-5 py-2 font-semibold text-white disabled:opacity-60">Simpan</button>
                          <button type="button" onClick={() => setEditing(null)} className="rounded-md border-2 border-line px-5 py-2 font-semibold hover:bg-background">Batal</button>
                        </div>
                      </td>
                    </tr>
                  )}
                </FragmentRow>
              );
            })}
          </tbody>
          <tfoot>
            <tr><td colSpan={8} className="px-3 py-3 text-right font-semibold">Total (tanpa Cancel / Ditolak)</td><td className="px-3 py-3 text-right text-lg font-bold tabular-nums whitespace-nowrap">{rp(total)}</td><td colSpan={5} /></tr>
          </tfoot>
        </table>
      </div>
    </div>
  );
}

// Pembungkus agar dua <tr> (baris dan baris ubah) boleh berada dalam satu elemen berkunci.
function FragmentRow({ children }: { children: ReactNode }) { return <Fragment>{children}</Fragment>; }
