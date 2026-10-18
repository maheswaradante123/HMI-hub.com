import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { PrForm } from "@/components/pr-form";
import { defaultAc, weekLabel } from "@/lib/pr/lines";
import { todayJakarta } from "@/lib/pricing/data";

export default async function NewPrPage() {
  const session = await requireSession();
  if (!session.can("purchase_request", "create")) {
    return <Forbidden roleName={session.roleName} what="form Purchase Request" />;
  }
  const today = todayJakarta();
  // Nomor lembar minggu ini dihitung di database; di sini hanya untuk teks dan penanda apakah lembarnya sudah ada.
  const supabase = await createClient();
  const { data: no } = await supabase.rpc("pr_sheet_number", { p_date: today });
  const { data: sheet } = no ? await supabase.from("purchase_requests").select("id").eq("doc_number", String(no)).is("deleted_at", null).maybeSingle() : { data: null };
  return (
    <div>
      <p className="text-sm text-muted">Purchase Request › Tambah barang</p>
      <h1 className="mb-1 text-3xl font-bold">Tambah Barang ke PR Minggu Ini</h1>
      <p className="mb-6 text-muted">{String(no ?? "")} · {weekLabel(today)} · diminta oleh {session.fullName}</p>
      <PrForm defaultAc={defaultAc(session.roleName)} weekText={`(${weekLabel(today)}).`} existing={!!sheet} />
    </div>
  );
}
