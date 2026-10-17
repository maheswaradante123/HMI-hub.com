import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { TaxForm } from "@/components/tax-form";

export default async function TaxPage() {
  const session = await requireSession();
  if (!session.can("master_data", "view")) return <Forbidden roleName={session.roleName} what="Pengaturan Pajak" />;
  const supabase = await createClient();
  const { data } = await supabase.from("tax_settings").select("label, rate").maybeSingle();
  const canEdit = session.can("master_data", "edit");
  return (
    <div>
      <h1 className="text-3xl font-bold">Pengaturan Pajak</h1>
      <p className="mt-1 max-w-3xl text-muted">Tarif ini dipakai untuk invoice yang masih draf. Invoice yang sudah terbit tidak berubah. Isi 0 jika belum memakai pajak.</p>
      <div className="mt-6">
        {canEdit
          ? <TaxForm label={data?.label ?? "PPN"} rate={String(data?.rate ?? 0).replace(".", ",")} />
          : <p className="rounded-md border border-line bg-surface px-4 py-3 text-lg">{data?.label}: {String(data?.rate ?? 0).replace(".", ",")}%</p>}
      </div>
    </div>
  );
}
