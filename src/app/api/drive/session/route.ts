import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { DriveError, accessToken, cpjFolderPath, ensurePath, folderLink, folderPath, isArea, shareFolder, startUpload, validateUpload } from "@/lib/drive/core";

export const dynamic = "force-dynamic";

// Membuat sesi unggah Google Drive untuk satu file. Isi file dikirim browser langsung ke Google.
export async function POST(req: Request) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: "Sesi berakhir. Masuk lagi lalu coba unggah ulang." }, { status: 401 });
  const body = (await req.json().catch(() => null)) as { name?: unknown; mime?: unknown; size?: unknown; area?: unknown; folder?: unknown } | null;
  const v = validateUpload({ name: body?.name, mime: body?.mime, size: body?.size });
  if (!v.ok) return NextResponse.json({ error: v.error }, { status: 400 });
  const area = isArea(body?.area) ? body!.area : "LAIN";
  // Mode folder CPJ: file masuk ke folder per item (CPJ/tahun/bulan/nomor/item) dan yang dikembalikan adalah tautan foldernya.
  let path = folderPath(area);
  if (body?.folder !== undefined) {
    const f = body.folder as { number?: unknown; date?: unknown; item?: unknown } | null;
    const p = area === "CPJ" && f ? cpjFolderPath(f) : null;
    if (!p) return NextResponse.json({ error: "Nomor CPJ, tanggal jurnal, atau nama item belum lengkap. Simpan dokumen dan isi Description dulu." }, { status: 400 });
    path = p;
  }
  const origin = req.headers.get("origin");
  if (!origin) return NextResponse.json({ error: "Asal permintaan tidak diketahui." }, { status: 400 });
  try {
    const token = await accessToken();
    const folderId = await ensurePath(token, path);
    if (body?.folder !== undefined) await shareFolder(token, folderId);
    const uploadUrl = await startUpload(token, { name: v.name, mime: v.mime, size: v.size, folderId, origin, by: session.fullName });
    return NextResponse.json({ uploadUrl, folderLink: body?.folder !== undefined ? folderLink(folderId) : undefined });
  } catch (e) {
    const err = e instanceof DriveError ? e : new DriveError("Unggah gagal dimulai.");
    return NextResponse.json({ error: err.message }, { status: err.status });
  }
}
