import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { driveDiagnose } from "@/lib/drive/core";

export const dynamic = "force-dynamic";

// Buka alamat ini di browser (sudah login) untuk menguji sambungan Google Drive. Tidak menampilkan nilai rahasia.
export async function GET() {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: "Masuk dulu." }, { status: 401 });
  return NextResponse.json(await driveDiagnose(), { headers: { "Cache-Control": "no-store" } });
}
