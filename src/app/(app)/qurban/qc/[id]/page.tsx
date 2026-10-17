import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { Forbidden } from "@/components/forbidden";
import { createClient } from "@/lib/supabase/server";
import { qcDoc } from "@/lib/qurban/docs";
import type { Qc } from "@/lib/qurban/data";
import { bulan, tgl } from "@/lib/qurban/format";
import { PdfPreview } from "@/components/qurban/pdf-preview";
import { Card, td, th } from "@/components/qurban/ui";

export default async function QcDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await requireSession();
  if (!session.can("qc_report", "view")) return <Forbidden roleName={session.roleName} what="QC Report Qurban" />;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const supabase = await createClient();
  const { data } = await supabase.from("qurban_qc_reports").select("*").eq("id", id).maybeSingle();
  if (!data) notFound();
  const q = data as Qc;
  const doc = await qcDoc(q);
  const canExport = session.can("qc_report", "export") || session.can("qc_report", "create");
  const dd = (a: string, b: string) => Math.round((Date.parse(b) - Date.parse(a)) / 864e5);

  return (
    <div className="space-y-6">
      <div>
        <Link href="/qurban/qc" className="text-muted underline">← QC Report</Link>
        <h1 className="mt-2 text-3xl font-bold">{q.qc_no}</h1>
        <p className="text-muted">{q.customer_nick} · {bulan(q.ym)} · publish {tgl(q.publish_date)}</p>
      </div>
      {canExport && <div className="flex flex-wrap items-center gap-3"><PdfPreview href={`/qurban/export/qc/${q.id}`} title={`Pratinjau ${q.qc_no}`} xlsx={`/qurban/export/qc/${q.id}`} /><a href={`/qurban/export/qc/${q.id}?format=pdf`} className="rounded-full bg-brand px-5 py-2 font-semibold text-white">Unduh PDF</a><a href={`/qurban/export/qc/${q.id}`} className="rounded-full border border-line px-5 py-2 font-semibold">Unduh Excel</a></div>}
      <Card title="Isi laporan">
        {doc.sapi.length === 0 ? <p className="text-muted">Belum ada sapi pada bulan ini.</p> : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-lg">
              <thead className="border-b border-line"><tr>{["No", "Nomor sapi", "Bobot awal", "Penimbangan", "Bobot", "Perkembangan", "ADG"].map((h) => <th key={h} scope="col" className={th}>{h}</th>)}</tr></thead>
              <tbody>
                {doc.sapi.flatMap((s, i) => {
                  let pb = s.bobotAwal, pt = s.tglAwal;
                  if (s.timbang.length === 0) {
                    return [<tr key={i} className="border-b border-line"><td className={td}>{i + 1}</td><td className={td}>{s.nomor}</td><td className={td}>{s.bobotAwal} Kg</td><td className={`${td} text-muted`} colSpan={4}>Belum ada penimbangan lanjutan</td></tr>];
                  }
                  return s.timbang.map((t, k) => {
                    const g = t.bobot - pb, d = dd(pt, t.tgl), adg = d > 0 ? (g / d).toFixed(2) : "0.00";
                    pb = t.bobot; pt = t.tgl;
                    return (
                      <tr key={`${i}-${k}`} className="border-b border-line">
                        <td className={td}>{k === 0 ? i + 1 : ""}</td><td className={td}>{k === 0 ? s.nomor : ""}</td><td className={td}>{k === 0 ? `${s.bobotAwal} Kg` : ""}</td>
                        <td className={td}>{tgl(t.tgl)}</td><td className={`${td} tabular-nums`}>{t.bobot} Kg</td><td className={`${td} tabular-nums`}>{g.toFixed(1)} Kg</td><td className={`${td} tabular-nums`}>{adg}</td>
                      </tr>
                    );
                  });
                })}
              </tbody>
            </table>
          </div>
        )}
        <p className="mt-4"><b>Catatan:</b> {q.note}</p>
        <p className="mt-1 text-muted">PPIC: {q.ppic_name} · Quality Control: {q.qc_name} · Dir. Operasional: {q.director_name}</p>
      </Card>
    </div>
  );
}
