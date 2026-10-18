import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { DocForm } from "@/components/doc-form";
import { CONFIGS } from "@/lib/docs/config";
import { PlForm } from "@/components/pl-form";
import { PoForm } from "@/components/po-form";
import { RoForm } from "@/components/ro-form";
import { loadPlRos, loadPoRos, loadRoLists, loadWarehouses } from "@/lib/docs/ro-lists";
import { loadDocRefs } from "@/lib/docs/refs";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const fmtNum = (v: unknown, money: boolean) => {
  if (v === null || v === undefined) return "";
  const s = String(v);
  if (money) return s.replace(/\.00$/, "").replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return s.includes(".") ? s.replace(/0+$/, "").replace(/\.$/, "").replace(".", ",") : s;
};

export default async function EditDocPage({ params }: { params: Promise<{ slug: string; id: string }> }) {
  const { slug, id } = await params;
  const cfg = CONFIGS[slug];
  if (!cfg || !UUID.test(id)) notFound();
  const session = await requireSession();
  if (!session.can(cfg.module, "edit")) return <Forbidden roleName={session.roleName} what={`perubahan ${cfg.singular}`} />;

  const supabase = await createClient();
  const childSel = cfg.children.map((c) => `${c.table}(*)`).join(", ");
  const { data } = await supabase.from(cfg.table).select(`*${childSel ? ", " + childSel : ""}`).eq("id", id).is("deleted_at", null).maybeSingle();
  const doc = data as unknown as Record<string, unknown> | null;
  if (!doc) notFound();
  if (doc.status !== "DRAFT") {
    return (
      <div className="max-w-2xl">
        <h1 className="text-3xl font-bold">Tidak bisa diubah</h1>
        <p className="mt-3 rounded-md bg-warn-bg px-4 py-3">Dokumen ini sudah tidak berstatus draf, jadi isinya terkunci. Jika perlu diperbaiki, batalkan lalu buat dokumen baru.</p>
      </div>
    );
  }

  const header = Object.fromEntries(cfg.header.map((f) => [f.name, f.kind === "money" || f.kind === "qty" ? fmtNum(doc[f.name], f.kind === "money") : String(doc[f.name] ?? "")]));
  const children = Object.fromEntries(cfg.children.map((c) => {
    const rows = ((doc[c.table] as Record<string, unknown>[] | undefined) ?? []).slice().sort((a, b) => Number(a.line_no) - Number(b.line_no));
    return [c.key, rows.map((r) => Object.fromEntries(c.fields.map((f) => [f.name, f.kind === "money" || f.kind === "qty" ? (f.blankAs0 && Number(r[f.name]) === 0 ? "" : fmtNum(r[f.name], f.kind === "money")) : String(r[f.name] ?? "")])))];
  }));
  if (slug === "ro") {
    const lists = await loadRoLists(supabase);
    return (
      <div>
        <h1 className="mb-6 text-3xl font-bold">Ubah RO {String(doc.doc_number)}</h1>
        <RoForm id={id} initial={{ header: header as Record<string, string>, items: children.items ?? [] }} {...lists} createdBy={session.fullName} number={String(doc.doc_number)} cancelHref={`/d/ro/${id}`} />
      </div>
    );
  }
  if (slug === "prod") {
    const [ros, lists] = await Promise.all([loadPoRos(supabase, String(doc.ro_id ?? "")), loadRoLists(supabase)]);
    return (
      <div>
        <h1 className="mb-6 text-3xl font-bold">Ubah Production Order {String(doc.doc_number)}</h1>
        <PoForm id={id} initial={{ header: header as Record<string, string>, items: children.items ?? [] }} ros={ros} products={lists.products} today={String(doc.order_date)} number={String(doc.doc_number)} cancelHref={`/d/prod/${id}`} />
      </div>
    );
  }
  if (slug === "pl") {
    const [ros, lists, warehouses] = await Promise.all([loadPlRos(supabase, String(doc.ro_id ?? "")), loadRoLists(supabase), loadWarehouses(supabase)]);
    return (
      <div>
        <h1 className="mb-6 text-3xl font-bold">Ubah Packing List {String(doc.doc_number)}</h1>
        <PlForm id={id} initial={{ header: header as Record<string, string>, items: children.items ?? [] }} ros={ros} products={lists.products} warehouses={warehouses} number={String(doc.doc_number)} cancelHref={`/d/pl/${id}`} />
      </div>
    );
  }
  const keep = [...Object.values(header), ...Object.values(children).flat().flatMap((r) => Object.values(r))];
  const refs = await loadDocRefs(supabase, [...cfg.header, ...cfg.children.flatMap((c) => c.fields)], keep);

  return (
    <div>
      <h1 className="mb-6 text-3xl font-bold">Ubah {cfg.singular} {String(doc.doc_number)}</h1>
      <DocForm slug={slug} id={id} header={cfg.header} lines={cfg.children} refs={refs} initial={{ header, children }} cancelHref={`/d/${slug}/${id}`} />
    </div>
  );
}
