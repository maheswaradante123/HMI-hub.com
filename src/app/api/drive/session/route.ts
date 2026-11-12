import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { DriveError, accessToken, ensurePath, folderPath, isArea, startUpload, validateUpload } from "@/lib/drive/core";

export const dynamic = "force-dynamic";

// Membuat sesi unggah Google Drive untuk satu file. Isi file dikirim browser langsung ke Google.
export async function POST(req: Request) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: "Sesi berakhir. Masuk lagi lalu coba unggah ulang." }, { status: 401 });
  const body = (await req.json().catch(() => null)) as { name?: unknown; mime?: unknown; size?: unknown; area?: unknown } | null;
  const v = validateUpload({ name: body?.name, mime: body?.mime, size: body?.size });
  if (!v.ok) return NextResponse.json({ error: v.error }, { status: 400 });
  const area = isArea(body?.area) ? body!.area : "LAIN";
  const origin = req.headers.get("origin");
  if (!origin) return NextResponse.json({ error: "Asal permintaan tidak diketahui." }, { status: 400 });
  try {
    const token = await accessToken();
    const folderId = await ensurePath(token, folderPath(area));
    const uploadUrl = await startUpload(token, { name: v.name, mime: v.mime, size: v.size, folderId, origin, by: session.fullName });
    return NextResponse.json({ uploadUrl });
  } catch (e) {
    const err = e instanceof DriveError ? e : new DriveError("Unggah gagal dimulai.");
    return NextResponse.json({ error: err.message }, { status: err.status });
  }
}
