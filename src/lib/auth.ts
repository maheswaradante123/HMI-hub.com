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
  // Token diperiksa secara lokal (cepat). Keputusan akses sebenarnya tetap
  // di database: RLS dan my_permissions() memakai auth.uid() dari token yang sama.
  const { data: claimsData } = await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;
  if (!userId) return null;

  // Dua query berjalan bersamaan, bukan berurutan.
  const [{ data: profile }, { data: perms }] = await Promise.all([
    supabase
      .from("user_profiles")
      .select("full_name, is_active, roles(name, is_active)")
      .eq("id", userId)
      .maybeSingle(),
    supabase.rpc("my_permissions"),
  ]);

  const role = Array.isArray(profile?.roles) ? profile?.roles[0] : profile?.roles;
  if (!profile || !profile.is_active || !role?.is_active) return null;
  const granted = new Set(
    (perms ?? []).map((p: { module: string; action: string }) => `${p.module}:${p.action}`),
  );

  return {
    userId,
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
