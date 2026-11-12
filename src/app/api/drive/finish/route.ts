import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { DriveError, accessToken, finishUpload } from "@/lib/drive/core";

export const dynamic = "force-dynamic";

// Dipanggil browser setelah file selesai terunggah: membuka akses tautan dan mengembalikan tautannya.
export async function POST(req: Request) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: "Sesi berakhir. Masuk lagi lalu coba unggah ulang." }, { status: 401 });
  const body = (await req.json().catch(() => null)) as { fileId?: unknown } | null;
  try {
    const token = await accessToken();
    const r = await finishUpload(token, String(body?.fileId ?? ""));
    return NextResponse.json(r);
  } catch (e) {
    const err = e instanceof DriveError ? e : new DriveError("Gagal menyelesaikan unggahan.");
    return NextResponse.json({ error: err.message }, { status: err.status });
  }
}
