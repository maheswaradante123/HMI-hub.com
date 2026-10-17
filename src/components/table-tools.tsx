"use client";

import { useEffect } from "react";
import { usePathname } from "next/navigation";

// Menambahkan urut (klik kepala kolom) dan saring (kotak di bawah kepala) pada setiap tabel daftar.
// Tabel yang berisi isian formulir, atau bertanda data-no-tools, dibiarkan apa adanya.
const MONTHS = ["januari", "februari", "maret", "april", "mei", "juni", "juli", "agustus", "september", "oktober", "november", "desember"];

type St = { f: string[]; col: number | null; dir: "asc" | "desc" | null };

function value(td: HTMLTableCellElement): { n?: number; s?: string } {
  const t = (td.textContent || "").trim();
  const d = t.match(/^(\d{1,2}) ([A-Za-z]+) (\d{4})$/);
  if (d) {
    const i = MONTHS.indexOf(d[2].toLowerCase());
    if (i >= 0) return { n: Date.UTC(+d[3], i, +d[1]) };
  }
  const x = t.replace(/^Rp\s*/i, "").replace(/\s*(Kg|hari|Hari)$/, "").trim();
  if (/^-?[\d.,]+$/.test(x) && /\d/.test(x)) {
    const n = parseFloat(x.replace(/\./g, "").replace(",", "."));
    if (!isNaN(n)) return { n };
  }
  return { s: t.toLowerCase() };
}

function apply(tb: HTMLTableElement, st: St) {
  const body = tb.tBodies[0];
  if (!body) return;
  const rows = Array.from(body.rows).filter((r) => !r.classList.contains("tt-none") && !Array.from(r.cells).some((c) => c.colSpan > 1));
  rows.forEach((r) => {
    const ok = st.f.every((q, i) => !q || (r.cells[i]?.textContent || "").toLowerCase().includes(q.toLowerCase()));
    r.style.display = ok ? "" : "none";
  });
  if (st.col !== null && st.dir) {
    const k = st.dir === "asc" ? 1 : -1;
    const c = st.col;
    rows.sort((a, b) => {
      const x = value(a.cells[c]), y = value(b.cells[c]);
      if (x.n !== undefined && y.n !== undefined) return (x.n - y.n) * k;
      if (x.n !== undefined) return -1;
      if (y.n !== undefined) return 1;
      return (x.s || "").localeCompare(y.s || "", "id", { numeric: true }) * k;
    });
    rows.forEach((r) => body.appendChild(r));
  }
  tb.querySelectorAll<HTMLElement>("th[data-tt] i").forEach((ic, i) => {
    ic.textContent = st.col === i && st.dir ? (st.dir === "asc" ? "▲" : "▼") : "⇅";
  });
  const vis = rows.filter((r) => r.style.display !== "none").length;
  let none = body.querySelector<HTMLElement>("tr.tt-none");
  if (rows.length && !vis) {
    if (!none) {
      none = document.createElement("tr");
      none.className = "tt-none";
      const td = document.createElement("td");
      td.colSpan = tb.tHead?.rows[0]?.cells.length ?? 1;
      td.className = "px-4 py-3 text-center";
      td.textContent = "Tidak ada baris yang cocok.";
      none.appendChild(td);
      body.appendChild(none);
    }
  } else none?.remove();
}

function enhance(tb: HTMLTableElement, states: Map<string, St>, key: string) {
  const head = tb.tHead;
  if (!head || head.rows.length !== 1 || tb.dataset.noTools !== undefined || tb.dataset.tt) return;
  const body = tb.tBodies[0];
  if (!body || body.rows.length < 1 || body.querySelector("input,select,textarea")) return;
  tb.dataset.tt = "1";
  const st = states.get(key) ?? { f: [], col: null, dir: null };
  states.set(key, st);
  const hr = head.rows[0];
  Array.from(hr.cells).forEach((th, i) => {
    if (!th.textContent?.trim()) return;
    th.dataset.tt = "1";
    th.style.cursor = "pointer";
    th.style.whiteSpace = "nowrap";
    const ic = document.createElement("i");
    ic.style.cssText = "font-style:normal;opacity:.55;margin-left:4px;font-size:.7em";
    ic.textContent = "⇅";
    th.appendChild(ic);
    th.addEventListener("click", () => {
      if (st.col === i) st.dir = st.dir === "asc" ? "desc" : st.dir === "desc" ? null : "asc";
      else { st.col = i; st.dir = "asc"; }
      apply(tb, st);
    });
  });
  const fr = document.createElement("tr");
  Array.from(hr.cells).forEach((th, i) => {
    const c = document.createElement("th");
    c.style.padding = "2px 6px";
    if (th.textContent?.replace(/[⇅▲▼]/g, "").trim()) {
      const inp = document.createElement("input");
      inp.placeholder = "Filter";
      inp.value = st.f[i] ?? "";
      inp.setAttribute("aria-label", "Filter " + th.textContent.replace(/[⇅▲▼]/g, "").trim());
      inp.style.cssText = "width:100%;min-width:60px;font-size:.8rem;padding:3px 8px;font-weight:400";
      inp.addEventListener("input", () => { st.f[i] = inp.value; apply(tb, st); });
      inp.addEventListener("click", (e) => e.stopPropagation());
      c.appendChild(inp);
    }
    fr.appendChild(c);
  });
  head.appendChild(fr);
  apply(tb, st);
}

export function TableTools() {
  const pathname = usePathname();
  useEffect(() => {
    const states = new Map<string, St>();
    const run = () => {
      document.querySelectorAll<HTMLTableElement>("main table").forEach((tb, ix) => enhance(tb, states, `${pathname}:${ix}`));
    };
    run();
    // Halaman server dapat menyegarkan isinya setelah sebuah aksi; pasang ulang bila tabel baru muncul.
    let t: ReturnType<typeof setTimeout> | undefined;
    const mo = new MutationObserver(() => { clearTimeout(t); t = setTimeout(run, 60); });
    const main = document.querySelector("main");
    if (main) mo.observe(main, { childList: true, subtree: true });
    return () => { mo.disconnect(); clearTimeout(t); };
  }, [pathname]);
  return null;
}
