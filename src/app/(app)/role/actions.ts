"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

export type RoleState = { error?: string };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function saveRolePermissions(roleId: string, _prev: RoleState, formData: FormData): Promise<RoleState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  if (!session.can("role", "edit")) return { error: "Anda tidak memiliki izin mengubah role." };
  if (!UUID.test(roleId)) return { error: "Role tidak valid." };

  const wanted = new Set(formData.getAll("perm").map(String).filter((p) => UUID.test(p)));
  const supabase = await createClient();
  const { data: role } = await supabase.from("roles").select("is_superuser").eq("id", roleId).maybeSingle();
  if (!role) return { error: "Role tidak ditemukan." };
  if (role.is_superuser) return { error: "Role Owner memiliki akses penuh dan tidak bisa diubah." };

  const [{ data: all }, { data: current }] = await Promise.all([
    supabase.from("permissions").select("id"),
    supabase.from("role_permissions").select("permission_id").eq("role_id", roleId),
  ]);
  const valid = new Set((all ?? []).map((p) => p.id as string));
  const have = new Set((current ?? []).map((p) => p.permission_id as string));
  const add = [...wanted].filter((p) => valid.has(p) && !have.has(p));
  const remove = [...have].filter((p) => !wanted.has(p));

  if (add.length) {
    const { error } = await supabase.from("role_permissions").insert(add.map((permission_id) => ({ role_id: roleId, permission_id })));
    if (error) return { error: "Perubahan izin belum tersimpan. Coba lagi." };
  }
  if (remove.length) {
    const { error } = await supabase.from("role_permissions").delete().eq("role_id", roleId).in("permission_id", remove);
    if (error) return { error: "Sebagian izin belum bisa dicabut. Muat ulang halaman lalu coba lagi." };
  }
  revalidatePath("/role");
  redirect(`/role/${roleId}?ok=disimpan`);
}

// Menyalakan atau mematikan satu izin langsung dari matriks Hak Akses (satu huruf = satu izin).
export async function setRolePermission(roleId: string, permissionId: string, on: boolean): Promise<RoleState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  if (!session.can("role", "edit")) return { error: "Anda tidak memiliki izin mengubah hak akses." };
  if (!UUID.test(roleId) || !UUID.test(permissionId)) return { error: "Data tidak valid." };
  const supabase = await createClient();
  const [{ data: role }, { data: perm }] = await Promise.all([
    supabase.from("roles").select("is_superuser").eq("id", roleId).maybeSingle(),
    supabase.from("permissions").select("id").eq("id", permissionId).maybeSingle(),
  ]);
  if (!role || !perm) return { error: "Role atau izin tidak ditemukan. Muat ulang halaman." };
  if (role.is_superuser) return { error: "Role Owner memiliki akses penuh dan tidak bisa diubah." };
  if (on) {
    const { error } = await supabase.from("role_permissions").insert({ role_id: roleId, permission_id: permissionId });
    if (error && error.code !== "23505") return { error: "Izin belum tersimpan. Coba lagi." };
  } else {
    const { error } = await supabase.from("role_permissions").delete().eq("role_id", roleId).eq("permission_id", permissionId);
    if (error) return { error: "Izin belum bisa dicabut. Coba lagi." };
  }
  revalidatePath("/role");
  return {};
}
