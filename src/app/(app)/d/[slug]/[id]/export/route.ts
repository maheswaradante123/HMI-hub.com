import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { buatInvoiceXlsx } from "@/lib/export/invoice-xlsx.mjs";
import { buatInvoiceTokoPdf } from "@/lib/export/invoice-toko-pdf.mjs";
import { buatPemasukanTokoPdf } from "@/lib/export/pmt-pdf.mjs";
import { buatPemasukanTokoXlsx } from "@/lib/export/pmt-xlsx.mjs";
import { pmtTotals } from "@/lib/docs/pmt";
import { buatCpjPdf } from "@/lib/export/jcp-pdf.mjs";
import { buatCpjXlsx } from "@/lib/export/jcp-xlsx.mjs";
import { buatApPdf } from "@/lib/export/ap-pdf.mjs";
import { buatApXlsx } from "@/lib/export/ap-xlsx.mjs";
import { apTotals } from "@/lib/docs/ap";
import { jcpPrintNumber, jcpTotals, planAmount, realAmount } from "@/lib/docs/jcp";
import { buatPackingListPdf, buatPackingListXlsx } from "@/lib/export/pl-pdf.mjs";
import { buatSuratJalanPdf, buatSuratJalanXlsx } from "@/lib/export/do-pdf.mjs";
import { buatRoPdf } from "@/lib/export/ro-pdf.mjs";
import { buatRoXlsx, buatProdXlsx } from "@/lib/export/ro-prod-xlsx.mjs";
import { buatProdPdf, leadTime, tglId } from "@/lib/export/prod-pdf.mjs";
import { docUnit } from "@/lib/docs/format";

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
  if ((slug !== "inv" && slug !== "pmt" && slug !== "jcp" && slug !== "ro" && slug !== "prod" && slug !== "pl" && slug !== "do" && slug !== "ap") || !UUID.test(id)) return NextResponse.json({ error: "Dokumen tidak dikenal." }, { status: 404 });
  const session = await getSession();
  if (!session) return NextResponse.json({ error: "Silakan masuk dulu." }, { status: 401 });
  const mod = slug === "jcp" ? "cpj_journal" : slug === "pmt" ? "store_income" : slug === "ro" ? "ro" : slug === "prod" ? "production_order" : slug === "pl" ? "packing_list" : slug === "do" ? "delivery_order" : slug === "ap" ? "purchase_analysis" : "invoice";
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
  if (slug === "do") {
    const { data: dn } = await supabase
      .from("delivery_orders")
      .select("doc_number, do_date, notes, customers(name), packing_lists(doc_number, phone, supervisor, request_orders(orderer_name), pl_items(line_no, qty, products(name, product_categories(name), units(name))))")
      .eq("id", id).is("deleted_at", null).maybeSingle();
    if (!dn) return NextResponse.json({ error: "Surat jalan tidak ditemukan." }, { status: 404 });
    type It = { line_no: number; qty: number; products: { name: string; product_categories: { name: string } | null; units: { name: string } | null } | null };
    type P = { doc_number: string; phone: string | null; supervisor: string | null; request_orders: { orderer_name: string | null } | null; pl_items: It[] };
    const pl = dn.packing_lists as unknown as P | null;
    const cust = (dn.customers as unknown as { name: string } | null)?.name ?? "";
    // Satu baris per produk: jumlahkan berat net semua kemasan produk yang sama.
    const per = new Map<string, { desc: string; jenis: string; qty: number; unit: string }>();
    for (const i of [...(pl?.pl_items ?? [])].sort((a, b) => a.line_no - b.line_no)) {
      const name = i.products?.name ?? "";
      const cur = per.get(name) ?? { desc: name, jenis: i.products?.product_categories?.name ?? "Daging", qty: 0, unit: docUnit(i.products?.units?.name) || "Kg" };
      cur.qty = Math.round((cur.qty + Number(i.qty)) * 1000) / 1000;
      per.set(name, cur);
    }
    const doData = {
      nomor: dn.doc_number, tanggal: dn.do_date, kepada: pl?.request_orders?.orderer_name || cust, telepon: pl?.phone ?? "", catatan: dn.notes ?? "",
      pengawas: pl?.supervisor ?? "", penerima: cust, baris: [...per.values()],
    };
    if (!pdf) return xlsxResponse(await buatSuratJalanXlsx(doData), dn.doc_number);
    return new NextResponse((await buatSuratJalanPdf(doData)) as BodyInit, { headers: pdfHeaders(dn.doc_number) });
  }
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
      baris: items.map((i) => ({ nama: i.products?.name ?? "", qty: Number(i.qty), unit: docUnit(i.products?.units?.name), potong: i.cut_type ?? "", kemas: i.packaging ?? "", harga: Number(i.unit_price) })),
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
      baris: items.map((i) => ({ nama: i.products?.name ?? "", qty: Number(i.qty), unit: docUnit(i.products?.units?.name), potong: i.cut_type ?? "", kemas: i.packaging ?? "" })),
      metode: ro?.delivery_method ?? "", jadwal: po.send_note || kirimTeks, alamat: po.delivery_address || ro?.delivery_address || "",
      pic: po.pic ?? "", kodeSapi: po.cow_codes ?? "", catatan: po.notes ?? "",
    };
    if (!pdf) return xlsxResponse(await buatProdXlsx(poData), po.doc_number);
    return new NextResponse((await buatProdPdf(poData)) as BodyInit, { headers: pdfHeaders(po.doc_number) });
  }
  if (slug === "jcp") {
    const { data: j } = await supabase
      .from("cash_journals")
      .select("doc_number, journal_date, status, initiator_name, initiator_title, approver_name, approver_title, pay_note, notes, cash_journal_lines(line_no, trans_date, ac, code, description, price, qty, unit, flag, real_price, real_qty, proof)")
      .eq("id", id).is("deleted_at", null).maybeSingle();
    if (!j) return NextResponse.json({ error: "Jurnal tidak ditemukan." }, { status: 404 });
    type JL = { line_no: number; trans_date: string | null; ac: string | null; code: string | null; description: string; price: number; qty: number; unit: string | null; flag: string; real_price: number | null; real_qty: number | null; proof: string | null };
    const ls = [...((j.cash_journal_lines as unknown as JL[]) ?? [])].sort((a, b) => a.line_no - b.line_no);
    const nums = ls.map((l) => ({ price: Number(l.price), qty: Number(l.qty), flag: l.flag, real_price: l.real_price === null ? null : Number(l.real_price), real_qty: l.real_qty === null ? null : Number(l.real_qty) }));
    const data = {
      nomor: jcpPrintNumber(j.doc_number, j.status), tanggal: j.journal_date, status: j.status,
      initiatorNama: j.initiator_name ?? "", initiatorJabatan: j.initiator_title ?? "", approverNama: j.approver_name ?? "", approverJabatan: j.approver_title ?? "",
      payNote: j.pay_note ?? "", note: j.notes ?? "", ttdInitiator: /arfan/i.test(j.initiator_name ?? ""),
      baris: ls.map((l, i) => ({ tanggal: l.trans_date, ac: l.ac ?? "", kode: l.code ?? "", desc: l.description, price: nums[i].price, qty: nums[i].qty, unit: l.unit ?? "", flag: l.flag, realPrice: nums[i].real_price, realQty: nums[i].real_qty, bukti: l.proof ?? "" })),
      hitung: {
        planAmount: (l: { price: number; qty: number }) => planAmount({ price: l.price, qty: l.qty, flag: "NONE" }),
        realAmount: (l: { price: number; qty: number; flag: string; realPrice: number | null; realQty: number | null }, done: boolean) => realAmount({ price: l.price, qty: l.qty, flag: l.flag, real_price: l.realPrice, real_qty: l.realQty }, done),
      },
      total: jcpTotals(nums, j.status === "REALIZED"),
    };
    if (pdf) return new NextResponse((await buatCpjPdf(data)) as BodyInit, { headers: pdfHeaders(data.nomor) });
    return xlsxResponse(await buatCpjXlsx(data), data.nomor);
  }
  if (slug === "ap") {
    const { data: ap } = await supabase
      .from("purchase_analyses")
      .select("doc_number, analysis_date, top_date, supplier_invoice, total_purchase, lower_side, upper_side, manual_total_cost, suppliers(name), cow_types(code), ap_cows(carcass_weighings(carcass_weight)), ap_items(line_no, weight, unit_price, products(name, product_categories(code))), ap_nonk(line_no, name, weight, unit_price), ap_costs(line_no, amount, cost_types(name))")
      .eq("id", id).is("deleted_at", null).maybeSingle();
    if (!ap) return NextResponse.json({ error: "Analisa tidak ditemukan." }, { status: 404 });
    type Rel<T> = T | T[] | null;
    const one = <T,>(v: Rel<T>): T | null => (Array.isArray(v) ? (v[0] ?? null) : v);
    type It = { line_no: number; weight: number; unit_price: number; products: Rel<{ name: string; product_categories: Rel<{ code: string }> }> };
    type Nk = { line_no: number; name: string; weight: number | null; unit_price: number };
    type Cs = { line_no: number; amount: number; cost_types: Rel<{ name: string }> };
    const items = [...((ap.ap_items as unknown as It[]) ?? [])].sort((a, b) => a.line_no - b.line_no).map((i) => {
      const p = one(i.products);
      return { nama: p?.name ?? "", qty: Number(i.weight), price: Number(i.unit_price), meat: one(p?.product_categories ?? null)?.code === "DAGING" };
    });
    const nonk = [...((ap.ap_nonk as unknown as Nk[]) ?? [])].sort((a, b) => a.line_no - b.line_no).map((n) => ({ nama: n.name, qty: n.weight === null ? null : Number(n.weight), price: Number(n.unit_price) }));
    const biaya = [...((ap.ap_costs as unknown as Cs[]) ?? [])].sort((a, b) => a.line_no - b.line_no).map((c) => ({ nama: one(c.cost_types)?.name ?? "", amount: Number(c.amount) }));
    const karkas = ((ap.ap_cows as unknown as { carcass_weighings: Rel<{ carcass_weight: number }> }[]) ?? []).reduce((s, c) => s + Number(one(c.carcass_weighings)?.carcass_weight ?? 0), 0);
    const manualTotal = ap.manual_total_cost === null ? null : Number(ap.manual_total_cost);
    const lower = ap.lower_side === null ? null : Number(ap.lower_side), upper = ap.upper_side === null ? null : Number(ap.upper_side);
    const total = apTotals({ items, nonk, costs: biaya.map((c) => c.amount), cowPrice: Number(ap.total_purchase), manualTotal, carcass: karkas, lower, upper });
    const apData = {
      nomor: ap.doc_number, tanggal: ap.analysis_date, supplier: one(ap.suppliers as Rel<{ name: string }>)?.name ?? "", jenis: one(ap.cow_types as Rel<{ code: string }>)?.code ?? "",
      top: ap.top_date, invoice: ap.supplier_invoice ?? "", harga: Number(ap.total_purchase), baris: items, nonk, biaya, karkas, lower, upper, manualTotal, total,
    };
    if (pdf) return new NextResponse((await buatApPdf(apData)) as BodyInit, { headers: pdfHeaders(ap.doc_number) });
    return xlsxResponse(await buatApXlsx(apData), ap.doc_number);
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
  const baris = items.map((i) => ({ desc: i.description || i.products?.name || "", qty: Number(i.qty), unit: docUnit(i.products?.units?.name), harga: Number(i.unit_price) }));
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
