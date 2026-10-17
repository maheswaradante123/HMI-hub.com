import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { getBuyer, getOrder, listBills, type Qc } from "@/lib/qurban/data";
import { billDoc, invoiceDoc, proformaDoc, qcDoc, spDoc } from "@/lib/qurban/docs";
import { buatInvoiceXlsx } from "@/lib/export/invoice-xlsx.mjs";
import { buatInvoicePdf } from "@/lib/export/invoice-pdf.mjs";
import { buatQcXlsx } from "@/lib/export/qc-xlsx.mjs";
import { buatQcPdf } from "@/lib/export/qc-pdf.mjs";
import { buatSpJb, buatSpPl } from "@/lib/export/sp-docx.mjs";

export const runtime = "nodejs";

const PDF = "application/pdf";
const XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
const DOCX = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
const clean = (s: string) => s.replace(/[^A-Za-z0-9._-]+/g, "_");

function file(body: Uint8Array | ArrayBuffer, type: string, name: string, inline = false) {
  return new NextResponse(body as BodyInit, {
    headers: {
      "Content-Type": type,
      "Content-Disposition": `${inline ? "inline" : "attachment"}; filename="${clean(name)}"`,
      "Cache-Control": "private, no-store",
    },
  });
}
const notFound = (m: string) => NextResponse.json({ error: m }, { status: 404 });

export async function GET(req: Request, { params }: { params: Promise<{ kind: string; id: string }> }) {
  const { kind, id } = await params;
  const q = new URL(req.url).searchParams;
  const pdf = q.get("format") === "pdf";
  const inline = q.get("inline") === "1";
  // Proforma/invoice/tagihan: Excel (bisa diubah) atau PDF (tampilan sama di semua perangkat).
  const out = async (doc: Parameters<typeof buatInvoicePdf>[0]) =>
    pdf ? file(await buatInvoicePdf(doc), PDF, `${doc.nomor}.pdf`, inline) : file(await (await buatInvoiceXlsx(doc)).xlsx.writeBuffer(), XLSX, `${doc.nomor}.xlsx`);
  const session = await getSession();
  if (!session) return NextResponse.json({ error: "Silakan masuk dulu." }, { status: 401 });
  const mod = kind === "qc" ? "qc_report" : "qurban";
  const allowed = session.can(mod, "view") && (session.can(mod, "export") || (kind === "qc" && session.can(mod, "create")));
  if (!allowed) {
    return NextResponse.json({ error: "Anda tidak memiliki izin mengunduh dokumen ini." }, { status: 403 });
  }

  if (kind === "proforma" || kind === "invoice") {
    const o = await getOrder(id);
    if (!o) return notFound("Pesanan tidak ditemukan.");
    if (kind === "invoice" && !o.inv_no) return NextResponse.json({ error: "Invoice belum diterbitkan." }, { status: 409 });
    const doc = kind === "proforma" ? await proformaDoc(o) : await invoiceDoc(o);
    return out(doc);
  }
  if (kind === "bill") {
    const supabase = await createClient();
    const { data: b } = await supabase.from("qurban_bills").select("order_id").eq("id", id).maybeSingle();
    if (!b) return notFound("Tagihan tidak ditemukan.");
    const o = await getOrder(b.order_id as string);
    const bill = (await listBills(b.order_id as string)).find((x) => x.id === id);
    if (!o || !bill) return notFound("Tagihan tidak ditemukan.");
    return out(billDoc(o, bill));
  }
  if (kind === "qc") {
    const supabase = await createClient();
    const { data: q } = await supabase.from("qurban_qc_reports").select("*").eq("id", id).maybeSingle();
    if (!q) return notFound("QC Report tidak ditemukan.");
    const doc = await qcDoc(q as Qc);
    if (doc.sapi.length === 0) return NextResponse.json({ error: "Belum ada sapi untuk bulan ini." }, { status: 409 });
    if (pdf) return file(await buatQcPdf(doc), PDF, `${doc.nomor}.pdf`, inline);
    const wb = await buatQcXlsx(doc);
    return file(await wb.xlsx.writeBuffer(), XLSX, `${doc.nomor}.xlsx`);
  }
  if (kind === "spjb" || kind === "sppl") {
    const o = await getOrder(id);
    const b = o ? await getBuyer(id) : null;
    if (!o || !b) return NextResponse.json({ error: "Data pembeli belum diisi. Isi dulu di halaman Surat Perjanjian." }, { status: 409 });
    const { jb, pl } = await spDoc(o, b);
    const buf = kind === "spjb" ? await buatSpJb(jb) : await buatSpPl(pl);
    return file(buf, DOCX, `${kind === "spjb" ? b.sp_jb_no : b.sp_pl_no}.docx`);
  }
  return notFound("Jenis dokumen tidak dikenal.");
}
