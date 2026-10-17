import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { PrForm } from "@/components/pr-form";
import { loadFormOptions } from "@/lib/pr/data";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function EditPrPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID.test(id)) notFound();
  const session = await requireSession();
  const supabase = await createClient();

  const { data: pr } = await supabase
    .from("purchase_requests")
    .select("id, reason, priority, status, requester_id, deleted_at, pr_items(line_no, product_id, item_name, qty, unit_id, estimated_price, notes)")
    .eq("id", id)
    .maybeSingle();
  if (!pr || pr.deleted_at) notFound();

  if (pr.status !== "DRAFT" || pr.requester_id !== session.userId) {
    return (
      <div className="max-w-2xl">
        <h1 className="text-3xl font-bold">PR tidak dapat diubah</h1>
        <p className="mt-3 rounded-md bg-warn-bg px-4 py-3">
          Hanya pembuat PR yang boleh mengubah, dan hanya selama statusnya masih Draf.
        </p>
        <Link href={`/purchase-request/${id}`} className="mt-4 inline-block underline">Kembali ke PR</Link>
      </div>
    );
  }

  const { products, units } = await loadFormOptions(supabase);
  const items = [...(pr.pr_items ?? [])].sort((a, b) => a.line_no - b.line_no);
  return (
    <div>
      <h1 className="mb-6 text-3xl font-bold">Ubah draf Purchase Request</h1>
      <PrForm
        id={id}
        products={products}
        units={units}
        initial={{
          reason: pr.reason,
          priority: pr.priority,
          rows: items.map((i) => ({
            product_id: i.product_id ?? "",
            item_name: i.item_name,
            qty: String(Number(i.qty)),
            unit_id: i.unit_id,
            estimated_price: i.estimated_price == null ? "" : String(Number(i.estimated_price)),
            notes: i.notes ?? "",
          })),
        }}
      />
    </div>
  );
}
