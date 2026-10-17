"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";

export type NavLinkData = { slug: string; label: string; href: string };
export type NavGroupData = { title: string; items: NavLinkData[] };

const ICON: Record<string, string> = {
  Beranda: "M3 11l9-8 9 8M5 10v10h5v-6h4v6h5V10",
  Operasional: "M21 8l-9-5-9 5v8l9 5 9-5V8zM3 8l9 5 9-5M12 13v8",
  Purchasing: "M3 4h2l2.4 11h10.2L20 7H6M9 20a1 1 0 100-2 1 1 0 000 2zM17 20a1 1 0 100-2 1 1 0 000 2z",
  "Qurban Cerdas": "M5 20V9l7-5 7 5v11M9 20v-6h6v6M3 20h18",
  Sales: "M3 12l9-9h8v8l-9 9-8-8zM15 7.5h.01",
  Accounting: "M6 3h9l4 4v14H6V3zM15 3v4h4M9 12h7M9 16h7",
  "Master Data": "M4 6c0-1.7 3.6-3 8-3s8 1.3 8 3-3.6 3-8 3-8-1.3-8-3zM4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3",
  Laporan: "M4 20V10M10 20V4M16 20v-8M22 20H2",
  Admin: "M12 3l8 3v6c0 5-3.500 8-8 9-4.500-1-8-4-8-9V6l8-3z",
};

function Icon({ name }: { name: string }) {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={ICON[name] ?? ICON.Operasional} />
    </svg>
  );
}

function isActive(pathname: string, href: string) {
  const base = href.split("?")[0];
  if (base === "/") return pathname === "/";
  return pathname === base || pathname.startsWith(base + "/");
}

export function SidebarNav({ groups, showDashboard }: { groups: NavGroupData[]; showDashboard: boolean }) {
  const pathname = usePathname();
  // Menu aktif = alamat paling panjang yang cocok, supaya "/qurban" tidak ikut menyala di "/qurban/proforma".
  const best = groups.flatMap((g) => g.items).filter((i) => isActive(pathname, i.href)).sort((a, b) => b.href.length - a.href.length)[0]?.href;
  const [closed, setClosed] = useState<Record<string, boolean>>({});
  const [mobileOpen, setMobileOpen] = useState(false);

  return (
    <>
    <button
      type="button"
      onClick={() => setMobileOpen((v) => !v)}
      aria-expanded={mobileOpen}
      className="mx-3 mb-2 rounded-xl bg-side-act px-4 py-2.5 text-left font-semibold md:hidden"
    >
      Menu
    </button>
    <nav className={`${mobileOpen ? "block" : "hidden"} min-h-0 flex-1 overflow-y-auto px-3 py-2 md:block`} aria-label="Menu utama">
      {showDashboard && (
        <Link
          href="/"
          className={`flex items-center gap-3 rounded-xl px-3 py-2.5 font-semibold ${
            pathname === "/" ? "bg-side-act text-white" : "text-side-fg hover:bg-side-act/60"
          }`}
        >
          <Icon name="Beranda" />
          Beranda
        </Link>
      )}
      {groups.map((g) => {
        const hasActive = g.items.some((i) => i.href === best);
        const open = closed[g.title] === undefined ? true : !closed[g.title];
        return (
          <div key={g.title} className="mt-1">
            <button
              type="button"
              onClick={() => setClosed((c) => ({ ...c, [g.title]: open }))}
              aria-expanded={open}
              className={`flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left font-semibold ${
                hasActive ? "text-white" : "text-side-fg"
              } hover:bg-side-act/60`}
            >
              <Icon name={g.title} />
              <span className="flex-1">{g.title}</span>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" className={`text-side-mute transition-transform ${open ? "" : "-rotate-90"}`} aria-hidden="true">
                <path d="M6 9l6 6 6-6" />
              </svg>
            </button>
            {open && (
              <ul className="ml-[1.35rem] border-l border-side-line pl-2">
                {g.items.map((i) => {
                  const on = i.href === best;
                  return (
                    <li key={i.slug}>
                      <Link
                        href={i.href}
                        aria-current={on ? "page" : undefined}
                        className={`block rounded-xl px-3 py-2 text-[0.95rem] ${
                          on ? "bg-side-act font-semibold text-white" : "text-side-mute hover:bg-side-act/60 hover:text-side-fg"
                        }`}
                      >
                        {i.label}
                      </Link>
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
        );
      })}
    </nav>
    </>
  );
}
