"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

export type UserState = { error?: string };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function saveUser(userId: string, _prev: UserState, formData: FormData): Promise<UserState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  if (!session.can("user", "edit")) return { error: "Anda tidak memiliki izin mengubah user." };
  if (!UUID.test(userId)) return { error: "User tidak valid." };
  if (userId === session.userId) return { error: "Anda tidak bisa mengubah role atau status akun Anda sendiri. Minta Owner lain atau ubah lewat Supabase." };

  const roleId = String(formData.get("role_id") ?? "");
  const deptId = String(formData.get("department_id") ?? "");
  const active = formData.get("is_active") === "on";
  const fullName = String(formData.get("full_name") ?? "").trim();
  if (!UUID.test(roleId)) return { error: "Role belum dipilih." };
  if (deptId && !UUID.test(deptId)) return { error: "Departemen tidak valid." };
  if (!fullName || fullName.length > 100) return { error: "Nama wajib diisi (maksimal 100 huruf)." };

  const supabase = await createClient();
  const { error } = await supabase.from("user_profiles").update({ role_id: roleId, department_id: deptId || null, is_active: active, full_name: fullName }).eq("id", userId);
  if (error) return { error: "Perubahan belum tersimpan. Coba lagi." };
  revalidatePath("/user");
  redirect("/user?ok=disimpan");
}
