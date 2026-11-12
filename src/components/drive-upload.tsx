"use client";

import { useRef, useState } from "react";

const DOC_TYPES = ["PO", "Surat Jalan", "Invoice", "Bukti Penerimaan", "Bukti Transfer", "Lainnya"];
type Listed = { id: string; name: string; link: string; docType: string };
const folderId = (u: string) => /\/folders\/([A-Za-z0-9_-]+)/.exec(u)?.[1] ?? "";

type Area = "CPJ" | "CRJ" | "PMT" | "PR" | "DO" | "LAIN";
export type DriveFolder = { number: string; date: string; item: string };

// Tombol unggah ke Google Drive perusahaan. Isi file dikirim langsung dari browser ke Google dan tidak disimpan di Supabase.
// - Mode biasa: satu file, tautan file diteruskan lewat onDone.
// - Mode folder (CPJ): banyak file sekaligus ke folder per item; yang diteruskan adalah tautan folder.
export function DriveUpload({ area, onDone, label = "Unggah", compact = false, folder, blocked, link: current }: {
  area: Area; onDone: (link: string, info: string) => void; label?: string; compact?: boolean;
  folder?: DriveFolder; blocked?: string; link?: string;
}) {
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [pct, setPct] = useState(0);
  const [pos, setPos] = useState("");
  const [err, setErr] = useState("");
  const [ok, setOk] = useState("");
  const [docType, setDocType] = useState("");
  const [files, setFiles] = useState<Listed[] | null>(null);

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

  async function showFiles() {
    if (files) { setFiles(null); return; }
    setErr("");
    try {
      const r = await fetch(`/api/drive/files?folder=${folderId(current ?? "")}`);
      const j = await r.json();
      if (!r.ok) throw new Error(j.error ?? "Gagal memuat daftar berkas.");
      setFiles(j.files as Listed[]);
    } catch (e) { setErr(e instanceof Error ? e.message : "Gagal memuat daftar berkas."); }
  }

  async function pick(chosen: FileList | null) {
    const list = chosen ? Array.from(chosen) : [];
    if (!list.length) return;
    if (folder && !docType) { setErr("Pilih jenis berkas dulu."); if (input.current) input.current.value = ""; return; }
    setErr(""); setOk(""); setBusy(true);
    let done = 0, link = "";
    try {
      // Satu per satu agar pembuatan folder tidak berbenturan.
      for (let n = 0; n < list.length; n++) {
        const file = list[n];
        setPct(0); setPos(list.length > 1 ? `${n + 1}/${list.length} ` : "");
        const s = await post<{ uploadUrl: string; folderLink?: string }>("/api/drive/session", { name: file.name, mime: file.type, size: file.size, area, ...(folder ? { folder, docType } : {}) });
        const up = await put(s.uploadUrl, file);
        if (folder) link = s.folderLink ?? link;
        else { const f = await post<{ link: string; name: string }>("/api/drive/finish", { fileId: up.id }); link = f.link; }
        done++;
      }
    } catch (e) {
      setErr(`${done ? `${done} file berhasil, ` : ""}${e instanceof Error ? e.message : "Unggah gagal."}`);
    } finally {
      if (link) { onDone(link, `${done} file`); setOk(`${done} file terunggah sebagai ${docType || "berkas"}`); setFiles(null); }
      setBusy(false); setPos("");
      if (input.current) input.current.value = "";
    }
  }

  const off = Boolean(blocked);
  return (
    <span className="inline-flex flex-col items-start">
      {folder && (
        <select aria-label="Jenis berkas" value={docType} disabled={busy || off} onChange={(e) => { setDocType(e.target.value); setErr(""); }}
          className="mb-1 w-full rounded-md border-2 border-line bg-white px-1 py-1 text-sm">
          <option value="">Jenis berkas...</option>
          {DOC_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
        </select>
      )}
      <input ref={input} type="file" multiple={Boolean(folder)} className="sr-only" tabIndex={-1} aria-hidden onChange={(e) => pick(e.target.files)}
        accept=".pdf,.jpg,.jpeg,.png,.webp,.heic,.heif,.gif,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.csv,.txt,.zip" />
      <button type="button" disabled={busy || off} onClick={() => input.current?.click()}
        className={`rounded-md border-2 border-line font-semibold hover:bg-background disabled:opacity-60 ${compact ? "px-2 py-1 text-sm" : "px-3 py-2 text-base"}`}
        title={blocked ?? (folder ? "Unggah beberapa file ke folder item ini di Google Drive; tautan folder terisi otomatis" : "Unggah file ke Google Drive dan isi tautannya otomatis")}>
        {busy ? `${pos}${pct}%` : label}
      </button>
      {folder && /\/folders\//.test(current ?? "") && (
        <button type="button" onClick={showFiles} className="mt-1 text-sm text-brand underline">{files ? "Tutup daftar" : "Lihat berkas"}</button>
      )}
      {files && (
        <ul className="mt-1 w-56 space-y-0.5 text-sm">
          {files.length === 0 && <li className="text-muted">Belum ada berkas.</li>}
          {files.map((f) => (
            <li key={f.id}><span className="mr-1 rounded bg-background px-1 font-semibold">{f.docType || "?"}</span>
              <a href={f.link} target="_blank" rel="noreferrer" className="break-all text-brand underline">{f.docType && f.name.startsWith(`${f.docType} - `) ? f.name.slice(f.docType.length + 3) : f.name}</a></li>
          ))}
        </ul>
      )}
      {ok && !err && <span className="mt-1 text-sm text-muted">{ok}</span>}
      {err && <span role="alert" className="mt-1 max-w-56 text-sm text-danger">{err}</span>}
    </span>
  );
}
