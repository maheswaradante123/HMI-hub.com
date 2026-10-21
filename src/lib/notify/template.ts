import { CONFIGS } from "../docs/config.ts";

// Murni (tanpa I/O) agar mudah diuji: tautan dokumen dan isi email.
const BY_TYPE = new Map(Object.values(CONFIGS).map((c) => [c.type, c.slug]));

export function docPath(docType: string | null, docId: string | null): string {
  if (!docType || !docId) return "/";
  if (docType === "PR") return `/purchase-request/${docId}`;
  const slug = BY_TYPE.get(docType);
  return slug ? `/d/${slug}/${docId}` : "/";
}

export function appBaseUrl(env: Record<string, string | undefined> = process.env): string {
  const raw = (env.APP_URL || env.NEXT_PUBLIC_SITE_URL || (env.VERCEL_PROJECT_PRODUCTION_URL ? `https://${env.VERCEL_PROJECT_PRODUCTION_URL}` : "") || "https://hmihub.vercel.app").trim();
  return raw.replace(/\/+$/, "");
}

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

export function buildEmail(subject: string, message: string, url: string): { subject: string; text: string; html: string } {
  const lines = message.split("\n").map((l) => l.trim()).filter(Boolean);
  const [head, ...rest] = lines;
  const text = `${message.trim()}\n\nBuka dokumen: ${url}\n\n-- HMI Hub (email otomatis). Untuk berhenti menerima, buka menu Notifikasi di HMI Hub.`;
  const html = `<!doctype html><html lang="id"><body style="margin:0;background:#f4f1ec;font-family:Arial,Helvetica,sans-serif;color:#222">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:24px 12px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#fff;border-radius:12px;overflow:hidden">
<tr><td style="background:#c2410c;color:#fff;padding:16px 24px;font-size:18px;font-weight:bold">HMI Hub</td></tr>
<tr><td style="padding:24px">
<p style="margin:0 0 12px;font-size:18px;font-weight:bold">${esc(head ?? subject)}</p>
${rest.map((l) => `<p style="margin:0 0 8px;font-size:15px;line-height:1.5">${esc(l)}</p>`).join("\n")}
<p style="margin:24px 0"><a href="${esc(url)}" style="background:#c2410c;color:#fff;text-decoration:none;padding:12px 24px;border-radius:8px;font-weight:bold;display:inline-block">Buka dokumen</a></p>
<p style="margin:0;font-size:12px;color:#777">Email otomatis dari HMI Hub. Untuk berhenti menerima, buka menu Notifikasi di HMI Hub.</p>
</td></tr></table></td></tr></table></body></html>`;
  return { subject: `[HMI Hub] ${subject}`, text, html };
}
