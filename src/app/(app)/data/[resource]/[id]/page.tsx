import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { RESOURCES } from "@/lib/master/config";
import { loadRefs } from "@/lib/master/refs";
import { Forbidden } from "@/components/forbidden";
import { RecordForm } from "@/components/record-form";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function EditRecordPage({ params }: { params: Promise<{ resource: string; id: string }> }) {
  const { resource: key, id } = await params;
  const resource = RESOURCES[key];
  if (!resource || !UUID.test(id)) notFound();

  const session = await requireSession();
  if (!session.can(resource.module, "edit")) {
    return <Forbidden roleName={session.roleName} what={`form ubah ${resource.singular.toLowerCase()}`} />;
  }

  const supabase = await createClient();
  const { data: row } = await supabase.from(resource.table).select("*").eq("id", id).maybeSingle();
  if (!row) notFound();
  const refs = await loadRefs(supabase, resource);

  const initial: Record<string, string> = {};
  for (const f of resource.fields) initial[f.name] = row[f.name] == null ? "" : String(row[f.name]);

  return (
    <div>
      <h1 className="mb-6 text-3xl font-bold">Ubah {resource.singular.toLowerCase()}</h1>
      <RecordForm resource={resource} refs={refs} id={id} initial={initial} />
    </div>
  );
}
