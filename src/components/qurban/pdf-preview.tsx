"use client";

import { useEffect, useRef, useState } from "react";

// Tombol "Pratinjau": membuka dokumen PDF asli (sama dengan yang diunduh) di jendela di atas halaman.
export function PdfPreview({ href, title, xlsx }: { href: string; title: string; xlsx?: string }) {
  const [open, setOpen] = useState(false);
  const closeRef = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    if (!open) return;
    closeRef.current?.focus();
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open]);
  const sep = href.includes("?") ? "&" : "?";
  return (
    <>
      <button type="button" onClick={() => setOpen(true)} className="rounded-full border border-line bg-surface px-4 py-1.5 font-semibold hover:bg-background">
        Pratinjau
      </button>
      {open && (
        <div className="fixed inset-0 z-50 grid place-items-center bg-black/60 p-3" role="dialog" aria-modal="true" aria-label={title} onClick={() => setOpen(false)}>
          <div className="flex h-[92vh] w-full max-w-4xl flex-col rounded-2xl bg-surface p-4 text-card-fg" onClick={(e) => e.stopPropagation()}>
            <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
              <h2 className="text-xl font-bold">{title}</h2>
              <div className="flex flex-wrap items-center gap-3">
                <a href={`${href}${sep}format=pdf`} className="rounded-full bg-brand px-4 py-1.5 font-semibold text-white">Unduh PDF</a>
                {xlsx && <a href={xlsx} className="rounded-full border border-line px-4 py-1.5 font-semibold">Unduh Excel</a>}
                <button ref={closeRef} type="button" onClick={() => setOpen(false)} className="rounded-full border border-line px-4 py-1.5 font-semibold">Tutup</button>
              </div>
            </div>
            <iframe title={title} src={`${href}${sep}format=pdf&inline=1`} className="min-h-0 w-full flex-1 rounded-lg border border-line bg-neutral-200" />
          </div>
        </div>
      )}
    </>
  );
}
