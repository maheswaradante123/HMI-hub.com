// Unggah file ke Google Drive milik perusahaan (bukan ke Supabase), memakai refresh token satu akun Google (scope drive.file).
// Browser mengirim isi file LANGSUNG ke Google lewat sesi unggah yang dibuat server, sehingga tidak kena batas ukuran
// permintaan Vercel (4,5 MB) dan server tidak ikut memikul trafik file. Berkas ini hanya boleh dipakai di sisi server.

export const ROOT_FOLDER = "HMI Hub Uploads";
export const AREAS = ["CPJ", "CRJ", "PMT", "PR", "DO", "LAIN"] as const;
export type Area = (typeof AREAS)[number];
export const MAX_BYTES = 200 * 1024 * 1024;
export const ALLOWED_MIME = new Set([
  "application/pdf", "image/jpeg", "image/png", "image/webp", "image/heic", "image/heif", "image/gif",
  "text/csv", "text/plain",
  "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/vnd.ms-excel", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "application/vnd.ms-powerpoint", "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  "application/zip",
]);

export type Env = Record<string, string | undefined>;
type Fetch = typeof fetch;

export function driveConfigured(env: Env = process.env): boolean {
  return Boolean(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET && env.GOOGLE_REFRESH_TOKEN);
}

export function isArea(v: unknown): v is Area {
  return typeof v === "string" && (AREAS as readonly string[]).includes(v);
}

export function safeFileName(name: string): string {
  const base = name.replace(/[\\/\u0000-\u001f]+/g, "_").replace(/\s+/g, " ").trim().slice(0, 150);
  return base || "file";
}

export function validateUpload(i: { name: unknown; mime: unknown; size: unknown }): { ok: true; name: string; mime: string; size: number } | { ok: false; error: string } {
  const name = typeof i.name === "string" ? safeFileName(i.name) : "";
  const mime = typeof i.mime === "string" ? i.mime.toLowerCase() : "";
  const size = Number(i.size);
  if (!name) return { ok: false, error: "Nama file kosong." };
  if (!Number.isFinite(size) || size <= 0) return { ok: false, error: "File kosong." };
  if (size > MAX_BYTES) return { ok: false, error: "Ukuran file maksimal 200 MB." };
  if (!ALLOWED_MIME.has(mime)) return { ok: false, error: "Jenis file tidak didukung. Gunakan PDF, foto (JPG/PNG/WEBP/HEIC), Word, Excel, PowerPoint, CSV, atau ZIP." };
  return { ok: true, name, mime, size };
}

// Folder tujuan: HMI Hub Uploads / <area> / <tahun-bulan>
export function folderPath(area: Area, now: Date = new Date()): string[] {
  const wib = new Date(now.getTime() + 7 * 3600_000);
  return [ROOT_FOLDER, area, `${wib.getUTCFullYear()}-${String(wib.getUTCMonth() + 1).padStart(2, "0")}`];
}

export const qEscape = (s: string) => s.replace(/\\/g, "\\\\").replace(/'/g, "\\'");

export class DriveError extends Error {
  status: number;
  constructor(message: string, status = 502) { super(message); this.status = status; }
}

let cached: { token: string; exp: number } | null = null;

export async function accessToken(env: Env = process.env, f: Fetch = fetch, now = Date.now()): Promise<string> {
  if (cached && cached.exp > now + 60_000) return cached.token;
  if (!driveConfigured(env)) throw new DriveError("Unggah ke Google Drive belum diatur di server.", 503);
  const r = await f("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env.GOOGLE_CLIENT_ID!, client_secret: env.GOOGLE_CLIENT_SECRET!, refresh_token: env.GOOGLE_REFRESH_TOKEN!, grant_type: "refresh_token",
    }),
  });
  const j = (await r.json().catch(() => ({}))) as { access_token?: string; expires_in?: number; error?: string };
  if (!r.ok || !j.access_token) {
    throw new DriveError(j.error === "invalid_grant" ? "Izin Google Drive sudah kedaluwarsa atau dicabut. Buat ulang token (lihat docs/GOOGLE-DRIVE.md)." : "Tidak dapat masuk ke Google Drive.", 502);
  }
  cached = { token: j.access_token, exp: now + (j.expires_in ?? 3600) * 1000 };
  return j.access_token;
}
export function resetTokenCache() { cached = null; }

