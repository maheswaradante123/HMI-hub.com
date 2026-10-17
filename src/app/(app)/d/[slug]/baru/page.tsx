import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { DocForm } from "@/components/doc-form";
import { CONFIGS } from "@/lib/docs/config";
import { loadDocRefs } from "@/lib/docs/refs";
import { loadPrefill } from "@/lib/docs/prefill";
import { RoForm } from "@/components/ro-form";
import { loadRoLists } from "@/lib/docs/ro-lists";
import { todayJakarta } from "@/lib/pricing/data";

export default async function NewDocPage({
  params, searchParams,
}: {
  params: Promise<{ slug: string }>;
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const { slug } = await params;
  const sp = await searchParams;
  const cfg = CONFIGS[slug];
  if (!cfg) notFound();
  const session = await requireSession();
  if (!session.can(cfg.module, "create")) return <Forbidden roleName={session.roleName} what={`pembuatan ${cfg.singular}`} />;

  const supabase = await createClient();
  const pre = await loadPrefill(supabase, cfg, sp);
  const keep = [...Object.values(pre.header), ...Object.values(pre.children).flat().flatMap((r) => Object.values(r))];
  const fields = [...cfg.header, ...cfg.children.flatMap((c) => c.fields)];
  const refs = await loadDocRefs(supabase, fields, keep);

  const header = Object.fromEntries(cfg.header.map((f) => [f.name, pre.header[f.name] ?? (f.today ? todayJakarta() : "")]));
  const children = Object.fromEntries(cfg.children.map((c) => [c.key, pre.children[c.key] ?? (c.required ? [Object.fromEntries(c.fields.map((f) => [f.name, ""]))] : [])]));

  if (slug === "ro") {
    const lists = await loadRoLists(supabase);
    const items = (pre.children.items ?? []) as Record<string, string>[];
    return (
      <div>
        <p className="text-sm text-muted"><Link href="/d/ro" className="underline">Order / RO</Link> › Baru</p>
        <h1 className="text-3xl font-bold">Request Order Baru</h1>
        <p className="mb-6 mt-1 text-muted">Nomor dibuat otomatis: RO-KODE CUSTOMER-URUT-BULAN-TAHUN.</p>
        <RoForm id="" initial={{ header: header as Record<string, string>, items }} {...lists} createdBy={session.fullName} number="Otomatis saat disimpan" cancelHref="/d/ro" />
      </div>
    );
  }

  return (
    <div>
      <h1 className="mb-6 text-3xl font-bold">{cfg.singular} baru</h1>
      <DocForm slug={slug} id="" header={cfg.header} lines={cfg.children} refs={refs} initial={{ header, children }} cancelHref={`/d/${slug}`} />
    </div>
  );
}
