"use client";

import { useState, useTransition } from "react";
import { sendMyTestEmail, setEmailNotif, type NotifState } from "@/app/(app)/notifikasi/actions";

export function NotifSettings({ enabled, configured }: { enabled: boolean; configured: boolean }) {
  const [on, setOn] = useState(enabled);
  const [res, setRes] = useState<NotifState>({});
  const [pending, start] = useTransition();
  const toggle = () => start(async () => { const next = !on; const r = await setEmailNotif(next); setRes(r); if (!r.error) setOn(next); });
  const test = () => start(async () => setRes(await sendMyTestEmail()));
  return (
    <div className="max-w-xl space-y-4">
      <label className="flex items-center gap-3 text-lg">
        <input type="checkbox" checked={on} onChange={toggle} disabled={pending} className="h-6 w-6" />
        <span className="font-semibold">Kirim notifikasi ke email saya</span>
      </label>
      <button type="button" onClick={test} disabled={pending || !configured} className="rounded-md border-2 border-brand px-6 py-2 font-semibold text-brand hover:bg-warn-bg disabled:opacity-60">
        {pending ? "Memproses..." : "Kirim email uji ke saya"}
      </button>
      {!configured && <p className="rounded-md bg-warn-bg px-4 py-3">Pengirim email belum diatur di server, jadi belum ada email yang terkirim. Hubungi Owner.</p>}
      {res.error && <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-danger">{res.error}</p>}
      {res.message && <p role="status" className="rounded-md bg-warn-bg px-4 py-3">{res.message}</p>}
    </div>
  );
}
