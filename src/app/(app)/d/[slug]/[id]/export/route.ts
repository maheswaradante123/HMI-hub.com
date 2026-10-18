import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { buatInvoiceXlsx } from "@/lib/export/invoice-xlsx.mjs";
import { buatInvoiceTokoPdf } from "@/lib/export/invoice-toko-pdf.mjs";
import { buatPemasukanTokoPdf } from "@/lib/export/pmt-pdf.mjs";
import { buatPemasukanTokoXlsx } from "@/lib/export/pmt-xlsx.mjs";
import { pmtTotals } from "@/lib/docs/pmt";
import { buatPackingListPdf, buatPackingListXlsx } from "@/lib/export/pl-pdf.mjs";
import { buatRoPdf } from "@/lib/export/ro-pdf.mjs";
import { buatRoXlsx, buatProdXlsx } from "@/lib/export/ro-prod-xlsx.mjs";
import { buatProdPdf, leadTime, tglId } from "@/lib/export/prod-pdf.mjs";

export const runtime = "nodejs";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

// Unduhan dokumen untuk Invoice (toko), Pemasukan Toko, RO dan Production Order (RO dan Production Order hanya PDF). Jenis dokumen lain belum punya unduhan.
export async function GET(req: Request, ctx: { params: Promise<{ slug: string; id: string }> }) {
  try {
    return await handle(req, ctx);
  } catch (e) {
    console.error("export gagal", e);
    return NextResponse.json({ error: "Gagal membuat dokumen: " + (e instanceof Error ? e.message : String(e)) }, { status: 500 });
  }
}

