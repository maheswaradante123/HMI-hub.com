import "server-only";
import nodemailer from "nodemailer";
import type { SupabaseClient } from "@supabase/supabase-js";
import { appBaseUrl, buildEmail, docPath } from "./template";

// Pengiriman lewat SMTP (Gmail dengan App Password, atau layanan lain). Kunci rahasia hanya di variabel lingkungan server.
export function mailConfigured(env: Record<string, string | undefined> = process.env): boolean {
  return Boolean(env.SMTP_USER && env.SMTP_PASS);
}

function transport() {
  const host = process.env.SMTP_HOST || "smtp.gmail.com";
  const port = Number(process.env.SMTP_PORT || 465);
  return nodemailer.createTransport({ host, port, secure: port === 465, auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS }, connectionTimeout: 10000, socketTimeout: 15000 });
}

function from() {
  const name = process.env.MAIL_FROM_NAME || "HMI Hub";
  return `"${name.replace(/"/g, "")}" <${process.env.MAIL_FROM || process.env.SMTP_USER}>`;
}

type Claimed = { id: number; to_email: string; doc_type: string | null; doc_id: string | null; subject: string; message: string };

// Mengirim email yang dipicu oleh user yang sedang login. Tidak pernah melempar galat: kegagalan dicatat di kotak keluar
// dan dicoba lagi pada proses berikutnya (maksimal 3 kali).
export async function dispatchNotifications(supabase: SupabaseClient): Promise<void> {
  if (!mailConfigured()) return;
  try {
    const { data, error } = await supabase.rpc("notif_claim", { p_limit: 50 });
    if (error || !Array.isArray(data) || data.length === 0) return;
    const tp = transport();
    const base = appBaseUrl();
    for (const row of data as Claimed[]) {
      try {
        const mail = buildEmail(row.subject, row.message, base + docPath(row.doc_type, row.doc_id));
        await tp.sendMail({ from: from(), to: row.to_email, subject: mail.subject, text: mail.text, html: mail.html });
        await supabase.rpc("notif_finish", { p_id: row.id, p_ok: true });
      } catch (e) {
        await supabase.rpc("notif_finish", { p_id: row.id, p_ok: false, p_error: e instanceof Error ? e.message : "gagal" });
      }
    }
  } catch {
    // Notifikasi tidak boleh mengganggu pekerjaan utama.
  }
}

export async function sendTestEmail(to: string): Promise<{ ok: boolean; error?: string }> {
  if (!mailConfigured()) return { ok: false, error: "Pengirim email belum diatur di server (SMTP_USER dan SMTP_PASS)." };
  try {
    const mail = buildEmail("Email uji", "Email uji dari HMI Hub.\nJika Anda membaca ini, pengiriman email berjalan.", appBaseUrl());
    await transport().sendMail({ from: from(), to, subject: mail.subject, text: mail.text, html: mail.html });
    return { ok: true };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message.slice(0, 200) : "Gagal mengirim." };
  }
}
