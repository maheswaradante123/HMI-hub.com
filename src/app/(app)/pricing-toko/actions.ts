"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { parsePrice } from "@/lib/pricing/schema";

export type PriceFormState = { error?: string; values?: Record<string, string> };
export type VoidState = { error?: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Pesan dari fungsi database sudah berbahasa Indonesia; kode lain diganti pesan umum.
function dbMessage(error: { code?: string; message?: string }): string {
  switch (error.code) {
    case "42501":
    case "55000":
    case "22023":
    case "P0002":
      return error.message ?? "Aksi tidak dapat dilakukan.";
    case "23P01":
      return "Masa berlaku harga ini bertabrakan dengan harga lain. Muat ulang halaman lalu coba lagi.";
    case "23514":
      return "Ada isian yang tidak sesuai aturan. Periksa kembali isian Anda.";
    default:
      return "Harga belum tersimpan. Silakan coba lagi. Jika masih gagal, hubungi Owner.";
  }
}

export async function setPrice(productId: string, _prev: PriceFormState, formData: FormData): Promise<PriceFormState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  const get = (k: string) => String(formData.get(k) ?? "");
  const values = { sell: get("sell"), buy: get("buy"), supplier: get("supplier"), from: get("from"), note: get("note") };

  if (!UUID.test(productId)) return { error: "Produk tidak valid.", values };
  if (!session.can("pricing", "create")) return { error: "Anda tidak memiliki izin mengubah harga.", values };

  const supabase = await createClient();
  const { data: product } = await supabase.from("products").select("product_type").eq("id", productId).maybeSingle();
  if (!product) return { error: "Produk tidak ditemukan.", values };

  const parsed = parsePrice(values, {
    canSetCost: session.can("pricing_cost", "view"),
    showCost: product.product_type !== "MANUFACTURE",
  });
  if (!parsed.ok) return { error: parsed.error, values };

  const { error } = await supabase.rpc("set_product_price", {
    p_product_id: productId,
    p_supplier_id: parsed.data.supplier_id,
    p_buy_price: parsed.data.buy_price,
    p_sell_price: parsed.data.sell_price,
    p_from: parsed.data.effective_from,
    p_note: parsed.data.note,
  });
  if (error) return { error: dbMessage(error), values };

  revalidatePath("/pricing-toko");
  revalidatePath(`/pricing-toko/${productId}`);
  redirect(`/pricing-toko/${productId}?ok=disimpan`);
}

export async function voidPrice(
  productId: string,
  priceId: string,
  _prev: VoidState,
  formData: FormData,
): Promise<VoidState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  if (!UUID.test(priceId)) return { error: "Harga tidak valid." };
  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "Alasan pembatalan wajib diisi." };
  if (reason.length > 500) return { error: "Alasan terlalu panjang (maksimal 500 huruf)." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("void_product_price", { p_price_id: priceId, p_reason: reason });
  if (error) return { error: dbMessage(error) };

  revalidatePath("/pricing-toko");
  revalidatePath(`/pricing-toko/${productId}`);
  redirect(`/pricing-toko/${productId}?ok=dibatalkan`);
}
