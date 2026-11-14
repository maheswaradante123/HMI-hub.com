"use client";

import Link from "next/link";
import { useActionState, useEffect, useState } from "react";
import { CpjDocs, folderIdOf } from "@/components/cpj-docs";
import { PettyDetails } from "@/components/petty-details";
import { saveJcpDocs, type DocFormState } from "@/app/(app)/d/actions";
import { fmtDate, fmtRupiah } from "@/lib/docs/format";
import { JCP_FLAG_BG, JCP_FLAGS, isPettyLine, parseDetails, planAmount, realAmount, type JcpDetail } from "@/lib/docs/jcp";
import type { FolderFile } from "@/lib/drive/types";

type Line = {
  line_no: number; trans_date: string; ac: string; code: string; description: string; price: number; qty: number; flag: string;
  real_price: number | null; real_qty: number | null; proof: string; details: unknown;
};
type State = { proof: string; details: JcpDetail[] };
const inp = "w-full rounded-md border-2 border-line bg-white px-2 py-2 text-base";

export function JcpDocsForm({ id, number, journalDate, status, lines, cancelHref }: {
  id: string; number: string; journalDate: string; status: string; lines: Line[]; cancelHref: string;
}) {
  const [state, action, pending] = useActionState<DocFormState, FormData>(saveJcpDocs.bind(null, id), {});
  const [rows, setRows] = useState<State[]>(() => lines.map((l) => ({ proof: l.proof, details: parseDetails(l.details) })));
  const [overview, setOverview] = useState<Record<string, FolderFile[]>>({});
  const [tick, setTick] = useState(0);
  const loadOverview = () => setTick((n) => n + 1);
  useEffect(() => {
    let off = false;
    fetch(`/api/drive/cpj?number=${encodeURIComponent(number)}&date=${encodeURIComponent(journalDate)}`)
      .then((r) => (r.ok ? r.json() : null))
      .then((j) => { if (!off && j) setOverview(j.folders ?? {}); })
      .catch(() => { /* kelengkapan tidak tampil bila Drive belum diatur atau offline */ });
    return () => { off = true; };
  }, [number, journalDate, tick]);
  const set = (i: number, patch: Partial<State>) => setRows((r) => r.map((x, j) => (j === i ? { ...x, ...patch } : x)));
  const flagLabel = Object.fromEntries(JCP_FLAGS.map((f) => [f.value, f.label]));
  const done = status === "REALIZED";
  const payload = JSON.stringify({ lines: lines.map((l, i) => ({ line_no: l.line_no, proof: rows[i].proof, details: isPettyLine(l.description) ? JSON.stringify(rows[i].details) : "" })) });

  return (
    <form action={action} noValidate>
      <input type="hidden" name="payload" value={payload} />
      <ul className="space-y-4">
        {lines.map((l, i) => {
          const num = { price: l.price, qty: l.qty, flag: l.flag, real_price: l.real_price, real_qty: l.real_qty };
          const ra = realAmount(num, done);
          const petty = isPettyLine(l.description) && l.flag !== "REJECTED" && l.flag !== "INCOMING";
          return (
            <li key={l.line_no} className={`rounded-xl border border-line p-4 ${JCP_FLAG_BG[l.flag] || "bg-surface"}`} title={flagLabel[l.flag]}>
              <div className="flex flex-wrap items-baseline gap-x-6 gap-y-1">
                <span className="text-muted">{l.line_no}</span>
                <b className="text-lg">{l.description}</b>
                <span className="text-muted">{l.trans_date ? fmtDate(l.trans_date) : "-"} · {l.ac} {l.code}</span>
                <span className="tabular-nums">Rencana {fmtRupiah(planAmount(num))}</span>
                <span className="tabular-nums">Realisasi {ra === null ? "-" : fmtRupiah(ra)}</span>
                {flagLabel[l.flag] && l.flag !== "NONE" && <span className="text-sm text-muted">{flagLabel[l.flag]}</span>}
              </div>
              <div className="mt-3 grid items-start gap-2 md:grid-cols-[minmax(0,1fr)_auto]">
                <div>
                  <label className="mb-1 block text-sm font-semibold uppercase tracking-wide text-muted" htmlFor={`pf-${l.line_no}`}>Bukti (folder Drive){petty ? " — untuk Petty Cash, dokumen ada di tiap rincian" : ""}</label>
                  <div className="flex items-start gap-1">
                    <input id={`pf-${l.line_no}`} className={inp} value={rows[i].proof} onChange={(e) => set(i, { proof: e.target.value })} />
                    {/^https?:\/\//.test(rows[i].proof) && <a href={rows[i].proof} target="_blank" rel="noreferrer" aria-label={`Buka folder bukti ${l.line_no}`} title="Buka folder bukti" className="px-1 pt-2 text-brand">↗</a>}
                  </div>
                </div>
                {!petty && (
                  <div className="pt-6">
                    <CpjDocs number={number} date={journalDate} item={l.description} proof={rows[i].proof} files={overview[folderIdOf(rows[i].proof)] ?? []}
                      blocked={!l.description.trim() ? "Deskripsi kosong." : undefined} onProof={(link) => set(i, { proof: link })} onChanged={loadOverview} />
                  </div>
                )}
              </div>
              {petty && (
                <div className="mt-4">
                  <PettyDetails no={l.line_no} description={l.description} defaultDate={l.trans_date} target={realAmount(num, true) ?? 0} list={rows[i].details}
                    onChange={(list) => set(i, { details: list })} number={number} jd={journalDate} overview={overview} onChanged={loadOverview} hardRule={!done} />
                </div>
              )}
            </li>
          );
        })}
      </ul>
      {state.error && <p role="alert" className="mt-4 rounded-md bg-danger-bg px-4 py-3 text-lg text-danger">{state.error}</p>}
      <div className="mt-6 flex gap-3">
        <button type="submit" disabled={pending} className="rounded-md bg-brand px-8 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Menyimpan..." : "Simpan dokumen"}</button>
        <Link href={cancelHref} className="rounded-md border-2 border-line px-8 py-3 text-lg font-semibold hover:bg-background">Batal</Link>
      </div>
    </form>
  );
}
