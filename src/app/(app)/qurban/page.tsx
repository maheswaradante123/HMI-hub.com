import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { Forbidden } from "@/components/forbidden";
import { listOrders } from "@/lib/qurban/data";
import { MODE_LABEL, kg, rp, tgl } from "@/lib/qurban/format";
import { Empty, Head, Pill, Table, td, th } from "@/components/qurban/ui";

// Pesanan dikelompokkan per tahap. "Sudah deal" = sudah dibayar (Lunas); proforma dan invoice yang belum dibayar tetap di Belum deal.
const TABS = [
  { key: "belum", label: "Belum deal", statuses: ["PROFORMA", "INVOICE"], empty: "Tidak ada pesanan yang belum dibayar. Pesanan yang sudah lunas ada di tab Sudah deal." },
  { key: "deal", label: "Sudah deal", statuses: ["PAID"], empty: "Belum ada pesanan yang lunas. Pesanan masuk ke sini begitu pembayarannya ditandai lunas." },
  { key: "batal", label: "Dibatalkan", statuses: ["CANCELLED"], empty: "Tidak ada pesanan yang dibatalkan." },
] as const;

export default async function MasterPesanan({ searchParams }: { searchParams: Promise<{ tab?: string }> }) {
  const sp = await searchParams;
  const session = await requireSession();
  if (!session.can("qurban", "view")) return <Forbidden roleName={session.roleName} what="Qurban Cerdas" />;
  const semua = await listOrders();
  const tab = TABS.find((t) => t.key === sp.tab) ?? TABS[0];
  const hitung = (t: (typeof TABS)[number]) => semua.filter((o) => (t.statuses as readonly string[]).includes(o.status)).length;
  const rows = semua.filter((o) => (tab.statuses as readonly string[]).includes(o.status));
  const tunggu = rows.filter((o) => o.status === "INVOICE").length;
  const nilai = rows.reduce((s, o) => s + (o.total - o.discount), 0);

  return (
    <div>
      <Head
        title="Master Pesanan Qurban"
        hint="Pesanan Qurban Cerdas per tahap. Yang sudah dibayar (deal) pindah ke tab Sudah deal. Klik kepala kolom untuk mengurutkan, ketik di kotak bawahnya untuk menyaring."
        action={session.can("qurban", "create") ? { href: "/qurban/baru", label: "+ Pesanan baru" } : undefined}
      />
      <nav aria-label="Tahap pesanan" className="mt-5 flex flex-wrap gap-2 border-b border-line">
        {TABS.map((t) => {
          const on = t.key === tab.key;
          return (
            <Link key={t.key} href={t.key === "belum" ? "/qurban" : `/qurban?tab=${t.key}`} aria-current={on ? "page" : undefined}
              className={`-mb-px rounded-t-md border border-b-0 px-5 py-2.5 text-lg font-semibold ${on ? "border-line bg-surface text-brand" : "border-transparent text-muted hover:text-brand"}`}>
              {t.label} <span className="ml-1 rounded-full bg-chip px-2.5 py-0.5 text-base">{hitung(t)}</span>
            </Link>
          );
        })}
      </nav>
      <div className="mt-5 flex flex-wrap gap-3 text-lg">
        <span className="rounded-full bg-chip px-4 py-1.5">Pesanan: <b>{rows.length}</b></span>
        {tab.key === "belum" && <span className="rounded-full bg-chip px-4 py-1.5">Menunggu bayar: <b>{tunggu}</b></span>}
        <span className="rounded-full bg-chip px-4 py-1.5">Nilai setelah diskon: <b>{rp(nilai)}</b></span>
      </div>
      {rows.length === 0 ? <Empty>{semua.length === 0 ? "Belum ada pesanan. Mulai dari tombol Pesanan baru." : tab.empty}</Empty> : (
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
