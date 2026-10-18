import "server-only";
import type { createClient } from "@/lib/supabase/server";
import type { RoCustomer, RoProduct } from "@/components/ro-form";

export async function loadRoLists(supabase: Awaited<ReturnType<typeof createClient>>): Promise<{ customers: RoCustomer[]; products: RoProduct[]; units: { id: string; name: string }[]; categories: { id: string; name: string }[] }> {
  const [c, p, u, k] = await Promise.all([
    supabase.from("customers").select("id, code, name, phone, address, payment_term_days").eq("is_active", true).order("name"),
    supabase.from("products").select("id, code, name, units(name)").eq("is_active", true).order("name"),
    supabase.from("units").select("id, name").eq("is_active", true).order("name"),
    supabase.from("product_categories").select("id, name").eq("is_active", true).order("name"),
  ]);
  return {
    units: (u.data ?? []).map((r) => ({ id: r.id, name: r.name })),
    categories: (k.data ?? []).map((r) => ({ id: r.id, name: r.name })),
    customers: (c.data ?? []).map((r) => ({ id: r.id, code: r.code, name: r.name, phone: r.phone ?? "", address: r.address ?? "", term: r.payment_term_days ?? 0 })),
    products: (p.data ?? []).map((r) => ({ id: r.id, code: r.code, name: r.name, unit: (r.units as unknown as { name: string } | null)?.name ?? "" })),
  };
}

export type PoRo = {
  id: string; no: string; customer: string; phone: string; orderDate: string; sendDate: string; sendTime: string;
  ship: string; address: string; poCount: number; activePo: string;
  items: { product_id: string; qty: string; cut: string; pack: string }[];
};

// RO yang sudah dikonfirmasi beserta isinya, untuk form Production Order.
export async function loadPoRos(supabase: Awaited<ReturnType<typeof createClient>>, keepId?: string): Promise<PoRo[]> {
  const q = supabase.from("request_orders")
    .select("id, doc_number, order_date, delivery_date, delivery_time, delivery_method, delivery_address, phone, customers(name), ro_items(product_id, qty, cut_type, packaging, line_no), production_orders(doc_number, status, deleted_at)")
    .is("deleted_at", null).order("doc_number", { ascending: false }).limit(300);
  const { data } = keepId ? await q.or(`status.eq.CONFIRMED,id.eq.${keepId}`) : await q.eq("status", "CONFIRMED");
  return (data ?? []).map((r) => {
    const pos = ((r.production_orders as unknown as { doc_number: string; status: string; deleted_at: string | null }[]) ?? []).filter((p) => !p.deleted_at);
    const act = pos.find((p) => !["REJECTED", "CANCELLED"].includes(p.status));
    const cu = r.customers as unknown as { name: string } | null;
    return {
      id: r.id, no: r.doc_number, customer: cu?.name ?? "", phone: r.phone ?? "", orderDate: r.order_date ?? "", sendDate: r.delivery_date ?? "",
      sendTime: r.delivery_time ?? "", ship: r.delivery_method ?? "", address: r.delivery_address ?? "", poCount: pos.length, activePo: act?.doc_number ?? "",
      items: [...((r.ro_items as unknown as { product_id: string; qty: number; cut_type: string | null; packaging: string | null; line_no: number }[]) ?? [])]
        .sort((a, b) => a.line_no - b.line_no)
        .map((i) => ({ product_id: i.product_id, qty: String(i.qty), cut: i.cut_type ?? "", pack: i.packaging ?? "" })),
    };
  });
}

export type PlRo = { id: string; no: string; customerId: string; customer: string; phone: string };

// RO yang boleh diacu Packing List (dikonfirmasi atau selesai), plus RO yang sudah tersimpan di dokumen.
export async function loadPlRos(supabase: Awaited<ReturnType<typeof createClient>>, keepId?: string): Promise<PlRo[]> {
  const q = supabase.from("request_orders").select("id, doc_number, customer_id, phone, customers(name)")
    .is("deleted_at", null).order("doc_number", { ascending: false }).limit(300);
  const { data } = keepId ? await q.or(`status.in.(CONFIRMED,COMPLETED),id.eq.${keepId}`) : await q.in("status", ["CONFIRMED", "COMPLETED"]);
  return (data ?? []).map((r) => ({
    id: r.id, no: r.doc_number, customerId: r.customer_id, phone: r.phone ?? "",
    customer: (r.customers as unknown as { name: string } | null)?.name ?? "",
  }));
}

export async function loadWarehouses(supabase: Awaited<ReturnType<typeof createClient>>): Promise<{ id: string; name: string }[]> {
  const { data } = await supabase.from("warehouses").select("id, name").eq("is_active", true).order("name");
  return (data ?? []).map((w) => ({ id: w.id, name: w.name }));
}
