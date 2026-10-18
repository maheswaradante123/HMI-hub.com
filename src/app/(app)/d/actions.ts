"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { CONFIGS } from "@/lib/docs/config";
import { parseDoc, parseQty, type Payload } from "@/lib/docs/parse";
import { cleanCwItems, cwTotals } from "@/lib/docs/cw";
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

// Penimbangan Karkas: item diketik bebas + kategori. Item yang belum ada di master dibuat otomatis, lalu dokumen disimpan
// sebagai draf, atau langsung difinalkan (stok masuk) bila tombol "Finalisasi & masuk stok" yang ditekan.
export async function saveCw(id: string, _prev: DocFormState, formData: FormData): Promise<DocFormState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  const raw = String(formData.get("payload") ?? "");
  const finalize = formData.get("mode") === "final";
  const cfg = CONFIGS.cw;
  if (id && !UUID.test(id)) return { error: "Dokumen tidak valid.", payload: raw };
  if (!session.can(cfg.module, id ? "edit" : "create")) return { error: "Anda tidak memiliki izin untuk menyimpan dokumen ini.", payload: raw };
  if (finalize && !session.can(cfg.module, "edit")) return { error: "Anda tidak memiliki izin untuk memfinalkan penimbangan.", payload: raw };

  let payload: { header?: Record<string, string>; items?: { name: string; cat: string; weight: string }[] };
  try { payload = JSON.parse(raw); } catch { return { error: "Isian tidak terbaca. Muat ulang halaman lalu coba lagi.", payload: raw }; }
  const head = parseDoc({ ...cfg, children: [] }, { header: payload.header ?? {} });
  if (!head.ok) return { error: head.error, payload: raw };
  const live = head.header.live_weight, carcass = Number(head.header.carcass_weight);
  if (live !== null && live !== undefined && carcass > Number(live)) return { error: "Berat karkas tidak boleh lebih besar dari berat hidup.", payload: raw };
  const items = cleanCwItems(Array.isArray(payload.items) ? payload.items : [], parseQty);
  if (!items.ok) return { error: items.error, payload: raw };
  if (cwTotals(items.items, carcass).over) return { error: "Total hasil potong melebihi berat karkas. Periksa kembali berat tiap item.", payload: raw };

  const supabase = await createClient();
  const { data: ids, error: e1 } = await supabase.rpc("cw_resolve_items", { p_items: items.items.map((i) => ({ name: i.name, cat: i.cat })) });
  if (e1) return { error: dbMessage(e1), payload: raw };
  const resolved = (ids ?? []) as { product_id: string | null; non_carcass_type_id: string | null }[];
  const parsed = parseDoc(cfg, {
    header: payload.header ?? {},
    children: { items: items.items.map((it, i) => ({ product_id: resolved[i]?.product_id ?? "", non_carcass_type_id: resolved[i]?.non_carcass_type_id ?? "", weight: String(it.weight) })) },
  });
  if (!parsed.ok) return { error: parsed.error, payload: raw };

  const { data, error } = await supabase.rpc("save_doc", { p_type: cfg.type, p_id: id || null, p_header: parsed.header, p_children: parsed.children });
  if (error) return { error: error.code === "23505" ? "Kode sapi ini sudah pernah ditimbang (ada penimbangan lain yang masih aktif)." : dbMessage(error), payload: raw };
  const docId = data as string;
  revalidatePath("/d/cw");
  if (!finalize) redirect(`/d/cw/${docId}?ok=disimpan`);

  const { error: e2 } = await supabase.rpc("doc_change_status", { p_type: cfg.type, p_id: docId, p_to: "FINAL", p_note: null });
  revalidatePath(`/d/cw/${docId}`);
  // Draf sudah tersimpan; bila finalisasi gagal, buka drafnya beserta alasannya agar tidak tersimpan dua kali.
  if (e2) redirect(`/d/cw/${docId}?ok=disimpan&err=${encodeURIComponent(dbMessage(e2))}`);
  redirect(`/d/cw/${docId}?ok=final`);
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

export type PrItemPull = { pr_item_id: string; pr_number: string; pr_status: string; item_name: string; qty: number; unit: string; price: number; ac: string; code: string };
// Item Purchase Request yang bisa ditarik ke Cash Payment Journal.
export async function pullPrItems(): Promise<{ error?: string; items?: PrItemPull[] }> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  if (!session.can("cpj_journal", "create") && !session.can("cpj_journal", "edit")) return { error: "Anda tidak memiliki izin." };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("cpj_pullable_pr_items");
  if (error) return { error: dbMessage(error) };
  return { items: (data ?? []).map((r: Record<string, unknown>) => ({ pr_item_id: String(r.pr_item_id), pr_number: String(r.pr_number ?? ""), pr_status: String(r.pr_status), item_name: String(r.item_name), qty: Number(r.qty), unit: String(r.unit ?? ""), price: Number(r.price), ac: String(r.ac ?? "OPR"), code: String(r.code ?? "") })) };
}
