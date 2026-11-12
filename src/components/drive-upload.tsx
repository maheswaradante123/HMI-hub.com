"use client";

import { useRef, useState } from "react";
import { postJson, uploadOne } from "@/lib/drive/client";

type Area = "CPJ" | "CRJ" | "PMT" | "PR" | "DO" | "LAIN";

// Tombol unggah satu file ke Google Drive perusahaan; tautan file diteruskan lewat onDone.
// Isi file dikirim langsung dari browser ke Google dan tidak disimpan di Supabase.
export function DriveUpload({ area, onDone, label = "Unggah", compact = false }: {
  area: Area; onDone: (link: string) => void; label?: string; compact?: boolean;
}) {
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [pct, setPct] = useState(0);
  const [err, setErr] = useState("");

  async function pick(file: File | undefined) {
    if (!file) return;
    setErr(""); setBusy(true); setPct(0);
    try {
      const up = await uploadOne(file, { area }, setPct);
      const done = await postJson<{ link: string }>("/api/drive/finish", { fileId: up.fileId });
      onDone(done.link);
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Unggah gagal.");
    } finally {
      setBusy(false);
      if (input.current) input.current.value = "";
    }
  }

  return (
    <span className="inline-flex flex-col items-start">
      <input ref={input} type="file" className="sr-only" tabIndex={-1} aria-hidden onChange={(e) => pick(e.target.files?.[0])}
        accept=".pdf,.jpg,.jpeg,.png,.webp,.heic,.heif,.gif,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.csv,.txt,.zip" />
      <button type="button" disabled={busy} onClick={() => input.current?.click()}
        className={`rounded-md border-2 border-line font-semibold hover:bg-background disabled:opacity-60 ${compact ? "px-2 py-1 text-sm" : "px-3 py-2 text-base"}`}
        title="Unggah file ke Google Drive dan isi tautannya otomatis">
        {busy ? `${pct}%` : label}
      </button>
      {err && <span role="alert" className="mt-1 max-w-56 text-sm text-danger">{err}</span>}
    </span>
  );
}
