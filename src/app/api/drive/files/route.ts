import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { DriveError, accessToken, listFolder } from "@/lib/drive/core";

export const dynamic = "force-dynamic";

// Daftar berkas di satu folder bukti (nama, jenis, tautan).
export async function GET(req: Request) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: "Sesi berakhir. Masuk lagi." }, { status: 401 });
  const folder = new URL(req.url).searchParams.get("folder") ?? "";
  try {
    return NextResponse.json({ files: await listFolder(await accessToken(), folder) });
  } catch (e) {
    const err = e instanceof DriveError ? e : new DriveError("Daftar berkas gagal dimuat.");
    return NextResponse.json({ error: err.message }, { status: err.status });
  }
}
