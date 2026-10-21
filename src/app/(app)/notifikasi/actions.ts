"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { sendTestEmail } from "@/lib/notify/send";

export type NotifState = { error?: string; message?: string };

export async function setEmailNotif(on: boolean): Promise<NotifState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_my_email_notif", { p_on: on });
  if (error) return { error: "Pilihan belum tersimpan. Coba lagi." };
  revalidatePath("/notifikasi");
  return { message: on ? "Notifikasi email dinyalakan." : "Notifikasi email dimatikan." };
}

export async function sendMyTestEmail(): Promise<NotifState> {
  const session = await getSession();
  if (!session) redirect("/login?error=akses");
  const supabase = await createClient();
  const { data: email } = await supabase.rpc("my_email");
  if (!email || typeof email !== "string") return { error: "Alamat email akun Anda tidak ditemukan." };
  const r = await sendTestEmail(email);
  return r.ok ? { message: `Email uji dikirim ke ${email}. Periksa kotak masuk dan folder spam.` } : { error: r.error };
}