async function api<T>(token: string, f: Fetch, url: string, init: RequestInit = {}): Promise<T> {
  const r = await f(url, { ...init, headers: { Authorization: `Bearer ${token}`, ...(init.headers ?? {}) } });
  const j = (await r.json().catch(() => ({}))) as { error?: { message?: string } } & T;
  if (!r.ok) throw new DriveError(`Google Drive: ${j.error?.message ?? r.status}`, 502);
  return j;
}

// Cari folder bernama tertentu di dalam induknya, buat bila belum ada.
export async function ensureFolder(token: string, name: string, parent: string | null, f: Fetch = fetch): Promise<string> {
  const q = `mimeType='application/vnd.google-apps.folder' and trashed=false and name='${qEscape(name)}' and ${parent ? `'${parent}' in parents` : "'root' in parents"}`;
  const found = await api<{ files?: { id: string }[] }>(token, f, `https://www.googleapis.com/drive/v3/files?${new URLSearchParams({ q, fields: "files(id)", pageSize: "1" })}`);
  if (found.files?.[0]) return found.files[0].id;
  const made = await api<{ id: string }>(token, f, "https://www.googleapis.com/drive/v3/files?fields=id", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name, mimeType: "application/vnd.google-apps.folder", parents: parent ? [parent] : undefined }),
  });
  return made.id;
}

export async function ensurePath(token: string, path: string[], f: Fetch = fetch): Promise<string> {
  let parent: string | null = null;
  for (const seg of path) parent = await ensureFolder(token, seg, parent, f);
  return parent!;
}

// Membuka sesi unggah resumable. Header Origin membuat Google mengizinkan PUT langsung dari browser (CORS).
export async function startUpload(token: string, o: { name: string; mime: string; size: number; folderId: string; origin: string; by: string }, f: Fetch = fetch): Promise<string> {
  const r = await f("https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`, "Content-Type": "application/json; charset=UTF-8",
      "X-Upload-Content-Type": o.mime, "X-Upload-Content-Length": String(o.size), Origin: o.origin,
    },
    body: JSON.stringify({ name: o.name, parents: [o.folderId], appProperties: { hmiHub: "1", by: o.by.slice(0, 100) } }),
  });
  const url = r.headers.get("location");
  if (!r.ok || !url) throw new DriveError("Google Drive menolak membuat sesi unggah.", 502);
  return url;
}

// Setelah browser selesai mengunggah: pastikan file memang dibuat lewat aplikasi ini, lalu buka akses "siapa pun yang punya tautan".
export async function finishUpload(token: string, fileId: string, f: Fetch = fetch): Promise<{ id: string; name: string; link: string }> {
  if (!/^[A-Za-z0-9_-]{10,}$/.test(fileId)) throw new DriveError("ID file tidak valid.", 400);
  const meta = await api<{ id: string; name: string; webViewLink?: string; appProperties?: Record<string, string> }>(
    token, f, `https://www.googleapis.com/drive/v3/files/${fileId}?fields=id,name,webViewLink,appProperties`);
  if (meta.appProperties?.hmiHub !== "1") throw new DriveError("File bukan hasil unggahan HMI Hub.", 403);
  await api(token, f, `https://www.googleapis.com/drive/v3/files/${fileId}/permissions`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ role: "reader", type: "anyone" }),
  });
  return { id: meta.id, name: meta.name, link: meta.webViewLink ?? `https://drive.google.com/file/d/${meta.id}/view` };
}
