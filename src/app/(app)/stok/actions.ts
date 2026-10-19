"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { dbMessage } from "@/lib/docs/errors";
import { parseGram, parseQty } from "@/lib/docs/parse";
import { isRealDate, parseMoney } from "@/lib/pricing/schema";

export type StockFormState = { error?: string; values?: Record<string, string> };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TYPES = ["OPENING", "IN_PURCHASE", "ADJUST_IN", "ADJUST_OUT"];

export async function recordMovement(_prev: StockFormState, formData: FormData): Promise<StockFormState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  const g = (k: string) => String(formData.get(k) ?? "").trim();
  const values = { product: g("product"), warehouse: g("warehouse"), type: g("type"), qty: g("qty"), lot: g("lot").toUpperCase(), cost: g("cost"), date: g("date"), note: g("note") };

  if (!session.can("stock", "create")) return { error: "Anda tidak memiliki izin mencatat stok.", values };
  if (!UUID.test(values.product)) return { error: "Produk belum dipilih.", values };
  if (!UUID.test(values.warehouse)) return { error: "Gudang belum dipilih.", values };
  if (!TYPES.includes(values.type)) return { error: "Jenis pencatatan belum dipilih.", values };
  const supabase = await createClient();
  const { data: prod } = await supabase.from("products").select("units(code)").eq("id", values.product).maybeSingle();
  const unitRel = prod?.units as { code: string } | { code: string }[] | null | undefined;
  const isGram = (Array.isArray(unitRel) ? unitRel[0]?.code : unitRel?.code) === "GRAM";
  const qty = isGram ? parseGram(values.qty) : parseQty(values.qty);
  if (typeof qty !== "number" || qty <= 0) return { error: isGram ? "Jumlah dalam gram harus bilangan bulat lebih dari 0, tanpa koma (contoh 14620 atau 14.620)." : "Jumlah harus angka lebih dari 0 (contoh 12,5).", values };
  let cost: number | null = null;
  if (values.cost) {
    const c = parseMoney(values.cost);
    if (typeof c !== "number") return { error: "Harga beli harus berupa angka rupiah (contoh 135.000).", values };
    cost = c;
  }
  if (values.type === "IN_PURCHASE" && cost === null) return { error: "Harga beli per satuan wajib diisi untuk pembelian masuk.", values };
  if (values.lot.length > 40) return { error: "Kode sapi terlalu panjang (maksimal 40 huruf).", values };
  if (values.date && !isRealDate(values.date)) return { error: "Tanggal tidak benar.", values };
  if ((values.type === "ADJUST_IN" || values.type === "ADJUST_OUT") && !values.note) return { error: "Penyesuaian wajib disertai alasan.", values };

  const { error } = await supabase.rpc("record_stock_movement", {
    p_product: values.product, p_wh: values.warehouse, p_type: values.type, p_qty: qty,
    p_cost: values.type === "IN_PURCHASE" ? cost : null, p_note: values.note || null, p_date: values.date || null, p_lot: values.lot || null,
  });
  if (error) return { error: dbMessage(error), values };

  revalidatePath("/stok");
  redirect(`/stok/${values.product}?ok=dicatat`);
}
