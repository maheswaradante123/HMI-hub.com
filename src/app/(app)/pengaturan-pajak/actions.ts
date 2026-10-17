"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { dbMessage } from "@/lib/docs/errors";

export type TaxState = { error?: string; ok?: boolean };

export async function saveTax(_prev: TaxState, formData: FormData): Promise<TaxState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  if (!session.can("master_data", "edit")) return { error: "Anda tidak memiliki izin mengubah pengaturan pajak." };
  const label = String(formData.get("label") ?? "").trim();
  const raw = String(formData.get("rate") ?? "").trim().replace(",", ".");
  if (!label) return { error: "Nama pajak wajib diisi." };
  if (!/^\d{1,3}(\.\d{1,2})?$/.test(raw)) return { error: "Tarif harus angka antara 0 dan 100 (contoh 11 atau 11,5)." };
  const rate = Number(raw);
  if (rate < 0 || rate > 100) return { error: "Tarif harus antara 0 dan 100." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_tax_rate", { p_label: label, p_rate: rate });
  if (error) return { error: dbMessage(error) };
  revalidatePath("/pengaturan-pajak");
  return { ok: true };
}
