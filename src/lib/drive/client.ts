"use client";
// Unggah dari browser: server HMI Hub membuat sesi, isi file dikirim langsung ke Google Drive.

export async function postJson<T>(url: string, body: unknown): Promise<T> {
  const r = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const ct = r.headers.get("content-type") ?? "";
  if (!ct.includes("application/json")) throw new Error("Sesi berakhir. Muat ulang halaman dan masuk lagi.");
  const j = await r.json();
  if (!r.ok) throw new Error(j.error ?? "Gagal.");
  return j as T;
}

export function putFile(url: string, file: File, onPct: (n: number) => void): Promise<{ id: string }> {
  return new Promise((resolve, reject) => {
    const x = new XMLHttpRequest();
    x.open("PUT", url);
    x.upload.onprogress = (e) => { if (e.lengthComputable) onPct(Math.round((e.loaded / e.total) * 100)); };
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

// Membuka sesi, mengunggah, mengembalikan { fileId, folderLink? }.
export async function uploadOne(file: File, body: Record<string, unknown>, onPct: (n: number) => void) {
  const s = await postJson<{ uploadUrl: string; folderLink?: string }>("/api/drive/session", { name: file.name, mime: file.type, size: file.size, ...body });
  const up = await putFile(s.uploadUrl, file, onPct);
  return { fileId: up.id, folderLink: s.folderLink };
}
