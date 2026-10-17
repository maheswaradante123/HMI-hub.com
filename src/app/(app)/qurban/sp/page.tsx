import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { Forbidden } from "@/components/forbidden";
import { listBuyers, listOrders } from "@/lib/qurban/data";
import { kg, tgl } from "@/lib/qurban/format";
import { Empty, Head, Table, td, th } from "@/components/qurban/ui";

export default async function SpList() {
  const session = await requireSession();
  if (!session.can("qurban", "view")) return <Forbidden roleName={session.roleName} what="Surat Perjanjian" />;
  const canSp = session.can("qurban", "create") || session.can("qurban", "edit");
  const [orders, buyers] = await Promise.all([listOrders(), canSp ? listBuyers() : Promise.resolve([])]);
  const by = new Map(buyers.map((b) => [b.order_id, b]));
  const rows = orders.filter((o) => o.status === "PAID");
  const canExport = session.can("qurban", "export");
  return (
    <div>
      <Head title="Surat Perjanjian" hint="Dibuat setelah invoice lunas: SP-JB (jual beli) dan SP-PL (pemeliharaan). Data lengkap pembeli (nama, KTP, alamat) diisi di sini, bukan saat proforma." />
      {rows.length === 0 ? <Empty>Belum ada pesanan lunas.</Empty> : (
        <Table>
          <thead className="border-b border-line"><tr>{["Sapi", "Pelanggan", "Bobot awal", "Lunas", "Nama lengkap", "No. SP-JB", "No. SP-PL", "Aksi"].map((h) => <th key={h} scope="col" className={th}>{h}</th>)}</tr></thead>
          <tbody>
            {rows.map((o) => {
              const b = by.get(o.id);
              return (
                <tr key={o.id} className="border-b border-line last:border-0">
                  <td className={td}>{o.cow_no}</td><td className={td}>{o.customer_nick}</td>
                  <td className={`${td} text-right tabular-nums`}>{kg(o.initial_weight)}</td><td className={td}>{tgl(o.paid_at)}</td>
                  <td className={td}>{b?.full_name ?? (canSp ? "Belum diisi" : "-")}</td>
                  <td className={td}>{b?.sp_jb_no ?? "-"}</td><td className={td}>{b?.sp_pl_no ?? "-"}</td>
                  <td className={`${td} space-x-3 whitespace-nowrap`}>
                    {canSp && <Link href={`/qurban/sp/${o.id}`} className="font-semibold underline">{b ? "Buka / ubah" : "Isi data dan buat surat"}</Link>}
                    {b && canExport && <><a href={`/qurban/export/spjb/${o.id}`} className="font-semibold underline">SP-JB</a><a href={`/qurban/export/sppl/${o.id}`} className="font-semibold underline">SP-PL</a></>}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </Table>
      )}
    </div>
  );
}
