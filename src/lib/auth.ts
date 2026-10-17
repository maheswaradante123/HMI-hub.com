import "server-only";
import { cache } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type Session = {
  userId: string;
  fullName: string;
  roleName: string;
  can: (module: string, action: string) => boolean;
};

// Satu kali per request: data user, role, dan daftar izin efektif dari database.
// Daftar izin berasal dari fungsi my_permissions() sehingga sama persis dengan
// yang dipakai kebijakan RLS.
export const getSession = cache(async (): Promise<Session | null> => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: profile } = await supabase
    .from("user_profiles")
    .select("full_name, is_active, roles(name, is_active)")
    .eq("id", user.id)
    .maybeSingle();

  const role = Array.isArray(profile?.roles) ? profile?.roles[0] : profile?.roles;
  if (!profile || !profile.is_active || !role?.is_active) return null;

  const { data: perms } = await supabase.rpc("my_permissions");
  const granted = new Set(
    (perms ?? []).map((p: { module: string; action: string }) => `${p.module}:${p.action}`),
  );

  return {
    userId: user.id,
    fullName: profile.full_name,
    roleName: role.name,
    can: (module, action) => granted.has(`${module}:${action}`),
  };
});

export async function requireSession(): Promise<Session> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  return session;
}

// Dipakai di halaman dan server action. Mengembalikan session jika diizinkan.
export async function requirePermission(module: string, action = "view") {
  const session = await requireSession();
  if (!session.can(module, action)) {
    throw new Error("FORBIDDEN");
  }
  return session;
}
