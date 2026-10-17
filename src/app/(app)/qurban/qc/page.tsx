import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { Forbidden } from "@/components/forbidden";
import { listOrders, listQc } from "@/lib/qurban/data";
import { bulan, todayIso } from "@/lib/qurban/format";
import { PdfPreview } from "@/components/qurban/pdf-preview";
import { Card, Empty, Head, Table, td, th } from "@/components/qurban/ui";
import { Field, QForm, fieldCls } from "@/components/qurban/qform";
import { createQc } from "../actions";

export default async function QcPage() {
  const session = await requireSession();
  if (!session.can("qc_report", "view")) return <Forbidden roleName={session.roleName} what="QC Report Qurban" />;
  const [reports, orders] = await Promise.all([listQc(), listOrders().catch(() => [])]);
  const nicks = [...new Set(orders.filter((o) => o.status === "INVOICE" || o.status === "PAID").map((o) => o.customer_nick))].sort();
  const canExport = session.can("qc_report", "export") || session.can("qc_report", "create");
  return (
    <div>
      <Head title="QC Report" hint="Satu laporan per pelanggan per bulan, memuat semua sapi pelanggan itu dan hasil penimbangannya." />
      {session.can("qc_report", "create") && (
        <Card title="Buat laporan bulan ini" className="mt-6">
          {nicks.length === 0 ? <p className="text-muted">Belum ada pelanggan dengan invoice terbit.</p> : (
            <QForm action={createQc} label="Buat QC Report" inline>
              <Field id="ym" label="Bulan"><input id="ym" name="ym" type="month" defaultValue={todayIso().slice(0, 7)} className={fieldCls} /></Field>
              <Field id="nick" label="Pelanggan">
                <select id="nick" name="nick" className={fieldCls}>{nicks.map((n) => <option key={n} value={n}>{n}</option>)}</select>
              </Field>
            </QForm>
          )}
        </Card>
      )}
      {reports.length === 0 ? <Empty>Belum ada QC Report.</Empty> : (
        <Table>
          <thead className="border-b border-line"><tr>{["Nomor", "Bulan", "Pelanggan", "Publish", "Unduh"].map((h) => <th key={h} scope="col" className={th}>{h}</th>)}</tr></thead>
          <tbody>
            {reports.map((q) => (
              <tr key={q.id} className="border-b border-line last:border-0">
                <td className={td}><Link href={`/qurban/qc/${q.id}`} className="font-semibold text-brand underline">{q.qc_no}</Link></td>
                <td className={td}>{bulan(q.ym)}</td><td className={td}>{q.customer_nick}</td><td className={td}>{q.publish_date.split("-").reverse().join("-")}</td>
                <td className={td}>{canExport ? <span className="flex items-center gap-3 whitespace-nowrap"><PdfPreview href={`/qurban/export/qc/${q.id}`} title={`Pratinjau ${q.qc_no}`} xlsx={`/qurban/export/qc/${q.id}`} /><a href={`/qurban/export/qc/${q.id}?format=pdf`} className="font-semibold underline">PDF</a><a href={`/qurban/export/qc/${q.id}`} className="font-semibold underline">Excel</a></span> : ""}</td>
              </tr>
            ))}
          </tbody>
        </Table>
      )}
    </div>
  );
}