async function handle(req: Request, { params }: { params: Promise<{ slug: string; id: string }> }) {
  const { slug, id } = await params;
  if ((slug !== "inv" && slug !== "pmt" && slug !== "ro" && slug !== "prod" && slug !== "pl") || !UUID.test(id)) return NextResponse.json({ error: "Dokumen tidak dikenal." }, { status: 404 });
  const session = await getSession();
  if (!session) return NextResponse.json({ error: "Silakan masuk dulu." }, { status: 401 });
  const mod = slug === "pmt" ? "store_income" : slug === "ro" ? "ro" : slug === "prod" ? "production_order" : slug === "pl" ? "packing_list" : "invoice";
  if (!session.can(mod, "view") || !session.can(mod, "export")) {
    return NextResponse.json({ error: "Anda tidak memiliki izin mengunduh dokumen ini." }, { status: 403 });
  }
  const q = new URL(req.url).searchParams;
  const pdf = q.get("format") === "pdf";
  const inline = q.get("inline") === "1";
  const supabase = await createClient();
  const pdfHeaders = (name: string) => ({ "Content-Type": "application/pdf", "Content-Disposition": `${inline ? "inline" : "attachment"}; filename="${name.replace(/[^A-Za-z0-9._-]+/g, "_")}.pdf"`, "Cache-Control": "private, no-store" });
  const xlsxResponse = async (wb: { xlsx: { writeBuffer(): Promise<ArrayBuffer | Uint8Array> } }, name: string) =>
    new NextResponse((await wb.xlsx.writeBuffer()) as BodyInit, {
      headers: { "Content-Type": XLSX, "Content-Disposition": `attachment; filename="${name.replace(/[^A-Za-z0-9._-]+/g, "_")}.xlsx"`, "Cache-Control": "private, no-store" },
    });
  if (slug === "pl") {
    const { data: pl } = await supabase
      .from("packing_lists")
      .select("doc_number, pack_date, phone, supervisor, notes, customers(name), pl_items(line_no, qty, gross_weight, products(name))")
      .eq("id", id).is("deleted_at", null).maybeSingle();
    if (!pl) return NextResponse.json({ error: "Packing List tidak ditemukan." }, { status: 404 });
    type It = { line_no: number; qty: number; gross_weight: number | null; products: { name: string } | null };
    const items = [...((pl.pl_items as unknown as It[]) ?? [])].sort((a, b) => a.line_no - b.line_no);
    const cust = (pl.customers as unknown as { name: string } | null)?.name ?? "";
    const plData = {
      nomor: pl.doc_number, tanggal: pl.pack_date, kepada: cust, telepon: pl.phone ?? "", catatan: pl.notes ?? "", pengawas: pl.supervisor ?? "", penerima: cust,
      baris: items.map((i) => ({ jenis: i.products?.name ?? "", net: Number(i.qty), gross: Number(i.gross_weight ?? i.qty) })),
    };
    if (!pdf) return xlsxResponse(await buatPackingListXlsx(plData), pl.doc_number);
    return new NextResponse((await buatPackingListPdf(plData)) as BodyInit, { headers: pdfHeaders(pl.doc_number) });
  }
  if (slug === "ro") {
    const { data: ro } = await supabase
      .from("request_orders")
      .select("doc_number, order_date, delivery_date, delivery_time, orderer_name, phone, delivery_address, payment_method, delivery_method, notes, created_by, customers(name), ro_items(line_no, qty, unit_price, cut_type, packaging, products(name, units(name)))")
      .eq("id", id).is("deleted_at", null).maybeSingle();
    if (!ro) return NextResponse.json({ error: "RO tidak ditemukan." }, { status: 404 });
    type It = { line_no: number; qty: number; unit_price: number; cut_type: string | null; packaging: string | null; products: { name: string; units: { name: string } | null } | null };
    const items = [...((ro.ro_items as unknown as It[]) ?? [])].sort((a, b) => a.line_no - b.line_no);
    let pembuat = "";
    if (ro.created_by) {
      const { data: u } = await supabase.from("user_directory").select("full_name").eq("id", ro.created_by).maybeSingle();
      pembuat = u?.full_name ?? "";
    }
    const cust = (ro.customers as unknown as { name: string } | null)?.name ?? "";
    const roData = {
      nomor: ro.doc_number, tanggal: ro.order_date, pemesan: ro.orderer_name || cust, alamat: ro.delivery_address ?? "", telepon: ro.phone ?? "",
      tglKirim: ro.delivery_date, waktuKirim: ro.delivery_time ?? "",
      baris: items.map((i) => ({ nama: i.products?.name ?? "", qty: Number(i.qty), unit: i.products?.units?.name ?? "", potong: i.cut_type ?? "", kemas: i.packaging ?? "", harga: Number(i.unit_price) })),
      bayar: ro.payment_method ?? "", kirim: ro.delivery_method ?? "", catatan: ro.notes ?? "", pembuat, jabatan: "Marketing",
      tandaTangan: /syifa/i.test(pembuat),
    };
    if (!pdf) return xlsxResponse(await buatRoXlsx(roData), ro.doc_number);
    return new NextResponse((await buatRoPdf(roData)) as BodyInit, { headers: pdfHeaders(ro.doc_number) });
  }
  if (slug === "prod") {
    const { data: po } = await supabase
      .from("production_orders")
      .select("doc_number, order_date, needed_date, send_note, delivery_address, pic, cow_codes, notes, request_orders(doc_number, order_date, delivery_date, delivery_time, phone, delivery_method, delivery_address, customers(name)), po_items(line_no, qty, cut_type, packaging, products:products!po_items_product_id_fkey(name, units(name)))")
      .eq("id", id).is("deleted_at", null).maybeSingle();
    if (!po) return NextResponse.json({ error: "Production Order tidak ditemukan." }, { status: 404 });
    type It = { line_no: number; qty: number; cut_type: string | null; packaging: string | null; products: { name: string; units: { name: string } | null } | null };
    type Ro = { doc_number: string; order_date: string; delivery_date: string | null; delivery_time: string | null; phone: string | null; delivery_method: string | null; delivery_address: string | null; customers: { name: string } | null };
    const items = [...((po.po_items as unknown as It[]) ?? [])].sort((a, b) => a.line_no - b.line_no);
    const ro = po.request_orders as unknown as Ro | null;
    const tglKirimRo = ro?.delivery_date ?? po.needed_date;
    const kirimTeks = tglKirimRo ? tglId(tglKirimRo) + (ro?.delivery_time ? `, ${ro.delivery_time}` : "") : "";
    const poData = {
      nomor: po.doc_number, tanggal: po.order_date, customer: ro?.customers?.name ?? "", telepon: ro?.phone ?? "",
      leadTime: leadTime(ro?.order_date ?? po.order_date, tglKirimRo), roNomor: ro?.doc_number ?? "", tglOrder: ro?.order_date ?? po.order_date, tglKirim: kirimTeks,
      baris: items.map((i) => ({ nama: i.products?.name ?? "", qty: Number(i.qty), unit: i.products?.units?.name ?? "", potong: i.cut_type ?? "", kemas: i.packaging ?? "" })),
      metode: ro?.delivery_method ?? "", jadwal: po.send_note || kirimTeks, alamat: po.delivery_address || ro?.delivery_address || "",
      pic: po.pic ?? "", kodeSapi: po.cow_codes ?? "", catatan: po.notes ?? "",
    };
    if (!pdf) return xlsxResponse(await buatProdXlsx(poData), po.doc_number);
    return new NextResponse((await buatProdPdf(poData)) as BodyInit, { headers: pdfHeaders(po.doc_number) });
  }
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
