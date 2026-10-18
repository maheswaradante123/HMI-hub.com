import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { buatInvoiceXlsx } from "@/lib/export/invoice-xlsx.mjs";

export const runtime = "nodejs";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

// Unduhan dokumen untuk Invoice (toko). Jenis dokumen lain belum punya unduhan.
export async function GET(_req: Request, { params }: { params: Promise<{ slug: string; id: string }> }) {
  const { slug, id } = await params;
  if (slug !== "inv" || !UUID.test(id)) return NextResponse.json({ error: "Dokumen tidak dikenal." }, { status: 404 });
  const session = await getSession();
  if (!session) return NextResponse.json({ error: "Silakan masuk dulu." }, { status: 401 });
  if (!session.can("invoice", "view") || !session.can("invoice", "export")) {
    return NextResponse.json({ error: "Anda tidak memiliki izin mengunduh dokumen ini." }, { status: 403 });
  }
  const supabase = await createClient();
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
  const wb = await buatInvoiceXlsx({
    varian: "toko", judul: "INVOICE", nomor: inv.doc_number, tanggal: inv.invoice_date,
    kepada: inv.buyer_name || cust, suratJalan: inv.delivery_note_no || undefined, telepon: inv.phone || undefined,
    baris, uangMuka: Number(inv.down_payment), jatuhTempo: inv.due_date ?? inv.invoice_date, tampilTotal: false,
    bankInfo: inv.bank_info || undefined, penandatangan: inv.signer || undefined, tandaTangan: inv.use_signature,
  });
  const buf = await wb.xlsx.writeBuffer();
  return new NextResponse(buf as BodyInit, {
    headers: {
      "Content-Type": XLSX,
      "Content-Disposition": `attachment; filename="${inv.doc_number.replace(/[^A-Za-z0-9._-]+/g, "_")}.xlsx"`,
      "Cache-Control": "private, no-store",
    },
  });
}
