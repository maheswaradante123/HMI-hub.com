import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { DriveError, accessToken, cpjOverview } from "@/lib/drive/core";

export const dynamic = "force-dynamic";

// Kelengkapan bukti satu CPJ: berkas per folder item (nama, jenis, tautan).
export async function GET(req: Request) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: "Sesi berakhir. Masuk lagi." }, { status: 401 });
  const sp = new URL(req.url).searchParams;
  try {
    return NextResponse.json({ folders: await cpjOverview(await accessToken(), { number: sp.get("number"), date: sp.get("date") }) });
  } catch (e) {
    const err = e instanceof DriveError ? e : new DriveError("Kelengkapan bukti gagal dimuat.");
    return NextResponse.json({ error: err.message }, { status: err.status });
  }
}
