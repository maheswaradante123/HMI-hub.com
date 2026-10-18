import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { buatPrPdf } from "@/lib/export/pr-pdf.mjs";
import { buatPrXlsx } from "@/lib/export/pr-xlsx.mjs";

export const runtime = "nodejs";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

// Unduhan lembar Purchase Request (PDF, Excel). Yang tampil hanya barang yang boleh dilihat pengunduh.
export async function GET(req: Request, ctx: { params: Promise<{ id: string }> }) {
  try {
    return await handle(req, ctx);
  } catch (e) {
    console.error("export PR gagal", e);
    return NextResponse.json({ error: "Gagal membuat dokumen: " + (e instanceof Error ? e.message : String(e)) }, { status: 500 });
  }
}

async function handle(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID.test(id)) return NextResponse.json({ error: "Dokumen tidak dikenal." }, { status: 404 });
  const session = await getSession();
  if (!session) return NextResponse.json({ error: "Silakan masuk dulu." }, { status: 401 });
  if (!session.can("purchase_request", "view") || !session.can("purchase_request", "export")) {
    return NextResponse.json({ error: "Anda tidak memiliki izin mengunduh dokumen ini." }, { status: 403 });
  }
  const q = new URL(req.url).searchParams;
  const pdf = q.get("format") === "pdf";
  const inline = q.get("inline") === "1";
  const supabase = await createClient();
  const { data: sheet } = await supabase
    .from("purchase_requests")
    .select("doc_number, request_date, pr_items(line_no, item_date, ac, code, item_name, estimated_price, qty, unit, status, pay_method, proof, units(name))")
    .eq("id", id).is("deleted_at", null).maybeSingle();
  if (!sheet) return NextResponse.json({ error: "Lembar PR tidak ditemukan." }, { status: 404 });
  type It = { line_no: number; item_date: string; ac: string; code: string; item_name: string; estimated_price: number | null; qty: number; unit: string | null; status: string; pay_method: string; proof: string | null; units: { name: string } | null };
  const items = [...((sheet.pr_items as unknown as It[]) ?? [])].sort((a, b) => a.line_no - b.line_no);
  const data = {
    nomor: sheet.doc_number as string, tanggal: sheet.request_date as string,
    baris: items.map((i, n) => ({
      no: n + 1, ac: i.ac, kode: i.code, tanggal: i.item_date, desc: i.item_name, price: Number(i.estimated_price ?? 0), qty: Number(i.qty),
      unit: i.unit ?? i.units?.name ?? "", status: i.status, pembelian: i.pay_method, bukti: i.proof ?? "",
    })),
  };
  const safe = data.nomor.replace(/[^A-Za-z0-9._-]+/g, "_");
  if (pdf) {
    return new NextResponse((await buatPrPdf(data)) as BodyInit, {
      headers: { "Content-Type": "application/pdf", "Content-Disposition": `${inline ? "inline" : "attachment"}; filename="${safe}.pdf"`, "Cache-Control": "private, no-store" },
    });
  }
  const wb = await buatPrXlsx(data);
  return new NextResponse((await wb.xlsx.writeBuffer()) as BodyInit, {
    headers: { "Content-Type": XLSX, "Content-Disposition": `attachment; filename="${safe}.xlsx"`, "Cache-Control": "private, no-store" },
  });
}
