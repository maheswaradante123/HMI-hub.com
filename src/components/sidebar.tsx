import Link from "next/link";
import { NAV } from "@/lib/nav";
import type { Session } from "@/lib/auth";
import { logout } from "@/app/login/actions";

// Menu disaring dari izin user. Ini hanya tampilan; akses sebenarnya
// tetap diperiksa di server pada setiap halaman dan di database (RLS).
export function Sidebar({ session }: { session: Session }) {
  const groups = NAV.map((g) => ({
    ...g,
    items: g.items.filter((i) => session.can(i.module, "view")),
  })).filter((g) => g.items.length > 0);

  return (
    <aside className="flex w-full flex-col border-b border-line bg-surface md:min-h-screen md:w-72 md:border-b-0 md:border-r">
      <div className="border-b border-line px-5 py-4">
        <Link href="/" className="text-2xl font-bold text-brand">
          HMI
        </Link>
        <p className="text-sm text-muted">Internal System</p>
      </div>
      <nav className="flex-1 overflow-y-auto px-3 py-3" aria-label="Menu utama">
        {session.can("dashboard", "view") && (
          <Link
            href="/"
            className="block rounded-md px-3 py-2.5 text-lg font-semibold hover:bg-background"
          >
            Dashboard
          </Link>
        )}
        {groups.map((g) => (
          <div key={g.title} className="mt-4">
            <p className="px-3 pb-1 text-base font-bold text-muted">{g.title}</p>
            <ul>
              {g.items.map((i) => (
                <li key={i.slug}>
                  <Link
                    href={i.href ?? `/${i.slug}`}
                    className="block rounded-md px-3 py-2.5 text-lg hover:bg-background"
                  >
                    {i.label}
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </nav>
      <div className="border-t border-line px-5 py-4">
        <p className="font-semibold">{session.fullName}</p>
        <p className="mb-3 text-sm text-muted">{session.roleName}</p>
        <form action={logout}>
          <button
            type="submit"
            className="w-full rounded-md border-2 border-line px-4 py-2.5 text-lg font-semibold hover:bg-background"
          >
            Keluar
          </button>
        </form>
      </div>
    </aside>
  );
}
