"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { dbMessage } from "@/lib/docs/errors";

export type QState = { error?: string; ok?: string };

const str = (f: FormData, k: string) => String(f.get(k) ?? "").trim();
const dec = (f: FormData, k: string) => Number(str(f, k).replace(/\./g, "").replace(",", "."));
const decPlain = (f: FormData, k: string) => Number(str(f, k).replace(",", "."));

async function ctx() {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  return { session, supabase: await createClient() };
}
function done(msg: string, ids?: string): QState {
  revalidatePath("/qurban", "layout");
  void ids;
  return { ok: msg };
}

export async function createOrder(_p: QState, f: FormData): Promise<QState> {
  const { session, supabase } = await ctx();
  if (!session.can("qurban", "create")) return { error: "Anda tidak memiliki izin membuat pesanan Qurban." };
  const start = str(f, "start");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(start)) return { error: "Tanggal mulai pemeliharaan wajib diisi." };
  // Satu baris per sapi: cow_1/weight_1, cow_2/weight_2, ... (daftar dikirim form dalam "rows").
  const idx = str(f, "rows").split(",").filter((x) => /^\d+$/.test(x));
  const cows: { cow: string; weight: number }[] = [];
  for (const i of idx) {
    const cow = str(f, `cow_${i}`);
    const weight = decPlain(f, `weight_${i}`);
    if (!cow && !str(f, `weight_${i}`)) continue; // baris kosong dilewati
    if (!cow) return { error: `Nomor sapi pada baris ${cows.length + 1} wajib diisi.` };
    if (!(weight > 0)) return { error: `Hasil timbang sapi ${cow} harus berupa angka lebih dari 0 (contoh 612,5).` };
    cows.push({ cow, weight });
  }
  if (cows.length === 0) return { error: "Isi minimal satu sapi." };
  const { data, error } = await supabase.rpc("qurban_create_orders", { p_nick: str(f, "nick"), p_start: start, p_mode: str(f, "mode"), p_cows: cows });
  if (error) return { error: dbMessage(error) };
  revalidatePath("/qurban", "layout");
  redirect(`/qurban/${data}`);
}

// Gabungkan pesanan PROFORMA pelanggan yang sama ke dalam satu proforma (dan nanti satu invoice).
export async function mergeProforma(id: string, _p: QState, f: FormData): Promise<QState> {
  const { session, supabase } = await ctx();
  if (!session.can("qurban", "edit")) return { error: "Anda tidak memiliki izin menggabungkan pesanan." };
  const ids = f.getAll("merge").map(String).filter((x) => /^[0-9a-f-]{36}$/i.test(x));
  if (ids.length === 0) return { error: "Centang minimal satu sapi yang mau digabung." };
  const { error } = await supabase.rpc("qurban_merge_proforma", { p_id: id, p_ids: ids });
  return error ? { error: dbMessage(error) } : done(`${ids.length} sapi digabung ke proforma ini.`);
}

export async function ungroupOrder(id: string, _p: QState, _f: FormData): Promise<QState> {
  void _f;
  const { session, supabase } = await ctx();
  if (!session.can("qurban", "edit")) return { error: "Anda tidak memiliki izin memisahkan pesanan." };
  const { data, error } = await supabase.rpc("qurban_ungroup", { p_id: id });
  return error ? { error: dbMessage(error) } : done(`Sapi dikeluarkan dari proforma gabungan. Nomor baru: ${data}.`);
}

export async function setDiscount(id: string, _p: QState, f: FormData): Promise<QState> {
  const { session, supabase } = await ctx();
  if (!session.can("qurban", "approve")) return { error: "Diskon hanya boleh diisi oleh Owner." };
  const amount = dec(f, "amount");
  if (!(amount >= 0)) return { error: "Diskon harus berupa angka Rupiah, 0 atau lebih." };
  const { error } = await supabase.rpc("qurban_set_discount", { p_id: id, p_amount: amount });
  return error ? { error: dbMessage(error) } : done("Diskon tersimpan.");
}

