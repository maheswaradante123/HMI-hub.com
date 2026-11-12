"use client";

import { useRef, useState } from "react";
import { uploadOne } from "@/lib/drive/client";
import { CPJ_REQUIRED, DOC_TYPES, type FolderFile } from "@/lib/drive/types";

const ACCEPT = ".pdf,.jpg,.jpeg,.png,.webp,.heic,.heif,.gif,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.csv,.txt,.zip";
export const folderIdOf = (u: string) => /\/folders\/([A-Za-z0-9_-]+)/.exec(u)?.[1] ?? "";
const stripType = (f: FolderFile) => (f.docType && f.name.startsWith(`${f.docType} - `) ? f.name.slice(f.docType.length + 3) : f.name);

export function completeness(files: FolderFile[]) {
  const have = new Set(files.map((f) => f.docType));
  return { done: CPJ_REQUIRED.filter((t) => have.has(t)).length, total: CPJ_REQUIRED.length };
}

// Kelengkapan dokumen satu item CPJ: PO, Surat Jalan, Invoice, Bukti Penerimaan, Bukti Transfer. Tiap jenis punya unggahan sendiri.
export function CpjDocs({ number, date, item, proof, files, blocked, onProof, onChanged }: {
  number: string; date: string; item: string; proof: string; files: FolderFile[]; blocked?: string;
  onProof: (link: string) => void; onChanged: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState("");
  const [pct, setPct] = useState(0);
  const [err, setErr] = useState("");
  const inputs = useRef<Record<string, HTMLInputElement | null>>({});
  const { done, total } = completeness(files);
  const legacy = proof.trim() !== "" && files.length === 0; // tautan lama yang bukan hasil unggah HMI Hub

  async function pick(type: string, list: FileList | null) {
    const chosen = list ? Array.from(list) : [];
    if (!chosen.length) return;
    if (legacy && !confirm("Kolom Bukti saat ini berisi tautan lama (di luar HMI Hub). Mengunggah akan menggantinya dengan folder baru di HMI Hub. Lanjutkan?")) {
      const el = inputs.current[type]; if (el) el.value = "";
      return;
    }
    setErr(""); setBusy(type);
    let ok = 0;
    try {
      for (const file of chosen) { // satu per satu agar pembuatan folder tidak berbenturan
        setPct(0);
        const r = await uploadOne(file, { area: "CPJ", docType: type, folder: { number, date, item } }, setPct);
        if (r.folderLink && r.folderLink !== proof) onProof(r.folderLink);
        ok++;
      }
    } catch (e) {
      setErr(`${ok ? `${ok} file berhasil, ` : ""}${e instanceof Error ? e.message : "Unggah gagal."}`);
    } finally {
      setBusy(""); onChanged();
      const el = inputs.current[type]; if (el) el.value = "";
    }
  }

  const badge = done === total ? "bg-green-100 text-green-800" : done === 0 ? "bg-danger-bg text-danger" : "bg-yellow-100 text-yellow-900";
  return (
    <>
      <button type="button" onClick={() => setOpen(true)} disabled={Boolean(blocked)} title={blocked ?? "Kelengkapan dokumen item ini"}
        className="mt-1 flex items-center gap-1 rounded-md border-2 border-line px-2 py-1 text-sm font-semibold hover:bg-background disabled:opacity-60">
        Dokumen <span className={`rounded px-1.5 ${badge}`}>{done}/{total}</span>
      </button>
      {open && (
        <div role="dialog" aria-modal="true" aria-label={`Kelengkapan dokumen ${item}`} className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={() => setOpen(false)}>
          <div className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-xl bg-white p-6 shadow-xl" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-start justify-between gap-4">
              <div>
                <h3 className="text-xl font-bold">Kelengkapan dokumen</h3>
                <p className="text-muted">{number} · {item}</p>
              </div>
              <span className={`rounded px-2 py-1 font-semibold ${badge}`}>{done}/{total} lengkap</span>
            </div>
            {legacy && <p className="mt-3 rounded-md bg-yellow-100 px-3 py-2 text-sm text-yellow-900">Kolom Bukti berisi tautan lama di luar HMI Hub, jadi berkasnya tidak terbaca di sini. Unggahan baru akan membuat folder baru dan menggantikan tautan itu.</p>}
            <ul className="mt-4 divide-y divide-line">
              {DOC_TYPES.map((t) => {
                const mine = files.filter((f) => f.docType === t);
                const required = (CPJ_REQUIRED as readonly string[]).includes(t);
                return (
                  <li key={t} className="flex items-start gap-3 py-3">
                    <span aria-hidden className={`mt-0.5 w-6 text-center text-xl ${mine.length ? "text-green-700" : "text-muted"}`}>{mine.length ? "✓" : "○"}</span>
                    <div className="min-w-0 flex-1">
                      <p className="font-semibold">{t}{!required && <span className="ml-2 text-sm font-normal text-muted">(opsional)</span>}</p>
                      {mine.length === 0
                        ? <p className="text-sm text-muted">{required ? "Belum ada." : "Tidak ada."}</p>
                        : <ul className="text-sm">{mine.map((f) => <li key={f.id}><a href={f.link} target="_blank" rel="noreferrer" className="break-all text-brand underline">{stripType(f)}</a></li>)}</ul>}
                    </div>
                    <div>
                      <input ref={(el) => { inputs.current[t] = el; }} type="file" multiple accept={ACCEPT} className="sr-only" tabIndex={-1} aria-hidden onChange={(e) => pick(t, e.target.files)} />
                      <button type="button" disabled={Boolean(busy)} onClick={() => inputs.current[t]?.click()}
                        className="rounded-md border-2 border-line px-3 py-1.5 text-sm font-semibold hover:bg-background disabled:opacity-60">
                        {busy === t ? `${pct}%` : mine.length ? "Tambah" : "Unggah"}
                      </button>
                    </div>
                  </li>
                );
              })}
            </ul>
            {err && <p role="alert" className="mt-3 text-danger">{err}</p>}
            <div className="mt-4 flex items-center justify-between gap-3">
              {/^https?:\/\//.test(proof) ? <a href={proof} target="_blank" rel="noreferrer" className="text-brand underline">Buka folder di Google Drive ↗</a> : <span />}
              <button type="button" onClick={() => setOpen(false)} className="rounded-md bg-brand px-5 py-2 font-semibold text-white hover:bg-brand-dark">Tutup</button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
