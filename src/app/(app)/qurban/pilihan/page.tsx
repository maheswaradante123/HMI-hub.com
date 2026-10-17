import { requireSession } from "@/lib/auth";
import { Forbidden } from "@/components/forbidden";
import { getSettings, listOrders } from "@/lib/qurban/data";
import { CHOICE_LABEL, kg, rp, tgl } from "@/lib/qurban/format";
import { Empty, Head, Table, td, th } from "@/components/qurban/ui";
import { QForm, fieldCls } from "@/components/qurban/qform";
import { setChoice } from "../actions";

export default async function PilihanPage() {
  const session = await requireSession();
  if (!session.can("qurban", "view")) return <Forbidden roleName={session.roleName} what="Pilihan Pemilik" />;
  const [orders, st] = await Promise.all([listOrders(), getSettings()]);
  const rows = orders.filter((o) => o.status === "PAID");
  const canEdit = session.can("qurban", "edit");
  return (
    <div>
      <Head title="Pilihan Pemilik" hint={`Setelah masa perawatan, pemilik memilih: dipakai sendiri, dijual ke pihak lain, atau dijual kembali ke HMI. Batas pemberitahuan ${tgl(st.notice_deadline)}. Nilai beli kembali = bobot terakhir × harga beli kembali kelas saat beli.`} />
      {rows.length === 0 ? <Empty>Belum ada pesanan lunas.</Empty> : (
        <Table>
          <thead className="border-b border-line"><tr>{["Sapi", "Pelanggan", "Bobot terakhir", "Harga beli kembali/Kg", "Perkiraan nilai beli kembali", "Pilihan", "Dicatat", "Ubah"].map((h) => <th key={h} scope="col" className={th}>{h}</th>)}</tr></thead>
          <tbody>
            {rows.map((o) => (
              <tr key={o.id} className="border-b border-line last:border-0">
                <td className={td}>{o.cow_no}</td><td className={td}>{o.customer_nick}</td>
                <td className={`${td} text-right tabular-nums`}>{kg(o.last_weight)}</td>
                <td className={`${td} text-right tabular-nums`}>{rp(o.buyback_price)}</td>
                <td className={`${td} text-right tabular-nums`}>{rp(o.last_weight * o.buyback_price)}</td>
                <td className={td}>{o.owner_choice ? CHOICE_LABEL[o.owner_choice] : "Belum dipilih"}</td>
                <td className={td}>{tgl(o.choice_date)}</td>
                <td className={td}>
                  {canEdit && (
                    <QForm action={setChoice.bind(null, o.id)} label="Simpan" inline>
                      <select name="choice" defaultValue={o.owner_choice ?? "SELF"} className={fieldCls} aria-label="Pilihan pemilik">
                        {Object.entries(CHOICE_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                      </select>
                    </QForm>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </Table>
      )}
    </div>
  );
}
