import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { PrForm } from "@/components/pr-form";
import { loadFormOptions } from "@/lib/pr/data";

export default async function NewPrPage() {
  const session = await requireSession();
  if (!session.can("purchase_request", "create")) {
    return <Forbidden roleName={session.roleName} what="form Purchase Request" />;
  }
  const { products, units } = await loadFormOptions(await createClient());
  return (
    <div>
      <h1 className="mb-6 text-3xl font-bold">Buat Purchase Request</h1>
      <PrForm id={null} products={products} units={units} initial={{ reason: "", priority: "NORMAL", rows: [] }} />
    </div>
  );
}
