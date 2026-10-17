import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { Forbidden } from "@/components/forbidden";
import { listBills, listOrders } from "@/lib/qurban/data";
import { bulan, rp, tgl } from "@/lib/qurban/format";
import { Empty, Head, Pill, Table, td, th } from "@/components/qurban/ui";
import { QForm } from "@/components/qurban/qform";
import { markBillPaid, markPaid } from "../actions";

export default async function InvoicePage() {
  const session = await requireSession();
  if (!session.can("qurban", "view")) return <Forbidden roleName={session.roleName} what="Invoice dan Tagihan Qurban" />;
  const [orders, bills] = await Promise.all([listOrders(), listBills()]);
  const byId = new Map(orders.map((o) => [o.id, o]));
  const canExport = session.can("qurban", "export");
  const canEdit = session.can("qurban", "edit");

  type Row = { key: string; no: string; jenis: string; tanggal: string; tempo: string; nick: string; cow: string; amount: number; status: string; orderId: string; xls: string; pay?: React.ReactNode };
  const rows: Row[] = [];
  for (const o of orders) {
    if (!o.inv_no) continue;
    rows.push({
      key: `o${o.id}`, no: o.inv_no, jenis: "Invoice awal", tanggal: o.inv_date ?? "", tempo: o.due_date ?? "", nick: o.customer_nick, cow: o.cow_no,
      amount: o.due_amount, status: o.status, orderId: o.id, xls: `/qurban/export/invoice/${o.id}`,
      pay: o.status === "INVOICE" && canEdit ? <QForm action={markPaid.bind(null, o.id)} label="Tandai lunas" /> : undefined,
    });
  }
  for (const b of bills) {
    const o = byId.get(b.order_id);
    if (!o || b.status === "CANCELLED") continue;
    rows.push({
      key: `b${b.id}`, no: b.bill_no, jenis: `Perawatan ${bulan(b.ym)}`, tanggal: b.bill_date, tempo: b.due_date, nick: o.customer_nick, cow: o.cow_no,
      amount: b.days * b.rate, status: b.status, orderId: o.id, xls: `/qurban/export/bill/${b.id}`,
      pay: b.status === "ISSUED" && canEdit ? <QForm action={markBillPaid.bind(null, b.id)} label="Tandai lunas" /> : undefined,
    });
  }
  rows.sort((a, b) => b.tanggal.localeCompare(a.tanggal) || b.no.localeCompare(a.no));

  return (
    <div>
      <Head title="Invoice dan Tagihan" hint="Invoice awal dan tagihan perawatan bulanan. Invoice awal jatuh tempo 1 hari, tagihan bulanan 7 hari setelah terbit." />
      {rows.length === 0 ? <Empty>Belum ada invoice yang terbit.</Empty> : (
        <Table>
          <thead className="border-b border-line"><tr>
            {["Nomor", "Jenis", "Tanggal", "Jatuh tempo", "Pelanggan", "Sapi", "Jumlah", "Status", "Unduh", ""].map((h, i) => <th key={i} scope="col" className={th}>{h}</th>)}
          </tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.key} className="border-b border-line last:border-0">
                <td className={td}><Link href={`/qurban/${r.orderId}`} className="font-semibold text-brand underline">{r.no}</Link></td>
                <td className={td}>{r.jenis}</td><td className={td}>{tgl(r.tanggal)}</td><td className={td}>{tgl(r.tempo)}</td>
                <td className={td}>{r.nick}</td><td className={td}>{r.cow}</td>
                <td className={`${td} text-right tabular-nums`}>{rp(r.amount)}</td>
                <td className={td}><Pill status={r.status} /></td>
                <td className={td}>{canExport ? <a href={r.xls} className="font-semibold underline">Excel</a> : ""}</td>
                <td className={td}>{r.pay}</td>
              </tr>
            ))}
          </tbody>
        </Table>
      )}
    </div>
  );
}
