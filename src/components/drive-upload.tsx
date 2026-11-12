"use client";

import { useRef, useState } from "react";

type Area = "CPJ" | "CRJ" | "PMT" | "PR" | "DO" | "LAIN";
export type DriveFolder = { number: string; date: string; item: string };

// Tombol unggah ke Google Drive perusahaan. Isi file dikirim langsung dari browser ke Google dan tidak disimpan di Supabase.
// - Mode biasa: satu file, tautan file diteruskan lewat onDone.
// - Mode folder (CPJ): banyak file sekaligus ke folder per item; yang diteruskan adalah tautan folder.
export function DriveUpload({ area, onDone, label = "Unggah", compact = false, folder, blocked }: {
  area: Area; onDone: (link: string, info: string) => void; label?: string; compact?: boolean;
  folder?: DriveFolder; blocked?: string;
}) {
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [pct, setPct] = useState(0);
  const [pos, setPos] = useState("");
  const [err, setErr] = useState("");
  const [ok, setOk] = useState("");

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

  async function pick(files: FileList | null) {
    const list = files ? Array.from(files) : [];
    if (!list.length) return;
    setErr(""); setOk(""); setBusy(true);
    let done = 0, link = "";
    try {
      // Satu per satu agar pembuatan folder tidak berbenturan.
      for (let n = 0; n < list.length; n++) {
        const file = list[n];
        setPct(0); setPos(list.length > 1 ? `${n + 1}/${list.length} ` : "");
        const s = await post<{ uploadUrl: string; folderLink?: string }>("/api/drive/session", { name: file.name, mime: file.type, size: file.size, area, ...(folder ? { folder } : {}) });
        const up = await put(s.uploadUrl, file);
        if (folder) link = s.folderLink ?? link;
        else { const f = await post<{ link: string; name: string }>("/api/drive/finish", { fileId: up.id }); link = f.link; }
        done++;
      }
    } catch (e) {
      setErr(`${done ? `${done} file berhasil, ` : ""}${e instanceof Error ? e.message : "Unggah gagal."}`);
    } finally {
      if (link) { onDone(link, `${done} file`); setOk(`${done} file terunggah`); }
      setBusy(false); setPos("");
      if (input.current) input.current.value = "";
    }
  }

  const off = Boolean(blocked);
  return (
    <span className="inline-flex flex-col items-start">
      <input ref={input} type="file" multiple={Boolean(folder)} className="sr-only" tabIndex={-1} aria-hidden onChange={(e) => pick(e.target.files)}
        accept=".pdf,.jpg,.jpeg,.png,.webp,.heic,.heif,.gif,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.csv,.txt,.zip" />
      <button type="button" disabled={busy || off} onClick={() => input.current?.click()}
        className={`rounded-md border-2 border-line font-semibold hover:bg-background disabled:opacity-60 ${compact ? "px-2 py-1 text-sm" : "px-3 py-2 text-base"}`}
        title={blocked ?? (folder ? "Unggah beberapa file ke folder item ini di Google Drive; tautan folder terisi otomatis" : "Unggah file ke Google Drive dan isi tautannya otomatis")}>
        {busy ? `${pos}${pct}%` : label}
      </button>
      {ok && !err && <span className="mt-1 text-sm text-muted">{ok}</span>}
      {err && <span role="alert" className="mt-1 max-w-56 text-sm text-danger">{err}</span>}
    </span>
  );
}
