"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { CONFIGS } from "@/lib/docs/config";
import { parseDoc, type Payload } from "@/lib/docs/parse";
import { dbMessage } from "@/lib/docs/errors";

export type DocFormState = { error?: string; payload?: string };
export type DocActionState = { error?: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function saveDoc(slug: string, id: string, _prev: DocFormState, formData: FormData): Promise<DocFormState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  const raw = String(formData.get("payload") ?? "");
  const cfg = CONFIGS[slug];
  if (!cfg) return { error: "Jenis dokumen tidak dikenal.", payload: raw };
  if (id && !UUID.test(id)) return { error: "Dokumen tidak valid.", payload: raw };
  if (!session.can(cfg.module, id ? "edit" : "create")) {
    return { error: "Anda tidak memiliki izin untuk menyimpan dokumen ini.", payload: raw };
  }

  let payload: Payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    return { error: "Isian tidak terbaca. Muat ulang halaman lalu coba lagi.", payload: raw };
  }
  const parsed = parseDoc(cfg, payload);
  if (!parsed.ok) return { error: parsed.error, payload: raw };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("save_doc", {
    p_type: cfg.type,
    p_id: id || null,
    p_header: parsed.header,
    p_children: parsed.children,
  });
  if (error) return { error: dbMessage(error), payload: raw };

  revalidatePath(`/d/${slug}`);
  redirect(`/d/${slug}/${data as string}?ok=disimpan`);
}

export async function changeDocStatus(slug: string, id: string, to: string, _prev: DocActionState, formData: FormData): Promise<DocActionState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  const cfg = CONFIGS[slug];
  if (!cfg || !UUID.test(id)) return { error: "Dokumen tidak valid." };
  const note = String(formData.get("note") ?? "").trim();
  if (note.length > 500) return { error: "Catatan terlalu panjang (maksimal 500 huruf)." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("doc_change_status", { p_type: cfg.type, p_id: id, p_to: to, p_note: note || null });
  if (error) return { error: dbMessage(error) };

  revalidatePath(`/d/${slug}`);
  revalidatePath(`/d/${slug}/${id}`);
  redirect(`/d/${slug}/${id}?ok=status`);
}

export async function closePr(prId: string, _prev: DocActionState, formData: FormData): Promise<DocActionState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  if (!UUID.test(prId)) return { error: "PR tidak valid." };
  const note = String(formData.get("note") ?? "").trim();
  const supabase = await createClient();
  const { error } = await supabase.rpc("pr_close", { p_id: prId, p_note: note || null });
  if (error) return { error: dbMessage(error) };
  revalidatePath(`/purchase-request/${prId}`);
  redirect(`/purchase-request/${prId}?ok=ditutup`);
}

export type QuickProductResult = { error?: string; product?: { id: string; code: string; name: string; unit: string } };

export async function quickProduct(name: string, unitId: string, categoryId: string): Promise<QuickProductResult> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  if (!session.can("ro", "create")) return { error: "Anda tidak memiliki izin untuk menambah produk." };
  if (!UUID.test(unitId)) return { error: "Pilih satuan terlebih dahulu." };
  if (categoryId && !UUID.test(categoryId)) return { error: "Kategori tidak valid." };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("ro_quick_product", { p_name: name, p_unit_id: unitId, p_category_id: categoryId || null });
  if (error) return { error: dbMessage(error) };
  const { data: p } = await supabase.from("products").select("id, code, name, units(name)").eq("id", data as string).maybeSingle();
  if (!p) return { error: "Produk belum bisa dibaca. Muat ulang halaman." };
  return { product: { id: p.id, code: p.code, name: p.name, unit: (p.units as unknown as { name: string } | null)?.name ?? "" } };
}

export type PullLine = { entry_date: string; description: string; tf: number; invoice_id: string };
export type PullResult = { error?: string; lines?: PullLine[]; recv?: { name: string; amount: number }[] };

// Menarik pembayaran invoice pada periode (kolom TF Rek HMI) untuk laporan Pemasukan Toko.
export async function pullInvoiceIncome(from: string, to: string): Promise<PullResult> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  if (!session.can("store_income", "create") && !session.can("store_income", "edit")) return { error: "Anda tidak memiliki izin." };
  if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to) || to < from) return { error: "Isi periode dengan benar dulu (tanggal akhir tidak boleh sebelum tanggal awal)." };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("store_income_invoice_lines", { p_from: from, p_to: to });
  if (error) return { error: dbMessage(error) };
  return { lines: (data ?? []).map((r: { entry_date: string; description: string; tf: number | string; invoice_id: string }) => ({ entry_date: r.entry_date, description: r.description, tf: Number(r.tf), invoice_id: r.invoice_id })) };
}

// Piutang saat ini per pelanggan dari invoice yang belum lunas.
export async function pullReceivables(): Promise<PullResult> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  if (!session.can("store_income", "create") && !session.can("store_income", "edit")) return { error: "Anda tidak memiliki izin." };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("store_income_receivables_now");
  if (error) return { error: dbMessage(error) };
  return { recv: (data ?? []).map((r: { name: string; amount: number | string }) => ({ name: r.name, amount: Number(r.amount) })) };
}
