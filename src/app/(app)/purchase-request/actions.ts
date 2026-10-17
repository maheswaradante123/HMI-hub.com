"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { parsePr } from "@/lib/pr/schema";

export type PrFormState = {
  error?: string;
  values?: { reason: string; priority: string; rows: Record<string, string>[] };
};
export type ActionState = { error?: string };

const ROW_FIELDS = ["product_id", "item_name", "qty", "unit_id", "estimated_price", "notes"] as const;

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
    case "23503":
      return "Pilihan yang dipakai sudah tidak tersedia. Muat ulang halaman lalu pilih lagi.";
    default:
      return "Data belum tersimpan. Silakan coba lagi. Jika masih gagal, hubungi Owner.";
  }
}

export async function savePr(id: string | null, _prev: PrFormState, formData: FormData): Promise<PrFormState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");

  const get = (k: string) => formData.getAll(k).map((v) => (typeof v === "string" ? v : ""));
  const cols = Object.fromEntries(ROW_FIELDS.map((f) => [f, get(f)]));
  const count = Math.max(...ROW_FIELDS.map((f) => cols[f].length), 0);
  const rows = Array.from({ length: count }, (_, i) =>
    Object.fromEntries(ROW_FIELDS.map((f) => [f, cols[f][i] ?? ""])),
  );
  const reason = String(formData.get("reason") ?? "");
  const priority = String(formData.get("priority") ?? "");
  const values = { reason, priority, rows };

  if (!session.can("purchase_request", "create")) {
    return { error: "Anda tidak memiliki izin membuat Purchase Request.", values };
  }
  const parsed = parsePr({ reason, priority, rows });
  if (!parsed.ok) return { error: parsed.error, values };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("save_purchase_request", {
    p_id: id,
    p_reason: parsed.data.reason,
    p_priority: parsed.data.priority,
    p_items: parsed.data.items,
  });
  if (error || !data) return { error: dbMessage(error ?? {}), values };
  const prId = data as string;

  if (formData.get("intent") === "submit") {
    const { error: e2 } = await supabase.rpc("pr_change_status", { p_id: prId, p_to: "SUBMITTED", p_note: null });
    if (e2) {
      // Draf sudah tersimpan; arahkan ke halaman draf agar bisa diajukan ulang.
      revalidatePath("/purchase-request");
      redirect(`/purchase-request/${prId}?ok=draf-tersimpan`);
    }
    revalidatePath("/purchase-request");
    redirect(`/purchase-request/${prId}?ok=diajukan`);
  }
  revalidatePath("/purchase-request");
  redirect(`/purchase-request/${prId}?ok=draf-tersimpan`);
}

export async function changeStatus(
  id: string,
  to: string,
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  const note = String(formData.get("note") ?? "").trim();
  if (to === "REJECTED" && !note) return { error: "Alasan penolakan wajib diisi." };
  if (note.length > 1000) return { error: "Catatan terlalu panjang." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("pr_change_status", { p_id: id, p_to: to, p_note: note || null });
  if (error) return { error: dbMessage(error) };
  revalidatePath(`/purchase-request/${id}`);
  revalidatePath("/purchase-request");
  return {};
}

export async function discardPr(id: string): Promise<void> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  const supabase = await createClient();
  const { error } = await supabase.rpc("pr_discard", { p_id: id });
  if (error) redirect(`/purchase-request/${id}?e=gagal`);
  revalidatePath("/purchase-request");
  redirect("/purchase-request?ok=dihapus");
}

export async function setItemSupplier(
  prId: string,
  itemId: string,
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  const supplierId = String(formData.get("supplier_id") ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(supplierId)) return { error: "Pilih supplier terlebih dahulu." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("pr_set_item_supplier", { p_item_id: itemId, p_supplier_id: supplierId });
  if (error) return { error: dbMessage(error) };
  revalidatePath(`/purchase-request/${prId}`);
  return {};
}
