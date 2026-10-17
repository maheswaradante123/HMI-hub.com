"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { RESOURCES } from "@/lib/master/config";
import { buildSchema } from "@/lib/master/schema";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

export type FormState = { error?: string; values?: Record<string, string> };

function friendlyDbError(code?: string): string {
  switch (code) {
    case "23505":
      return "Kode atau nama ini sudah dipakai data lain. Gunakan kode atau nama yang berbeda.";
    case "42501":
      return "Anda tidak memiliki izin untuk melakukan ini.";
    case "23503":
      return "Pilihan yang dipakai sudah tidak tersedia. Muat ulang halaman lalu pilih lagi.";
    case "23514":
      return "Ada isian yang tidak sesuai aturan. Periksa kembali isian Anda.";
    default:
      return "Data belum tersimpan. Silakan coba lagi. Jika masih gagal, hubungi Owner.";
  }
}

export async function saveRecord(
  key: string,
  id: string | null,
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  const resource = RESOURCES[key];
  if (!resource) return { error: "Jenis data tidak dikenal." };

  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  const mode = id ? "edit" : "create";
  if (!session.can(resource.module, mode)) {
    return { error: "Anda tidak memiliki izin untuk melakukan ini." };
  }

  const raw: Record<string, string> = {};
  for (const f of resource.fields) {
    const v = formData.get(f.name);
    raw[f.name] = typeof v === "string" ? v : "";
  }

  const parsed = buildSchema(resource, mode).safeParse(raw);
  if (!parsed.success) {
    return { error: parsed.error.issues[0].message, values: raw };
  }

  const supabase = await createClient();
  if (id) {
    const { data, error } = await supabase
      .from(resource.table)
      .update(parsed.data)
      .eq("id", id)
      .select("id");
    if (error) return { error: friendlyDbError(error.code), values: raw };
    if (!data || data.length === 0) {
      return { error: "Data tidak ditemukan atau Anda tidak berhak mengubahnya.", values: raw };
    }
  } else {
    const { error } = await supabase.from(resource.table).insert(parsed.data);
    if (error) return { error: friendlyDbError(error.code), values: raw };
  }

  revalidatePath(`/data/${key}`);
  redirect(`/data/${key}?ok=${id ? "diubah" : "ditambah"}`);
}

// Data tidak pernah dihapus; hanya diaktifkan atau dinonaktifkan.
export async function setActive(key: string, id: string, active: boolean) {
  const resource = RESOURCES[key];
  if (!resource) redirect("/");

  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  if (!session.can(resource.module, "edit")) {
    redirect(`/data/${key}?error=izin`);
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from(resource.table)
    .update({ is_active: active })
    .eq("id", id)
    .select("id");

  revalidatePath(`/data/${key}`);
  if (error || !data || data.length === 0) redirect(`/data/${key}?error=gagal`);
  redirect(`/data/${key}?ok=${active ? "diaktifkan" : "dinonaktifkan"}`);
}