export async function setCareFixed(id: string, fixed: boolean, _p: QState, _f: FormData): Promise<QState> {
  void _p; void _f;
  const { session, supabase } = await ctx();
  if (!session.can("qurban", "approve")) return { error: "Tarif perawatan tetap hanya boleh diatur oleh Owner." };
  const { error } = await supabase.rpc("qurban_set_care_fixed", { p_id: id, p_fixed: fixed });
  return error ? { error: dbMessage(error) } : done(fixed ? "Tagihan bulanan sekarang memakai tarif tetap." : "Tagihan bulanan kembali mengikuti tarif kelas.");
}

export async function issueInvoice(id: string, _p: QState, _f: FormData): Promise<QState> {
  void _f;
  const { supabase } = await ctx();
  const { error } = await supabase.rpc("qurban_issue_invoice", { p_id: id });
  return error ? { error: dbMessage(error) } : done("Invoice diterbitkan.");
}

export async function markPaid(id: string, _p: QState, _f: FormData): Promise<QState> {
  void _f;
  const { supabase } = await ctx();
  const { error } = await supabase.rpc("qurban_mark_paid", { p_id: id });
  return error ? { error: dbMessage(error) } : done("Invoice ditandai lunas.");
}

export async function cancelOrder(id: string, _p: QState, f: FormData): Promise<QState> {
  const { supabase } = await ctx();
  const reason = str(f, "reason");
  if (!reason) return { error: "Alasan pembatalan wajib diisi." };
  const { error } = await supabase.rpc("qurban_cancel", { p_id: id, p_reason: reason });
  return error ? { error: dbMessage(error) } : done("Pesanan dibatalkan.");
}

export async function addWeighing(id: string, _p: QState, f: FormData): Promise<QState> {
  const { supabase } = await ctx();
  const w = decPlain(f, "weight");
  const date = str(f, "date");
  if (!(w > 0)) return { error: "Hasil timbang harus berupa angka lebih dari 0." };
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return { error: "Tanggal timbang wajib diisi." };
  const { error } = await supabase.rpc("qurban_add_weighing", { p_id: id, p_date: date, p_weight: w, p_note: str(f, "note") || null });
  return error ? { error: dbMessage(error) } : done("Penimbangan dicatat.");
}

export async function createBill(id: string, _p: QState, _f: FormData): Promise<QState> {
  void _f;
  const { supabase } = await ctx();
  const { data, error } = await supabase.rpc("qurban_create_bill", { p_id: id });
  return error ? { error: dbMessage(error) } : done(`Tagihan ${data} dibuat.`);
}

export async function markBillPaid(billId: string, _p: QState, _f: FormData): Promise<QState> {
  void _f;
  const { supabase } = await ctx();
  const { error } = await supabase.rpc("qurban_mark_bill_paid", { p_bill_id: billId });
  return error ? { error: dbMessage(error) } : done("Tagihan ditandai lunas.");
}

export async function setChoice(id: string, _p: QState, f: FormData): Promise<QState> {
  const { supabase } = await ctx();
  const { error } = await supabase.rpc("qurban_set_choice", { p_id: id, p_choice: str(f, "choice") });
  return error ? { error: dbMessage(error) } : done("Pilihan pemilik tersimpan.");
}

export async function saveSp(id: string, _p: QState, f: FormData): Promise<QState> {
  const { supabase } = await ctx();
  const nik = str(f, "nik").replace(/\s/g, "");
  if (!/^\d{16}$/.test(nik)) return { error: "No. KTP harus 16 angka." };
  const { error } = await supabase.rpc("qurban_save_sp", {
    p_id: id, p_name: str(f, "name"), p_nik: nik, p_addr: str(f, "addr"), p_phone: str(f, "phone"),
    p_type: str(f, "type"), p_date: str(f, "date") || null,
  });
  return error ? { error: dbMessage(error) } : done("Data tersimpan. Surat perjanjian siap diunduh.");
}

export async function createQc(_p: QState, f: FormData): Promise<QState> {
  const { session, supabase } = await ctx();
  if (!session.can("qc_report", "create")) return { error: "Anda tidak memiliki izin membuat QC Report." };
  const { data, error } = await supabase.rpc("qurban_create_qc", { p_ym: str(f, "ym"), p_nick: str(f, "nick") });
  if (error) return { error: dbMessage(error) };
  revalidatePath("/qurban", "layout");
  redirect(`/qurban/qc/${data}`);
}
