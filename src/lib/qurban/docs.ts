import "server-only";
import {
  getBuyer, getLines, getOrder, listBills, listWeighings, getSettings,
  type Bill, type Buyer, type Order, type Qc, type Line,
} from "./data";
import { createClient } from "@/lib/supabase/server";

const addDays = (iso: string, n: number) => new Date(Date.parse(iso + "T00:00:00Z") + n * 864e5).toISOString().slice(0, 10);
const BLN_EN = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const tglEn = (iso: string) => { const [y, m, d] = iso.split("-").map(Number); return `${d} ${BLN_EN[m - 1]} ${y}`; };
const LATE = "Jika saat tanggal jatuh tempo belum dilakukan pelunasan pembayaran, maka transaksi pembelian dibatalkan.";

export type InvoiceDoc = {
  varian: "qurban"; judul: string; nomor: string; tanggal: string; kepada: string;
  baris: { desc: string; qty: number; unit: string; harga: number }[];
  diskon?: number; uangMuka: number; tampilTotal: boolean; jatuhTempo: string; catatan: string;
};

const toRows = (L: Line[]) => L.map((l) => ({ desc: l.descr, qty: l.qty, unit: l.unit, harga: l.price }));

export async function proformaDoc(o: Order): Promise<InvoiceDoc> {
  const L = await getLines(o.id);
  const pro = o.pro_date ?? o.start_date;
  return {
    varian: "qurban", judul: "PROFORMA-INVOICE", nomor: o.pro_no ?? "", tanggal: pro, kepada: o.customer_nick,
    baris: toRows(L), diskon: o.discount ? o.discount : undefined, uangMuka: o.down_payment, tampilTotal: true,
    jatuhTempo: addDays(pro, 1),
    catatan: `Validitas proforma invoice berlaku selama 2 hari hingga tanggal ${tglEn(addDays(pro, 1))}`,
  };
}

export async function invoiceDoc(o: Order): Promise<InvoiceDoc> {
  const L = await getLines(o.id);
  return {
    varian: "qurban", judul: "INVOICE", nomor: o.inv_no ?? "", tanggal: o.inv_date ?? o.start_date, kepada: o.customer_nick,
    baris: toRows(L), diskon: o.discount, uangMuka: o.down_payment, tampilTotal: false,
    jatuhTempo: o.due_date ?? addDays(o.inv_date ?? o.start_date, 1), catatan: LATE,
  };
}

const BLN_ID = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];
export const ymName = (ym: string) => { const [y, m] = ym.split("-").map(Number); return `${BLN_ID[m - 1]} ${y}`; };

export function billDoc(o: Order, b: Bill): InvoiceDoc {
  return {
    varian: "qurban", judul: "INVOICE", nomor: b.bill_no, tanggal: b.bill_date, kepada: o.customer_nick,
    baris: [{ desc: `Perawatan Bulan ${ymName(b.ym)}`, qty: b.days, unit: "Hari", harga: b.rate }],
    diskon: 0, uangMuka: 0, tampilTotal: false, jatuhTempo: b.due_date, catatan: LATE,
  };
}

// Data QC Report: sapi milik pelanggan (invoice sudah terbit) dengan penimbangan sampai akhir bulan laporan.
export async function qcDoc(q: Qc) {
  const supabase = await createClient();
  const { data: orders } = await supabase
    .from("qurban_orders").select("id, cow_no, start_date, initial_weight, status")
    .eq("customer_nick", q.customer_nick).in("status", ["INVOICE", "PAID"]).is("deleted_at", null).order("created_at");
  const list = orders ?? [];
  const w = await listWeighings(list.map((o) => o.id as string));
  const lastDay = new Date(Date.UTC(Number(q.ym.slice(0, 4)), Number(q.ym.slice(5, 7)), 0)).toISOString().slice(0, 10);
  return {
    nomor: q.qc_no, publish: q.publish_date, kepada: q.customer_nick, catatan: q.note,
    ppic: q.ppic_name, qc: q.qc_name, direktur: q.director_name,
    sapi: list
      .filter((o) => (o.start_date as string) <= lastDay)
      .map((o) => ({
        nomor: String(o.cow_no), bobotAwal: Number(o.initial_weight), tglAwal: o.start_date as string,
        timbang: w.filter((x) => x.order_id === o.id).slice(1).filter((x) => x.weigh_date <= lastDay)
          .map((x) => ({ tgl: x.weigh_date, bobot: x.weight })),
      })),
  };
}

// Data Surat Perjanjian satu pesanan (satu sapi per surat).
export async function spDoc(o: Order, b: Buyer) {
  const st = await getSettings();
  const end = st.care_end ?? "2027-05-17";
  const hari = Math.round((Date.parse(end + "T00:00:00Z") - Date.parse(b.sp_date + "T00:00:00Z")) / 864e5) + 1;
  const sapi = [{ jenis: b.cow_type, nomor: o.cow_no, bobotAwal: o.initial_weight, nilaiAwal: Math.round(o.initial_weight * o.buy_price) }];
  const jb = { seq: b.sp_seq, tanggal: b.sp_date, pembeli: b.full_name, nik: b.nik, alamat: b.address, sapi };
  const pl = {
    seq: b.sp_seq, tanggal: b.sp_date, pemilik: b.full_name, nik: b.nik, alamat: b.address, telepon: b.phone ?? "",
    jb: { seq: b.sp_seq, tanggal: b.sp_date }, hariPemeliharaan: hari, tarifPerHari: o.care_price, sapi,
  };
  return { jb, pl };
}

export { getOrder, getBuyer, listBills };
