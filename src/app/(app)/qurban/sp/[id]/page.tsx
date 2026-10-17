import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { Forbidden } from "@/components/forbidden";
import { getBuyer, getOrder } from "@/lib/qurban/data";
import { spDoc } from "@/lib/qurban/docs";
import { todayIso } from "@/lib/qurban/format";
import { Card, Head } from "@/components/qurban/ui";
import { Field, QForm, fieldCls } from "@/components/qurban/qform";
import { SpPaper } from "@/components/qurban/sp-paper";
import { saveSp } from "../../actions";

export default async function SpDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await requireSession();
  if (!session.can("qurban", "create") && !session.can("qurban", "edit")) return <Forbidden roleName={session.roleName} what="Surat Perjanjian" />;
  const o = await getOrder(id);
  if (!o) notFound();
  const b = await getBuyer(id);
  const canExport = session.can("qurban", "export");
  const docs = b ? await spDoc(o, b) : null;

  return (
    <div className="space-y-6">
      <Link href="/qurban/sp" className="text-muted underline">← Surat Perjanjian</Link>
      <Head title={`Surat Perjanjian · Sapi ${o.cow_no} (${o.customer_nick})`} hint={o.status === "PAID" ? "Isi data pembeli. Nomor surat dibuat sekali saat pertama disimpan dan tidak berubah bila data diperbaiki." : "Surat perjanjian baru bisa dibuat setelah invoice lunas."} />
      {o.status === "PAID" && (
        <Card title="Data pembeli">
          <QForm action={saveSp.bind(null, id)} label={b ? "Simpan perubahan" : "Simpan dan buat surat"}>
            <div className="grid max-w-3xl gap-4 sm:grid-cols-2">
              <Field id="name" label="Nama lengkap"><input id="name" name="name" defaultValue={b?.full_name ?? ""} className={fieldCls} /></Field>
              <Field id="nik" label="No. KTP (16 angka)"><input id="nik" name="nik" inputMode="numeric" maxLength={16} defaultValue={b?.nik ?? ""} className={fieldCls} /></Field>
              <div className="sm:col-span-2"><Field id="addr" label="Alamat"><textarea id="addr" name="addr" rows={2} defaultValue={b?.address ?? ""} className={fieldCls} /></Field></div>
              <Field id="phone" label="No. telepon"><input id="phone" name="phone" inputMode="tel" defaultValue={b?.phone ?? ""} className={fieldCls} /></Field>
              <Field id="type" label="Jenis sapi" hint="Contoh: Limousin, Simental, Brahman."><input id="type" name="type" defaultValue={b?.cow_type ?? ""} className={fieldCls} /></Field>
              <Field id="date" label="Tanggal surat"><input id="date" name="date" type="date" defaultValue={b?.sp_date ?? todayIso()} className={fieldCls} /></Field>
            </div>
          </QForm>
        </Card>
      )}
      {b && docs && (
        <>
          <div className="flex flex-wrap gap-3">
            {canExport && <a href={`/qurban/export/spjb/${id}`} className="rounded-md bg-brand px-6 py-3 text-lg font-semibold text-white">Unduh {b.sp_jb_no} (Word)</a>}
            {canExport && <a href={`/qurban/export/sppl/${id}`} className="rounded-md bg-brand px-6 py-3 text-lg font-semibold text-white">Unduh {b.sp_pl_no} (Word)</a>}
          </div>
          <SpPaper jb={docs.jb} pl={docs.pl} />
        </>
      )}
    </div>
  );
}
