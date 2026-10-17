"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { dbMessage } from "@/lib/docs/errors";
import { isRealDate, parseMoney } from "@/lib/pricing/schema";

export type CPState = { error?: string; values?: Record<string, string> };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function setCustomerPrice(customerId: string, _prev: CPState, formData: FormData): Promise<CPState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  const g = (k: string) => String(formData.get(k) ?? "").trim();
  const values = { product: g("product"), price: g("price"), from: g("from"), note: g("note") };
  if (!UUID.test(customerId)) return { error: "Customer tidak valid.", values };
  if (!session.can("customer", "edit")) return { error: "Anda tidak memiliki izin mengubah harga customer.", values };
  if (!UUID.test(values.product)) return { error: "Produk belum dipilih.", values };
  const price = parseMoney(values.price);
  if (typeof price !== "number") return { error: "Harga harus berupa angka rupiah (contoh 135.000), tidak boleh kosong atau negatif.", values };
  if (!isRealDate(values.from)) return { error: "Tanggal berlaku belum diisi dengan benar.", values };
  if (values.note.length > 500) return { error: "Catatan terlalu panjang (maksimal 500 huruf).", values };

  const supabase = await createClient();
  const { error } = await supabase.rpc("set_customer_price", { p_customer: customerId, p_product: values.product, p_price: price, p_from: values.from, p_note: values.note || null });
  if (error) return { error: dbMessage(error), values };
  revalidatePath(`/harga-customer/${customerId}`);
  redirect(`/harga-customer/${customerId}?ok=disimpan`);
}

export async function voidCustomerPrice(customerId: string, priceId: string, _prev: CPState, formData: FormData): Promise<CPState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  if (!UUID.test(priceId)) return { error: "Harga tidak valid." };
  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "Alasan pembatalan wajib diisi." };
  if (reason.length > 500) return { error: "Alasan terlalu panjang (maksimal 500 huruf)." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("void_customer_price", { p_id: priceId, p_reason: reason });
  if (error) return { error: dbMessage(error) };
  revalidatePath(`/harga-customer/${customerId}`);
  redirect(`/harga-customer/${customerId}?ok=dibatalkan`);
}
