import "server-only";
import type { createClient } from "@/lib/supabase/server";
import type { DocConfig } from "./types";

type Supa = Awaited<ReturnType<typeof createClient>>;
type Row = Record<string, string>;
export type Prefill = { header: Row; children: Record<string, Row[]> };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const s = (v: unknown) => (v === null || v === undefined ? "" : String(v));

// Mengisi form baru dari dokumen sebelumnya (RO -> Production Order -> Packing List -> Invoice, dst).
export async function loadPrefill(supabase: Supa, cfg: DocConfig, sp: Record<string, string | undefined>): Promise<Prefill> {
  const out: Prefill = { header: {}, children: {} };
  const take = (k: string) => (sp[k] && UUID.test(sp[k]!) ? sp[k]! : null);

  if (cfg.type === "PROD" && take("ro")) {
    const id = take("ro")!;
    const { data } = await supabase.from("request_orders").select("id, ro_items(product_id, qty, line_no)").eq("id", id).maybeSingle();
    if (data) {
      out.header = { ro_id: id };
      out.children.items = [...(data.ro_items ?? [])].sort((a, b) => a.line_no - b.line_no).map((i) => ({ product_id: s(i.product_id), qty: s(i.qty), notes: "" }));
    }
  } else if (cfg.type === "PL" && (take("po") || take("ro"))) {
    if (take("po")) {
      const { data } = await supabase.from("production_orders").select("id, ro_id, request_orders(customer_id), po_items(product_id, qty, line_no)").eq("id", take("po")!).maybeSingle();
      if (data) {
        const ro = Array.isArray(data.request_orders) ? data.request_orders[0] : data.request_orders;
        out.header = { po_id: data.id, ro_id: s(data.ro_id), customer_id: s(ro?.customer_id) };
        out.children.items = [...(data.po_items ?? [])].sort((a, b) => a.line_no - b.line_no).map((i) => ({ product_id: s(i.product_id), qty: s(i.qty), notes: "" }));
      }
    } else {
      const { data } = await supabase.from("request_orders").select("id, customer_id, ro_items(product_id, qty, line_no)").eq("id", take("ro")!).maybeSingle();
      if (data) {
        out.header = { ro_id: data.id, customer_id: s(data.customer_id) };
        out.children.items = [...(data.ro_items ?? [])].sort((a, b) => a.line_no - b.line_no).map((i) => ({ product_id: s(i.product_id), qty: s(i.qty), notes: "" }));
      }
    }
  } else if (cfg.type === "INV" && take("pl")) {
    const { data } = await supabase.from("packing_lists").select("id, ro_id, customer_id, pl_items(product_id, qty, line_no)").eq("id", take("pl")!).maybeSingle();
    if (data) {
      // Jika packing list berasal dari RO, harga mengikuti harga yang sudah disepakati di RO.
      const roPrice = new Map<string, number>();
      if (data.ro_id) {
        const { data: ro } = await supabase.from("ro_items").select("product_id, unit_price").eq("ro_id", data.ro_id);
        for (const r of ro ?? []) roPrice.set(r.product_id as string, Number(r.unit_price));
      }
      const money = (n: number) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ".");
      out.header = { pl_id: data.id, ro_id: s(data.ro_id), customer_id: s(data.customer_id) };
      // Satu produk bisa terdiri dari banyak kemasan: jumlahkan per produk.
      const sums = new Map<string, number>();
      for (const i of [...(data.pl_items ?? [])].sort((a, b) => a.line_no - b.line_no)) {
        sums.set(i.product_id as string, Math.round(((sums.get(i.product_id as string) ?? 0) + Number(i.qty)) * 1000) / 1000);
      }
      out.children.items = [...sums.entries()].map(([pid, qty]) => {
        const p = roPrice.get(pid);
        return { product_id: pid, qty: String(qty).replace(".", ","), unit_price: p ? money(p) : "" };
      });
    }
  } else if (cfg.type === "DO" && take("pl")) {
    const { data } = await supabase.from("packing_lists").select("id, driver_name, vehicle_plate, request_orders(delivery_address)").eq("id", take("pl")!).maybeSingle();
    if (data) {
      const ro = Array.isArray(data.request_orders) ? data.request_orders[0] : data.request_orders;
      out.header = { pl_id: data.id, driver_name: s(data.driver_name), vehicle_plate: s(data.vehicle_plate), delivery_address: s(ro?.delivery_address) };
    }
  } else if (cfg.type === "NCS" && take("cw")) {
    const id = take("cw")!;
    const { data: cw } = await supabase.from("carcass_weighings").select("id, cw_items(non_carcass_type_id, weight, line_no)").eq("id", id).maybeSingle();
    if (cw) {
      out.header = { cw_id: id };
      out.children.items = [...(cw.cw_items ?? [])].filter((i) => i.non_carcass_type_id).sort((a, b) => a.line_no - b.line_no).map((i) => ({ non_carcass_type_id: s(i.non_carcass_type_id), weight: s(i.weight), unit_price: "" }));
    }
  } else if (cfg.type === "CRJ" && (take("inv") || take("ncs"))) {
    if (take("inv")) {
      const { data } = await supabase.from("invoices").select("id, customer_id, total, paid_amount").eq("id", take("inv")!).maybeSingle();
      if (data) {
        const left = Number(data.total) - Number(data.paid_amount);
        const m = String(left).replace(/\B(?=(\d{3})+(?!\d))/g, ".");
        out.header = { customer_id: data.customer_id, amount: m };
        out.children.items = [{ invoice_id: data.id, ncs_id: "", amount: m }];
      }
    } else {
      const { data } = await supabase.from("noncarcass_sales").select("id, customer_id, total_amount, paid_amount").eq("id", take("ncs")!).maybeSingle();
      if (data) {
        const m = String(Number(data.total_amount) - Number(data.paid_amount)).replace(/\B(?=(\d{3})+(?!\d))/g, ".");
        out.header = { customer_id: data.customer_id, amount: m };
        out.children.items = [{ invoice_id: "", ncs_id: data.id, amount: m }];
      }
    }
  } else if (cfg.type === "CPJ" && take("pr")) {
    out.header = { pr_id: take("pr")! };
  }
  return out;
}
