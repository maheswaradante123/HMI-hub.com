"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { parsePrRows } from "@/lib/pr/schema";
import { LINE_LABEL, type LineStatus } from "@/lib/pr/lines";

export type PrFormState = { error?: string; rows?: Record<string, string>[] };
export type MoveResult = { error?: string; message?: string };

// Pesan dari database sudah berbahasa Indonesia dan aman ditampilkan.
// Kode lain diganti pesan umum agar detail teknis tidak bocor.
function dbMessage(error: { code?: string; message?: string }): string {
  switch (error.code) {
    case "42501":
    case "55000":
    case "22023":
    case "P0002":
      return error.message ?? "Aksi tidak dapat dilakukan.";
    case "23514":
      return "Ada isian yang tidak sesuai aturan. Periksa kembali isian Anda.";
    default:
      return "Data belum tersimpan. Silakan coba lagi. Jika masih gagal, hubungi Owner.";
  }
}

const FIELDS = ["ac", "code", "item_name", "price", "qty", "unit", "pay_method"] as const;

export async function addPrItems(_prev: PrFormState, formData: FormData): Promise<PrFormState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  const get = (k: string) => formData.getAll(k).map((v) => (typeof v === "string" ? v : ""));
  const cols = Object.fromEntries(FIELDS.map((f) => [f, get(f)]));
  const count = Math.max(...FIELDS.map((f) => cols[f].length), 0);
  const rows = Array.from({ length: count }, (_, i) => Object.fromEntries(FIELDS.map((f) => [f, cols[f][i] ?? ""])));
  if (!session.can("purchase_request", "create")) return { error: "Anda tidak memiliki izin membuat Purchase Request.", rows };
  const parsed = parsePrRows(rows);
  if (!parsed.ok) return { error: parsed.error, rows };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("pr_add_items", { p_items: parsed.items.map((i) => ({ ac: i.ac, code: i.code, item_name: i.item_name, price: i.price, qty: i.qty, unit: i.unit, pay_method: i.pay_method })), p_date: null });
  if (error || !data) return { error: dbMessage(error ?? {}), rows };
  revalidatePath("/purchase-request");
  redirect(`/purchase-request/${data as string}?ok=ditambah-${parsed.items.length}`);
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function movePrItems(sheetId: string, ids: string[], to: string, note: string): Promise<MoveResult> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  if (ids.length === 0 || ids.length > 200 || !ids.every((x) => UUID.test(x))) return { error: "Centang barang terlebih dahulu." };
  if (to === "REJECTED" && !note.trim()) return { error: "Alasan penolakan wajib diisi." };
  if (note.length > 1000) return { error: "Catatan terlalu panjang." };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("pr_move_items", { p_ids: ids, p_to: to, p_note: note.trim() || null });
  if (error) return { error: dbMessage(error) };
  revalidatePath(`/purchase-request/${sheetId}`);
  revalidatePath("/purchase-request");
  const n = Number(data ?? 0);
  return n > 0 ? { message: `${n} barang menjadi ${LINE_LABEL[to as LineStatus] ?? to}.` } : { error: "Tidak ada barang yang cocok untuk aksi ini (periksa status barang yang dicentang)." };
}

export async function updatePrItem(sheetId: string, itemId: string, fields: Record<string, string>): Promise<MoveResult> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  if (!UUID.test(itemId)) return { error: "Barang tidak valid." };
  const body: Record<string, string | number> = {};
  if ("pay_method" in fields) body.pay_method = fields.pay_method;
  if ("proof" in fields) body.proof = fields.proof;
  if ("item_name" in fields) {
    const parsed = parsePrRows([{ ac: fields.ac, code: fields.code, item_name: fields.item_name, price: fields.price, qty: fields.qty, unit: fields.unit, pay_method: "tf" }]);
    if (!parsed.ok) return { error: parsed.error.replace(/^Barang baris 1: /, "") };
    const i = parsed.items[0];
    Object.assign(body, { item_name: i.item_name, price: i.price, qty: i.qty, unit: i.unit, ac: i.ac, code: i.code });
  }
  if (Object.keys(body).length === 0) return { error: "Tidak ada perubahan." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("pr_update_item", { p_id: itemId, p_fields: body });
  if (error) return { error: dbMessage(error) };
  revalidatePath(`/purchase-request/${sheetId}`);
  return { message: "Tersimpan." };
}
