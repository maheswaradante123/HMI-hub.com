import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { Forbidden } from "@/components/forbidden";
import { getLines, getOrder, listBills, listWeighings } from "@/lib/qurban/data";
import { CHOICE_LABEL, MODE_LABEL, bulan, kg, rp, tgl, todayIso } from "@/lib/qurban/format";
import { Card, Dl, Pill, td, th } from "@/components/qurban/ui";
import { Field, QForm, fieldCls } from "@/components/qurban/qform";
import {
  addWeighing, cancelOrder, createBill, issueInvoice, markBillPaid, markPaid, setDiscount,
} from "../actions";

const dl = "rounded-md border-2 border-line px-5 py-2.5 text-lg font-semibold hover:bg-background";

export default async function DetailPesanan({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await requireSession();
  if (!session.can("qurban", "view") && !session.can("qc_report", "view")) return <Forbidden roleName={session.roleName} what="Qurban Cerdas" />;
  const o = await getOrder(id);
  if (!o) notFound();
  const [lines, weighings, bills] = await Promise.all([getLines(id), listWeighings([id]), listBills(id)]);
  const full = session.can("qurban", "view");
  const total = lines.reduce((s, l) => s + l.qty * l.price, 0);
  const open = o.status === "PROFORMA" || o.status === "INVOICE";
  const canExport = session.can("qurban", "export");

  return (
    <div className="space-y-6">
      <div>
        <Link href="/qurban" className="text-muted underline">← Master Pesanan</Link>
        <div className="mt-2 flex flex-wrap items-center gap-3">
          <h1 className="text-3xl font-bold">Sapi {o.cow_no} · {o.customer_nick}</h1>
          <Pill status={o.status} />
        </div>
      </div>

      {full && (
        <>
          <Card title="Ringkasan">
            <Dl rows={[
              ["Pelanggan", o.customer_nick], ["Nomor sapi", o.cow_no], ["Mulai pemeliharaan", tgl(o.start_date)],
              ["Bobot awal", kg(o.initial_weight)], ["Bobot terakhir", kg(o.last_weight)],
              ["Kelas harga", `${o.class_min}${o.class_max ? `–${o.class_max}` : "+"} Kg`],
              ["Harga beli", `${rp(o.buy_price)} / Kg`], ["Perawatan", `${rp(o.care_price)} / hari`],
              ["Beli kembali", `${rp(o.buyback_price)} / Kg`], ["Cara bayar perawatan", MODE_LABEL[o.pay_mode]],
              ["No. Proforma", o.pro_no ?? "-"], ["No. Invoice", o.inv_no ?? "-"],
              ["Jatuh tempo invoice", tgl(o.due_date)], ["Pilihan pemilik", o.owner_choice ? CHOICE_LABEL[o.owner_choice] : "Belum dipilih"],
              ...(o.cancel_reason ? [["Alasan batal", o.cancel_reason] as [string, string]] : []),
            ]} />
          </Card>

          <Card title="Rincian invoice">
            <div className="overflow-x-auto">
              <table className="w-full text-left text-lg">
                <thead className="border-b border-line"><tr>
                  {["No", "Deskripsi", "Qty", "Satuan", "Harga satuan", "Jumlah"].map((h) => <th key={h} scope="col" className={th}>{h}</th>)}
                </tr></thead>
                <tbody>
                  {lines.map((l) => (
                    <tr key={l.line_no} className="border-b border-line">
                      <td className={td}>{l.line_no}</td><td className={td}>{l.descr}</td>
                      <td className={`${td} text-right tabular-nums`}>{l.qty.toLocaleString("id-ID")}</td><td className={td}>{l.unit}</td>
                      <td className={`${td} text-right tabular-nums`}>{rp(l.price)}</td>
                      <td className={`${td} text-right tabular-nums`}>{rp(l.qty * l.price)}</td>
                    </tr>
                  ))}
                </tbody>
                <tfoot className="text-right font-semibold">
                  <tr><td colSpan={5} className={td}>Total</td><td className={`${td} tabular-nums`}>{rp(total)}</td></tr>
                  <tr><td colSpan={5} className={td}>Diskon</td><td className={`${td} tabular-nums`}>{rp(o.discount)}</td></tr>
                  <tr><td colSpan={5} className={td}>Uang muka</td><td className={`${td} tabular-nums`}>{rp(o.down_payment)}</td></tr>
                  <tr><td colSpan={5} className={td}>Kekurangan</td><td className={`${td} tabular-nums`}>{rp(total - o.discount - o.down_payment)}</td></tr>
                </tfoot>
              </table>
            </div>
          </Card>

          {open && (
            <Card title="Negosiasi dan penerbitan">
              <div className="grid gap-6 md:grid-cols-2">
                {session.can("qurban", "approve") && (
                  <div>
                    <p className="mb-2 text-muted">Diskon hasil negosiasi (hanya Owner).</p>
                    <QForm action={setDiscount.bind(null, id)} label="Simpan diskon" inline>
                      <Field id="amount" label="Diskon (Rp)"><input id="amount" name="amount" inputMode="numeric" defaultValue={String(Math.round(o.discount))} className={fieldCls} /></Field>
                    </QForm>
                  </div>
                )}
                <div className="space-y-4">
                  {o.status === "PROFORMA" && session.can("qurban", "edit") && (
                    <QForm action={issueInvoice.bind(null, id)} label="Terbitkan invoice" />
                  )}
                  {o.status === "INVOICE" && session.can("qurban", "edit") && (
                    <QForm action={markPaid.bind(null, id)} label="Tandai lunas" />
                  )}
                </div>
              </div>
              {session.can("qurban", "delete") && (
                <div className="mt-6 border-t border-line pt-4">
                  <QForm action={cancelOrder.bind(null, id)} label="Batalkan pesanan" danger inline>
                    <Field id="reason" label="Alasan pembatalan (wajib)"><input id="reason" name="reason" className={fieldCls} /></Field>
                  </QForm>
                </div>
              )}
            </Card>
          )}

          {o.pay_mode === "MONTHLY" && (o.status === "PAID" || bills.length > 0) && (
            <Card title="Tagihan bulanan">
              {bills.length === 0 ? <p className="text-muted">Belum ada tagihan bulanan.</p> : (
                <div className="overflow-x-auto">
                  <table className="w-full text-left text-lg">
                    <thead className="border-b border-line"><tr>
                      {["No. Tagihan", "Bulan", "Hari", "Tarif/hari", "Jumlah", "Jatuh tempo", "Status", ""].map((h, i) => <th key={i} scope="col" className={th}>{h}</th>)}
                    </tr></thead>
                    <tbody>
                      {bills.map((b) => (
                        <tr key={b.id} className="border-b border-line">
                          <td className={td}>{b.bill_no}</td><td className={td}>{bulan(b.ym)}</td>
                          <td className={`${td} text-right`}>{b.days}</td><td className={`${td} text-right tabular-nums`}>{rp(b.rate)}</td>
                          <td className={`${td} text-right tabular-nums`}>{rp(b.days * b.rate)}</td><td className={td}>{tgl(b.due_date)}</td>
                          <td className={td}><Pill status={b.status} /></td>
                          <td className={`${td} space-y-2`}>
                            {canExport && <span className="space-x-3"><a href={`/qurban/export/bill/${b.id}?format=pdf`} className="font-semibold underline">PDF</a><a href={`/qurban/export/bill/${b.id}`} className="font-semibold underline">Excel</a></span>}
                            {b.status === "ISSUED" && session.can("qurban", "edit") && (
                              <QForm action={markBillPaid.bind(null, b.id)} label="Tandai lunas" />
                            )}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
              {o.status === "PAID" && session.can("qurban", "create") && (
                <div className="mt-4"><QForm action={createBill.bind(null, id)} label="Buat tagihan bulan berikutnya" /></div>
              )}
              <p className="mt-3 text-sm text-muted">Tarif tiap bulan mengikuti kelas bobot timbang terakhir sebelum bulan itu.</p>
            </Card>
          )}
        </>
      )}

      <Card title="Penimbangan">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-lg">
            <thead className="border-b border-line"><tr>{["Tanggal", "Bobot", "Catatan"].map((h) => <th key={h} scope="col" className={th}>{h}</th>)}</tr></thead>
            <tbody>
              {weighings.map((w) => (
                <tr key={w.id} className="border-b border-line last:border-0">
                  <td className={td}>{tgl(w.weigh_date)}</td><td className={`${td} tabular-nums`}>{kg(w.weight)}</td><td className={td}>{w.note ?? ""}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {o.status !== "CANCELLED" && session.can("qc_report", "create") && (
          <div className="mt-4 border-t border-line pt-4">
            <QForm action={addWeighing.bind(null, id)} label="Catat penimbangan" inline>
              <Field id="date" label="Tanggal timbang"><input id="date" name="date" type="date" defaultValue={todayIso()} className={fieldCls} /></Field>
              <Field id="weight" label="Bobot (Kg)"><input id="weight" name="weight" inputMode="decimal" className={fieldCls} /></Field>
              <Field id="note" label="Catatan (boleh kosong)"><input id="note" name="note" className={fieldCls} /></Field>
            </QForm>
          </div>
        )}
      </Card>

      {full && o.status !== "CANCELLED" && (
        <Card title="Dokumen">
          <div className="flex flex-wrap gap-3">
            {canExport && <a href={`/qurban/export/proforma/${id}?format=pdf`} className={dl}>Unduh Proforma (PDF)</a>}
            {canExport && <a href={`/qurban/export/proforma/${id}`} className={dl}>Proforma (Excel)</a>}
            {canExport && o.inv_no && <a href={`/qurban/export/invoice/${id}?format=pdf`} className={dl}>Unduh Invoice (PDF)</a>}
            {canExport && o.inv_no && <a href={`/qurban/export/invoice/${id}`} className={dl}>Invoice (Excel)</a>}
            {o.status === "PAID" && <Link href={`/qurban/sp/${id}`} className={dl}>Surat Perjanjian</Link>}
            {o.status === "PAID" && <Link href="/qurban/pilihan" className={dl}>Pilihan Pemilik</Link>}
          </div>
        </Card>
      )}
    </div>
  );
}
