import Link from "next/link";
import { NAV } from "@/lib/nav";
import type { Session } from "@/lib/auth";
import { logout } from "@/app/login/actions";
import { SidebarNav } from "./sidebar-nav";

// Menu disaring dari izin user. Ini hanya tampilan; akses sebenarnya
// tetap diperiksa di server pada setiap halaman dan di database (RLS).
export function Sidebar({ session }: { session: Session }) {
  const groups = NAV.map((g) => ({
    title: g.title,
    items: g.items
      .filter((i) => session.can(i.module, "view"))
      .map((i) => ({ slug: i.slug, label: i.label, href: i.href ?? `/${i.slug}` })),
  })).filter((g) => g.items.length > 0);

  return (
    <aside className="m-3 flex flex-col rounded-2xl bg-side text-side-fg md:sticky md:top-3 md:m-3 md:h-[calc(100vh-1.5rem)] md:w-72 md:shrink-0">
      <div className="p-3">
        <Link
          href="/"
          className="flex items-center gap-3 rounded-xl px-4 py-4 text-white"
          style={{ background: "linear-gradient(135deg,#c2410c 0%,#e8590c 55%,#f59e0b 100%)" }}
        >
          <span className="grid h-10 w-10 shrink-0 place-items-center rounded-lg bg-black/25 text-lg font-bold">H</span>
          <span className="leading-tight">
            <span className="block text-xl font-bold">HMI Hub</span>
            <span className="block text-[0.72rem] opacity-90">PT Harmoni Mitra Inovindo</span>
          </span>
        </Link>
      </div>
      <SidebarNav groups={groups} showDashboard={session.can("dashboard", "view")} />
      <div className="border-t border-side-line p-4">
        <p className="font-semibold text-white">{session.fullName}</p>
        <p className="mb-3 text-sm text-side-mute">{session.roleName}</p>
        <form action={logout}>
          <button
            type="submit"
            className="w-full rounded-full border border-side-line px-4 py-2 font-semibold text-side-fg hover:bg-side-act"
          >
            Keluar
          </button>
        </form>
      </div>
    </aside>
  );
}
