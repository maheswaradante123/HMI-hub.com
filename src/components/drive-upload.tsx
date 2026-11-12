"use client";

import { useRef, useState } from "react";

type Area = "CPJ" | "CRJ" | "PMT" | "PR" | "DO" | "LAIN";

// Tombol unggah file ke Google Drive perusahaan. Setelah selesai, tautan file dikirim lewat onDone
// (biasanya diisikan ke kolom Bukti/Tautan di sebelahnya). Isi file tidak melewati server HMI Hub dan tidak disimpan di Supabase.
export function DriveUpload({ area, onDone, label = "Unggah", compact = false }: {
  area: Area; onDone: (link: string, fileName: string) => void; label?: string; compact?: boolean;
}) {
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [pct, setPct] = useState(0);
  const [err, setErr] = useState("");

  async function post<T>(url: string, body: unknown): Promise<T> {
    const r = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    const ct = r.headers.get("content-type") ?? "";
    if (!ct.includes("application/json")) throw new Error("Sesi berakhir. Muat ulang halaman dan masuk lagi.");
    const j = await r.json();
    if (!r.ok) throw new Error(j.error ?? "Gagal.");
    return j as T;
  }

  function put(url: string, file: File): Promise<{ id: string }> {
    return new Promise((resolve, reject) => {
      const x = new XMLHttpRequest();
      x.open("PUT", url);
      x.upload.onprogress = (e) => { if (e.lengthComputable) setPct(Math.round((e.loaded / e.total) * 100)); };
      x.onload = () => {
        try {
          const j = JSON.parse(x.responseText);
          if (x.status >= 200 && x.status < 300 && j.id) resolve(j); else reject(new Error("Google Drive menolak file."));
        } catch { reject(new Error("Balasan Google Drive tidak terbaca.")); }
      };
      x.onerror = () => reject(new Error("Koneksi terputus saat mengunggah. Coba lagi."));
      x.send(file);
    });
  }

  async function pick(file: File | undefined) {
    if (!file) return;
    setErr(""); setBusy(true); setPct(0);
    try {
      const { uploadUrl } = await post<{ uploadUrl: string }>("/api/drive/session", { name: file.name, mime: file.type, size: file.size, area });
      const up = await put(uploadUrl, file);
      const done = await post<{ link: string; name: string }>("/api/drive/finish", { fileId: up.id });
      onDone(done.link, done.name);
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
