import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { Forbidden } from "@/components/forbidden";
import { listOrders } from "@/lib/qurban/data";
import { MODE_LABEL, kg, rp, tgl } from "@/lib/qurban/format";
import { Empty, Head, Pill, Table, td, th } from "@/components/qurban/ui";

export default async function MasterPesanan() {
  const session = await requireSession();
  if (!session.can("qurban", "view")) return <Forbidden roleName={session.roleName} what="Qurban Cerdas" />;
  const rows = await listOrders();
  const aktif = rows.filter((o) => o.status !== "CANCELLED");
  const lunas = rows.filter((o) => o.status === "PAID").length;
  const tunggu = rows.filter((o) => o.status === "INVOICE").length;
  const nilai = aktif.reduce((s, o) => s + (o.total - o.discount), 0);

  return (
    <div>
      <Head
        title="Master Pesanan Qurban"
        hint="Semua pesanan Qurban Cerdas. Klik kepala kolom untuk mengurutkan, ketik di kotak bawahnya untuk menyaring."
        action={session.can("qurban", "create") ? { href: "/qurban/baru", label: "+ Pesanan baru" } : undefined}
      />
      <div className="mt-5 flex flex-wrap gap-3 text-lg">
        <span className="rounded-full bg-chip px-4 py-1.5">Pesanan aktif: <b>{aktif.length}</b></span>
        <span className="rounded-full bg-chip px-4 py-1.5">Menunggu bayar: <b>{tunggu}</b></span>
        <span className="rounded-full bg-chip px-4 py-1.5">Lunas: <b>{lunas}</b></span>
        <span className="rounded-full bg-chip px-4 py-1.5">Nilai setelah diskon: <b>{rp(nilai)}</b></span>
      </div>
      {rows.length === 0 ? <Empty>Belum ada pesanan. Mulai dari tombol Pesanan baru.</Empty> : (
        <Table>
          <thead className="border-b border-line"><tr>
            {["No. Sapi", "Pelanggan", "Mulai", "Bobot awal", "Bobot terakhir", "Perawatan", "Total", "Sisa bayar", "Status", "Proforma/Invoice"].map((h) => <th key={h} scope="col" className={th}>{h}</th>)}
          </tr></thead>
          <tbody>
            {rows.map((o) => (
              <tr key={o.id} className="border-b border-line last:border-0">
                <td className={td}><Link href={`/qurban/${o.id}`} className="font-semibold text-brand underline">{o.cow_no}</Link></td>
                <td className={td}>{o.customer_nick}</td>
                <td className={td}>{tgl(o.start_date)}</td>
                <td className={`${td} text-right tabular-nums`}>{kg(o.initial_weight)}</td>
                <td className={`${td} text-right tabular-nums`}>{kg(o.last_weight)}</td>
                <td className={td}>{MODE_LABEL[o.pay_mode]}</td>
                <td className={`${td} text-right tabular-nums`}>{rp(o.total)}</td>
                <td className={`${td} text-right tabular-nums`}>{rp(o.due_amount)}</td>
                <td className={td}><Pill status={o.status} /></td>
                <td className={td}>{o.inv_no ?? o.pro_no}</td>
              </tr>
            ))}
          </tbody>
        </Table>
      )}
    </div>
  );
}
