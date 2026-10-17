import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { RESOURCES } from "@/lib/master/config";
import { loadRefs } from "@/lib/master/refs";
import { Forbidden } from "@/components/forbidden";
import { RecordForm } from "@/components/record-form";

export default async function NewRecordPage({ params }: { params: Promise<{ resource: string }> }) {
  const { resource: key } = await params;
  const resource = RESOURCES[key];
  if (!resource) notFound();

  const session = await requireSession();
  if (!session.can(resource.module, "create")) {
    return <Forbidden roleName={session.roleName} what={`form tambah ${resource.singular.toLowerCase()}`} />;
  }
  const refs = await loadRefs(await createClient(), resource);

  return (
    <div>
      <h1 className="mb-6 text-3xl font-bold">Tambah {resource.singular.toLowerCase()}</h1>
      <RecordForm resource={resource} refs={refs} id={null} initial={{}} />
    </div>
  );
}
