import "server-only";
import { createClient } from "@/lib/supabase/server";

export type Order = {
  id: string; cow_no: string; customer_nick: string; start_date: string; initial_weight: number;
  pay_mode: "FULL" | "MONTHLY"; class_min: number; class_max: number | null;
  buy_price: number; care_price: number; buyback_price: number; discount: number; down_payment: number;
  status: "PROFORMA" | "INVOICE" | "PAID" | "CANCELLED";
  pro_no: string | null; pro_date: string | null; inv_no: string | null; inv_date: string | null; due_date: string | null;
  paid_at: string | null; owner_choice: "SELF" | "SELL_OUT" | "SELL_BACK" | null; choice_date: string | null;
  cancel_reason: string | null; total: number; due_amount: number; last_weight: number; bill_count: number;
};
export type Weighing = { id: string; order_id: string; weigh_date: string; weight: number; note: string | null };
export type Bill = {
  id: string; order_id: string; bill_no: string; ym: string; days: number; rate: number;
  basis_weight: number; bill_date: string; due_date: string; status: "ISSUED" | "PAID" | "CANCELLED"; paid_at: string | null;
};
export type Line = { line_no: number; descr: string; qty: number; unit: string; price: number };
export type Qc = {
  id: string; qc_no: string; ym: string; customer_nick: string; publish_date: string; note: string;
  ppic_name: string; qc_name: string; director_name: string;
};
export type Buyer = {
  order_id: string; full_name: string; nik: string; address: string; phone: string | null;
  cow_type: string; sp_date: string; sp_seq: number; sp_jb_no: string; sp_pl_no: string;
};
export type PriceClass = { id: string; min_kg: number; max_kg: number | null; buy_price: number; care_price: number; buyback_price: number; effective_from: string };

const num = <T extends Record<string, unknown>>(o: T, keys: string[]): T => {
  const r: Record<string, unknown> = { ...o };
  for (const k of keys) if (r[k] !== null && r[k] !== undefined) r[k] = Number(r[k]);
  return r as T;
};
const ORDER_NUM = ["initial_weight", "class_min", "class_max", "buy_price", "care_price", "buyback_price", "discount", "down_payment", "total", "due_amount", "last_weight", "bill_count"];

export async function listOrders(): Promise<Order[]> {
  const supabase = await createClient();
  const { data } = await supabase.from("v_qurban_orders").select("*").order("created_at", { ascending: false }).limit(1000);
  return (data ?? []).map((r) => num(r as Order, ORDER_NUM));
}

export async function getOrder(id: string): Promise<Order | null> {
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  const supabase = await createClient();
  const { data } = await supabase.from("v_qurban_orders").select("*").eq("id", id).maybeSingle();
  return data ? num(data as Order, ORDER_NUM) : null;
}

export async function getLines(id: string): Promise<Line[]> {
  const supabase = await createClient();
  const { data } = await supabase.rpc("qurban_order_lines", { p_id: id });
  return ((data ?? []) as Line[]).map((l) => num(l, ["line_no", "qty", "price"]));
}

export async function listWeighings(orderIds?: string[]): Promise<Weighing[]> {
  const supabase = await createClient();
  let q = supabase.from("qurban_weighings").select("id, order_id, weigh_date, weight, note").order("weigh_date").order("created_at").limit(5000);
  if (orderIds) q = q.in("order_id", orderIds);
  const { data } = await q;
  return (data ?? []).map((r) => num(r as Weighing, ["weight"]));
}

export async function listBills(orderId?: string): Promise<Bill[]> {
  const supabase = await createClient();
  let q = supabase.from("qurban_bills").select("*").order("ym").limit(2000);
  if (orderId) q = q.eq("order_id", orderId);
  const { data } = await q;
  return (data ?? []).map((r) => num(r as Bill, ["days", "rate", "basis_weight"]));
}

export async function listQc(): Promise<Qc[]> {
  const supabase = await createClient();
  const { data } = await supabase.from("qurban_qc_reports").select("*").order("ym", { ascending: false }).order("customer_nick").limit(1000);
  return (data ?? []) as Qc[];
}

export async function getBuyer(orderId: string): Promise<Buyer | null> {
  const supabase = await createClient();
  const { data } = await supabase.from("qurban_buyer_details").select("*").eq("order_id", orderId).maybeSingle();
  return (data as Buyer | null) ?? null;
}

export async function listBuyers(): Promise<Buyer[]> {
  const supabase = await createClient();
  const { data } = await supabase.from("qurban_buyer_details").select("*").limit(2000);
  return (data ?? []) as Buyer[];
}

export async function getSettings(): Promise<Record<string, string>> {
  const supabase = await createClient();
  const { data } = await supabase.from("qurban_settings").select("key, value");
  return Object.fromEntries((data ?? []).map((r: { key: string; value: string }) => [r.key, r.value]));
}

export async function listClasses(): Promise<PriceClass[]> {
  const supabase = await createClient();
  const { data } = await supabase.from("qurban_price_classes").select("*").order("min_kg").order("effective_from", { ascending: false });
  return (data ?? []).map((r) => num(r as PriceClass, ["min_kg", "max_kg", "buy_price", "care_price", "buyback_price"]));
}
