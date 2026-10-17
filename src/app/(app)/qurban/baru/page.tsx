import { requireSession } from "@/lib/auth";
import { Forbidden } from "@/components/forbidden";
import { getSettings, listClasses } from "@/lib/qurban/data";
import { todayIso } from "@/lib/qurban/format";
import { OrderForm } from "@/components/qurban/order-form";
import { Head } from "@/components/qurban/ui";

export default async function BaruPage() {
  const session = await requireSession();
  if (!session.can("qurban", "create")) return <Forbidden roleName={session.roleName} what="membuat pesanan Qurban" />;
  const [classes, st] = await Promise.all([listClasses(), getSettings()]);
  const today = todayIso();
  // Daftar harga yang berlaku hari ini: per kelas, versi terbaru yang sudah berlaku.
  const cur = new Map<number, (typeof classes)[number]>();
  for (const c of classes) if (c.effective_from <= today && !cur.has(c.min_kg)) cur.set(c.min_kg, c);
  return (
    <div>
      <Head title="Pesanan Qurban baru" hint="Timbang sapi, isi hasilnya, dan proforma langsung dibuat." />
      <div className="mt-6"><OrderForm classes={[...cur.values()]} today={today} careEnd={st.care_end ?? "2027-05-17"} /></div>
    </div>
  );
}
