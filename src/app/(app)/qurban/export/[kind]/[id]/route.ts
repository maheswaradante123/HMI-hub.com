import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { getBuyer, getOrder, listBills, type Qc } from "@/lib/qurban/data";
import { billDoc, invoiceDoc, proformaDoc, qcDoc, spDoc } from "@/lib/qurban/docs";
import { buatInvoiceXlsx } from "@/lib/export/invoice-xlsx.mjs";
import { buatQcXlsx } from "@/lib/export/qc-xlsx.mjs";
import { buatSpJb, buatSpPl } from "@/lib/export/sp-docx.mjs";

export const runtime = "nodejs";

const XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
const DOCX = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
const clean = (s: string) => s.replace(/[^A-Za-z0-9._-]+/g, "_");

function file(body: Uint8Array | ArrayBuffer, type: string, name: string) {
  return new NextResponse(body as BodyInit, {
    headers: {
      "Content-Type": type,
      "Content-Disposition": `attachment; filename="${clean(name)}"`,
      "Cache-Control": "private, no-store",
    },
  });
}
const notFound = (m: string) => NextResponse.json({ error: m }, { status: 404 });

export async function GET(_req: Request, { params }: { params: Promise<{ kind: string; id: string }> }) {
  const { kind, id } = await params;
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
    const wb = await buatInvoiceXlsx(doc);
    return file(await wb.xlsx.writeBuffer(), XLSX, `${doc.nomor}.xlsx`);
  }
  if (kind === "bill") {
    const supabase = await createClient();
    const { data: b } = await supabase.from("qurban_bills").select("order_id").eq("id", id).maybeSingle();
    if (!b) return notFound("Tagihan tidak ditemukan.");
    const o = await getOrder(b.order_id as string);
    const bill = (await listBills(b.order_id as string)).find((x) => x.id === id);
    if (!o || !bill) return notFound("Tagihan tidak ditemukan.");
    const doc = billDoc(o, bill);
    const wb = await buatInvoiceXlsx(doc);
    return file(await wb.xlsx.writeBuffer(), XLSX, `${doc.nomor}.xlsx`);
  }
  if (kind === "qc") {
    const supabase = await createClient();
    const { data: q } = await supabase.from("qurban_qc_reports").select("*").eq("id", id).maybeSingle();
    if (!q) return notFound("QC Report tidak ditemukan.");
    const doc = await qcDoc(q as Qc);
    if (doc.sapi.length === 0) return NextResponse.json({ error: "Belum ada sapi untuk bulan ini." }, { status: 409 });
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
