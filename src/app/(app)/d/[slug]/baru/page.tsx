import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { DocForm } from "@/components/doc-form";
import { CONFIGS } from "@/lib/docs/config";
import { loadDocRefs } from "@/lib/docs/refs";
import { loadPrefill } from "@/lib/docs/prefill";
import { PlForm } from "@/components/pl-form";
import { PoForm } from "@/components/po-form";
import { RoForm } from "@/components/ro-form";
import { loadPlRos, loadPoRos, loadRoLists, loadWarehouses } from "@/lib/docs/ro-lists";
import { fmtDate } from "@/lib/docs/format";
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

  if (slug === "prod") {
    const [ros, lists] = await Promise.all([loadPoRos(supabase), loadRoLists(supabase)]);
    const ro = ros.find((r) => r.id === pre.header.ro_id);
    const today = todayJakarta();
    const initial = {
      header: { ro_id: ro?.id ?? "", order_date: today, needed_date: ro?.sendDate ?? "", delivery_address: ro?.address ?? "", send_note: ro ? `${fmtDate(ro.sendDate)} ${ro.sendTime}`.trim() : "", pic: "", cow_codes: "", notes: "" } as Record<string, string>,
      items: (ro?.items ?? []).map((i) => ({ product_id: i.product_id, ro_product_id: i.product_id, qty: i.qty, cut_type: i.cut, packaging: i.pack, notes: "" })),
    };
    return (
      <div>
        <p className="text-sm text-muted"><Link href="/d/prod" className="underline">Production Order</Link> › Baru</p>
        <h1 className="text-3xl font-bold">Production Order Baru</h1>
        <p className="mb-6 mt-1 text-muted">Publish date = hari ini. Detail pesanan ditarik dari RO; nama produk boleh diganti.</p>
        <PoForm id="" initial={initial} ros={ros} products={lists.products} today={today} number="" cancelHref="/d/prod" />
      </div>
    );
  }

  if (slug === "pl") {
    const [ros, lists, warehouses] = await Promise.all([loadPlRos(supabase, pre.header.ro_id), loadRoLists(supabase), loadWarehouses(supabase)]);
    const seen = new Set<string>();
    const rows = (pre.children.items ?? []).filter((r) => r.product_id && !seen.has(r.product_id) && seen.add(r.product_id))
      .map((r) => ({ product_id: r.product_id, qty: "", gross_weight: "", notes: "" }));
    const initial = {
      header: { ro_id: pre.header.ro_id ?? "", customer_id: pre.header.customer_id ?? "", po_id: pre.header.po_id ?? "", pack_date: todayJakarta(), phone: ros.find((r) => r.id === pre.header.ro_id)?.phone ?? "", warehouse_id: warehouses.length === 1 ? warehouses[0].id : "", supervisor: "", notes: "" } as Record<string, string>,
      items: rows,
    };
    return (
      <div>
        <p className="text-sm text-muted"><Link href="/d/pl" className="underline">Packing List</Link> › Baru</p>
        <h1 className="text-3xl font-bold">Packing List Baru</h1>
        <p className="mb-6 mt-1 text-muted">Isi manual per baris, atau gunakan tombol tambah / tempel dari Excel.</p>
        <PlForm id="" initial={initial} ros={ros} products={lists.products} warehouses={warehouses} number="" cancelHref="/d/pl" />
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
