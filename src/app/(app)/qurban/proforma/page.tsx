import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { Forbidden } from "@/components/forbidden";
import { listOrders } from "@/lib/qurban/data";
import { kg, rp, tgl } from "@/lib/qurban/format";
import { Empty, Head, Pill, Table, td, th } from "@/components/qurban/ui";

export default async function ProformaPage() {
  const session = await requireSession();
  if (!session.can("qurban", "view")) return <Forbidden roleName={session.roleName} what="Proforma Qurban" />;
  const rows = (await listOrders()).filter((o) => o.pro_no);
  const canExport = session.can("qurban", "export");
  return (
    <div>
      <Head title="Proforma Invoice" hint="Berlaku 2 hari sejak dibuat. Diskon dari negosiasi diisi Owner di halaman pesanan." action={session.can("qurban", "create") ? { href: "/qurban/baru", label: "+ Pesanan baru" } : undefined} />
      {rows.length === 0 ? <Empty>Belum ada proforma.</Empty> : (
        <Table>
          <thead className="border-b border-line"><tr>
            {["No. Proforma", "Tanggal", "Pelanggan", "Sapi", "Bobot", "Total", "Diskon", "Setelah diskon", "Status", "Unduh"].map((h) => <th key={h} scope="col" className={th}>{h}</th>)}
          </tr></thead>
          <tbody>
            {rows.map((o) => (
              <tr key={o.id} className="border-b border-line last:border-0">
                <td className={td}><Link href={`/qurban/${o.id}`} className="font-semibold text-brand underline">{o.pro_no}</Link></td>
                <td className={td}>{tgl(o.pro_date)}</td><td className={td}>{o.customer_nick}</td><td className={td}>{o.cow_no}</td>
                <td className={`${td} text-right tabular-nums`}>{kg(o.initial_weight)}</td>
                <td className={`${td} text-right tabular-nums`}>{rp(o.total)}</td>
                <td className={`${td} text-right tabular-nums`}>{rp(o.discount)}</td>
                <td className={`${td} text-right tabular-nums`}>{rp(o.total - o.discount)}</td>
                <td className={td}><Pill status={o.status} /></td>
                <td className={td}>{canExport ? <a href={`/qurban/export/proforma/${o.id}`} className="font-semibold underline">Excel</a> : ""}</td>
              </tr>
            ))}
          </tbody>
        </Table>
      )}
    </div>
  );
}
