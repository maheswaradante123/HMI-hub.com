"use client";

import { Suspense, useEffect, useRef, useState } from "react";
import { usePathname, useSearchParams } from "next/navigation";

// Garis oranye di atas layar muncul begitu tautan diklik dan hilang saat halaman
// tujuan tampil. Berlaku untuk semua perpindahan, termasuk ganti filter.
function Bar() {
  const pathname = usePathname();
  const search = useSearchParams().toString();
  const key = `${pathname}?${search}`;
  const keyRef = useRef(key);
  const [startedAt, setStartedAt] = useState<string | null>(null);

  useEffect(() => {
    keyRef.current = key;
  }, [key]);

  useEffect(() => {
    function onClick(e: MouseEvent) {
      if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
      const a = (e.target as HTMLElement | null)?.closest("a");
      if (!a || a.target || a.hasAttribute("download")) return;
      const u = new URL(a.href, window.location.href);
      if (u.origin !== window.location.origin) return;
      if (u.pathname === window.location.pathname && u.search === window.location.search) return;
      const from = keyRef.current;
      setStartedAt(from);
      window.setTimeout(() => setStartedAt((cur) => (cur === from ? null : cur)), 20000);
    }
    document.addEventListener("click", onClick, true);
    return () => document.removeEventListener("click", onClick, true);
  }, []);

  if (startedAt === null || startedAt !== key) return null;
  return <div className="navbar fixed left-0 top-0 z-50 h-[3px] bg-accent no-print" aria-hidden="true" />;
}

export function NavProgress() {
  return (
    <Suspense fallback={null}>
      <Bar />
    </Suspense>
  );
}
