import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { NotifSettings } from "@/components/notif-settings";
import { mailConfigured } from "@/lib/notify/send";

type Rule = { id: number; source: string; doc_type: string | null; to_status: string; module: string; action: string; title: string; todo: string };

export default async function NotifikasiPage() {
  const session = await requireSession();
  const supabase = await createClient();
  const [{ data: pref }, { data: rules }] = await Promise.all([
    supabase.from("notification_prefs").select("email_enabled").eq("user_id", session.userId).maybeSingle(),
    supabase.from("notification_rules").select("id, source, doc_type, to_status, module, action, title, todo").eq("is_active", true).order("id"),
  ]);
  // Daftar yang akan Anda terima = aturan yang izinnya Anda miliki (sama dengan yang dipakai database saat mengirim).
  const mine = ((rules ?? []) as Rule[]).filter((r) => session.can(r.module, r.action));
  return (
    <div>
      <h1 className="mb-2 text-3xl font-bold">Notifikasi Email</h1>
      <p className="mb-6 max-w-2xl text-lg">Anda diberi tahu lewat email saat dokumen sampai pada langkah yang menjadi tugas Anda, sesuai hak akses role Anda. Perubahan yang Anda lakukan sendiri tidak dikirim ke Anda.</p>
      <NotifSettings enabled={pref?.email_enabled ?? true} configured={mailConfigured()} />
      <h2 className="mb-3 mt-10 text-2xl font-bold">Yang akan Anda terima</h2>
      {mine.length === 0 ? (
        <p className="text-lg">Role Anda belum memiliki langkah yang memicu email.</p>
      ) : (
        <ul className="max-w-2xl space-y-3">
          {mine.map((r) => (
            <li key={r.id} className="rounded-md border-2 border-line bg-white px-4 py-3">
              <p className="font-semibold">{r.title}</p>
              <p>{r.todo}</p>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
