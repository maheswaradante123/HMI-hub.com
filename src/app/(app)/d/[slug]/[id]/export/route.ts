import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { buatInvoiceXlsx } from "@/lib/export/invoice-xlsx.mjs";
import { buatInvoiceTokoPdf } from "@/lib/export/invoice-toko-pdf.mjs";
import { buatPemasukanTokoPdf } from "@/lib/export/pmt-pdf.mjs";
import { buatPemasukanTokoXlsx } from "@/lib/export/pmt-xlsx.mjs";
import { pmtTotals } from "@/lib/docs/pmt";

export const runtime = "nodejs";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

// Unduhan dokumen untuk Invoice (toko) dan Pemasukan Toko. Jenis dokumen lain belum punya unduhan.
export async function GET(req: Request, { params }: { params: Promise<{ slug: string; id: string }> }) {
  const { slug, id } = await params;
  if ((slug !== "inv" && slug !== "pmt") || !UUID.test(id)) return NextResponse.json({ error: "Dokumen tidak dikenal." }, { status: 404 });
  const session = await getSession();
  if (!session) return NextResponse.json({ error: "Silakan masuk dulu." }, { status: 401 });
  const mod = slug === "pmt" ? "store_income" : "invoice";
  if (!session.can(mod, "view") || !session.can(mod, "export")) {
    return NextResponse.json({ error: "Anda tidak memiliki izin mengunduh dokumen ini." }, { status: 403 });
  }
  const q = new URL(req.url).searchParams;
  const pdf = q.get("format") === "pdf";
  const inline = q.get("inline") === "1";
  const supabase = await createClient();
  if (slug === "pmt") {
    const { data: rep } = await supabase
      .from("store_income_reports")
      .select("doc_number, period_from, period_to, store_income_lines(entry_date, description, cash, qris, debit, grab, tf, deposited, created_at), store_income_receivables(name, amount, created_at)")
      .eq("id", id).is("deleted_at", null).maybeSingle();
    if (!rep) return NextResponse.json({ error: "Laporan tidak ditemukan." }, { status: 404 });
    type L = { entry_date: string | null; description: string; cash: number; qris: number; debit: number; grab: number; tf: number; deposited: number; created_at: string };
    type Rc = { name: string; amount: number; created_at: string };
    const ls = [...((rep.store_income_lines as unknown as L[]) ?? [])].sort((a, b) => (a.entry_date ?? "").localeCompare(b.entry_date ?? "") || a.created_at.localeCompare(b.created_at));
    const rs = [...((rep.store_income_receivables as unknown as Rc[]) ?? [])].sort((a, b) => a.created_at.localeCompare(b.created_at));
    const total = pmtTotals(ls, rs);
    const data = {
      nomor: rep.doc_number, dari: rep.period_from, sampai: rep.period_to,
      baris: ls.map((l) => ({ tanggal: l.entry_date, desc: l.description, cash: Number(l.cash), qris: Number(l.qris), debit: Number(l.debit), grab: Number(l.grab), tf: Number(l.tf), deposited: Number(l.deposited) })),
      piutang: rs.map((x) => ({ nama: x.name, jumlah: Number(x.amount) })), total,
    };
    const safeP = String(rep.doc_number).replace(/[^A-Za-z0-9._-]+/g, "_");
    if (pdf) {
      const bytes = await buatPemasukanTokoPdf(data);
      return new NextResponse(bytes as BodyInit, {
        headers: { "Content-Type": "application/pdf", "Content-Disposition": `${inline ? "inline" : "attachment"}; filename="${safeP}.pdf"`, "Cache-Control": "private, no-store" },
      });
    }
    const wbp = await buatPemasukanTokoXlsx(data);
    return new NextResponse((await wbp.xlsx.writeBuffer()) as BodyInit, {
      headers: { "Content-Type": XLSX, "Content-Disposition": `attachment; filename="${safeP}.xlsx"`, "Cache-Control": "private, no-store" },
    });
  }
  const { data: inv } = await supabase
    .from("invoices")
    .select("doc_number, invoice_date, due_date, status, tax_rate, tax_amount, down_payment, delivery_note_no, buyer_name, phone, bank_info, signer, use_signature, customers(name), inv_items(line_no, qty, unit_price, description, products(name, units(name)))")
    .eq("id", id).is("deleted_at", null).maybeSingle();
  if (!inv) return NextResponse.json({ error: "Invoice tidak ditemukan." }, { status: 404 });

  const items = [...((inv.inv_items as unknown as { line_no: number; qty: number; unit_price: number; description: string | null; products: { name: string; units: { name: string } | null } | null }[]) ?? [])]
    .sort((a, b) => a.line_no - b.line_no);
  const baris = items.map((i) => ({ desc: i.description || i.products?.name || "", qty: Number(i.qty), unit: i.products?.units?.name ?? "", harga: Number(i.unit_price) }));
  if (Number(inv.tax_amount) > 0) baris.push({ desc: `PPN ${Number(inv.tax_rate)}%`, qty: 1, unit: "", harga: Number(inv.tax_amount) });

  const cust = (inv.customers as unknown as { name: string } | null)?.name ?? "";
  const doc = {
    varian: "toko" as const, judul: "INVOICE", nomor: inv.doc_number, tanggal: inv.invoice_date,
    kepada: inv.buyer_name || cust, suratJalan: inv.delivery_note_no || undefined, telepon: inv.phone || undefined,
    baris, uangMuka: Number(inv.down_payment), jatuhTempo: inv.due_date ?? inv.invoice_date, tampilTotal: false,
    bankInfo: inv.bank_info || undefined, penandatangan: inv.signer || undefined, tandaTangan: inv.use_signature,
  };
  const safe = inv.doc_number.replace(/[^A-Za-z0-9._-]+/g, "_");
  if (pdf) {
    const bytes = await buatInvoiceTokoPdf(doc);
    return new NextResponse(bytes as BodyInit, {
      headers: { "Content-Type": "application/pdf", "Content-Disposition": `${inline ? "inline" : "attachment"}; filename="${safe}.pdf"`, "Cache-Control": "private, no-store" },
    });
  }
  const wb = await buatInvoiceXlsx(doc);
  const buf = await wb.xlsx.writeBuffer();
  return new NextResponse(buf as BodyInit, {
    headers: { "Content-Type": XLSX, "Content-Disposition": `attachment; filename="${safe}.xlsx"`, "Cache-Control": "private, no-store" },
  });
}
