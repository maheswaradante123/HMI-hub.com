import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { fmtRupiah } from "@/lib/docs/format";

type Summary = Partial<Record<"low_stock" | "pr_waiting" | "prod_waiting" | "ro_open" | "pl_on_the_way" | "receivable_total" | "receivable_overdue" | "cash_in_month" | "cash_out_month", number>>;

export default async function DashboardPage() {
  const session = await requireSession();
  const allowed = session.can("dashboard", "view");
  let s: Summary = {};
  if (allowed) {
    const supabase = await createClient();
    const { data } = await supabase.rpc("dashboard_summary");
    s = (data ?? {}) as Summary;
  }
  const cards: { key: keyof Summary; label: string; href: string; money?: boolean; warn?: (n: number) => boolean }[] = [
    { key: "pr_waiting", label: "PR menunggu persetujuan", href: "/purchase-request?status=SUBMITTED", warn: (n) => n > 0 },
    { key: "prod_waiting", label: "Production Order menunggu persetujuan", href: "/d/prod?status=SUBMITTED", warn: (n) => n > 0 },
    { key: "low_stock", label: "Item stok menipis", href: "/stok?hanya=menipis", warn: (n) => n > 0 },
    { key: "ro_open", label: "RO terkonfirmasi (belum selesai)", href: "/d/ro?status=CONFIRMED" },
    { key: "pl_on_the_way", label: "Pengiriman belum terkonfirmasi", href: "/pengiriman" },
    { key: "receivable_total", label: "Total piutang", href: "/d/inv", money: true },
    { key: "receivable_overdue", label: "Piutang lewat jatuh tempo", href: "/d/inv", money: true, warn: (n) => n > 0 },
    { key: "cash_in_month", label: "Kas masuk bulan ini", href: "/d/crj", money: true },
    { key: "cash_out_month", label: "Kas keluar bulan ini", href: "/d/cpj", money: true },
  ];
  const shown = cards.filter((c) => s[c.key] !== undefined);

  return (
    <div className="max-w-5xl">
      <h1 className="text-3xl font-bold">Selamat datang, {session.fullName}</h1>
      <p className="mt-1 text-muted">Masuk sebagai {session.roleName}</p>
      {!allowed ? (
        <p className="mt-8 rounded-lg border border-line bg-surface p-6">Role Anda belum memiliki akses ke Dashboard. Gunakan menu di sebelah kiri.</p>
      ) : shown.length === 0 ? (
        <p className="mt-8 rounded-lg border border-line bg-surface p-6">Belum ada ringkasan untuk role Anda. Gunakan menu di sebelah kiri.</p>
      ) : (
        <ul className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {shown.map((c) => {
            const v = Number(s[c.key]);
            const warn = c.warn?.(v);
            return (
              <li key={c.key}>
                <Link href={c.href} className={`block h-full rounded-lg border-2 p-5 hover:bg-background ${warn ? "border-amber-500 bg-warn-bg" : "border-line bg-surface"}`}>
                  <p className="text-muted">{c.label}</p>
                  <p className="mt-1 text-3xl font-bold tabular-nums">{c.money ? fmtRupiah(v) : v}</p>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
