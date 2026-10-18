import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { fmtDate, fmtQty, fmtRupiah } from "@/lib/docs/format";
import { todayJakarta } from "@/lib/pricing/data";

type Summary = Partial<Record<"low_stock" | "pr_waiting" | "prod_waiting" | "ro_open" | "pl_on_the_way" | "receivable_total" | "receivable_overdue" | "cash_in_month" | "cash_out_month", number>>;
type Rel<T> = T | T[] | null;
const one = <T,>(v: Rel<T>): T | null => (Array.isArray(v) ? (v[0] ?? null) : v);

const MONTHS = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];
const DAYS = ["Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab"];
const card = "rounded-lg border border-line bg-surface p-6";
const tile = "block rounded-xl border border-line bg-surface p-4 transition hover:border-foreground";

// Pintasan "Things to do": sama dengan preview, hanya untuk modul yang boleh dibuat user.
const TODO = [
  { module: "ro", label: "Request Order baru", note: "Catat pesanan pelanggan, termasuk pelanggan baru.", href: "/d/ro/baru" },
  { module: "production_order", label: "Production Order baru", note: "Hanya untuk RO tanpa PO aktif.", href: "/d/prod/baru" },
  { module: "carcass_weighing", label: "Timbang karkas", note: "Item, kategori dan berat diisi manual.", href: "/d/cw/baru" },
  { module: "packing_list", label: "Packing List baru", note: "Isi berat per item.", href: "/d/pl/baru" },
  { module: "invoice", label: "Invoice baru", note: "Dibuat dari Packing List.", href: "/d/inv/baru" },
  { module: "purchase_analysis", label: "Analisa pembelian baru", note: "Qty ditarik dari penimbangan.", href: "/d/ap/baru" },
] as const;

// Perhatian tambahan (persetujuan, pengiriman, kas) yang sudah ada sejak awal; tetap ditampilkan di bawah.
const ATTENTION: { key: keyof Summary; label: string; href: string; money?: boolean; warn?: (n: number) => boolean }[] = [
  { key: "pr_waiting", label: "PR menunggu persetujuan", href: "/purchase-request?tab=item&status=SUBMITTED", warn: (n) => n > 0 },
  { key: "prod_waiting", label: "Production Order menunggu persetujuan", href: "/d/prod?status=SUBMITTED", warn: (n) => n > 0 },
  { key: "pl_on_the_way", label: "Pengiriman belum terkonfirmasi", href: "/d/pl" },
  { key: "receivable_overdue", label: "Piutang lewat jatuh tempo", href: "/d/inv", money: true, warn: (n) => n > 0 },
  { key: "cash_in_month", label: "Kas masuk bulan ini", href: "/d/crj", money: true },
  { key: "cash_out_month", label: "Kas keluar bulan ini", href: "/d/cpj", money: true },
];

export default async function DashboardPage() {
  const session = await requireSession();
  const allowed = session.can("dashboard", "view");
  const supabase = await createClient();
  const today = todayJakarta();
  const [yy, mm] = [Number(today.slice(0, 4)), Number(today.slice(5, 7))];
  const first = `${today.slice(0, 7)}-01`;
  const daysInMonth = new Date(Date.UTC(yy, mm, 0)).getUTCDate();
  const last = `${today.slice(0, 7)}-${String(daysInMonth).padStart(2, "0")}`;
  const canRo = allowed && session.can("ro", "view");
  const canStock = allowed && session.can("stock", "view");
  const canAp = allowed && session.can("purchase_analysis", "view");

  const count = (status: string) => supabase.from("request_orders").select("id", { count: "exact", head: true }).eq("status", status).is("deleted_at", null);
  const [sum, stockRows, low, apLast, draft, confirmed, done, recent, sends] = await Promise.all([
    allowed ? supabase.rpc("dashboard_summary") : Promise.resolve({ data: null }),
    canStock ? supabase.from("v_stock_summary").select("qty").limit(5000) : Promise.resolve({ data: null }),
    canStock ? supabase.from("v_stock_summary").select("product_id, name, qty, min_stock").eq("is_low", true).order("qty").limit(8) : Promise.resolve({ data: null }),
    canAp ? supabase.from("v_purchase_analysis").select("doc_number, profit").neq("status", "VOID").order("analysis_date", { ascending: false }).order("doc_number", { ascending: false }).limit(1) : Promise.resolve({ data: null }),
    canRo ? count("DRAFT") : Promise.resolve({ count: null }),
    canRo ? count("CONFIRMED") : Promise.resolve({ count: null }),
    canRo ? count("COMPLETED") : Promise.resolve({ count: null }),
    canRo ? supabase.from("request_orders").select("id, doc_number, delivery_date, est_pay_date, total_amount, customers(name)").is("deleted_at", null).order("created_at", { ascending: false }).limit(3) : Promise.resolve({ data: null }),
    canRo ? supabase.from("request_orders").select("delivery_date").is("deleted_at", null).neq("status", "CANCELLED").gte("delivery_date", first).lte("delivery_date", last) : Promise.resolve({ data: null }),
  ]);
  const s = (sum.data ?? {}) as Summary;
  const totalStock = (stockRows.data ?? []).reduce((t, r) => t + Number(r.qty), 0);
  const latestAp = apLast.data?.[0];
  const sendCount = new Map<string, number>();
  for (const r of sends.data ?? []) if (r.delivery_date) sendCount.set(String(r.delivery_date), (sendCount.get(String(r.delivery_date)) ?? 0) + 1);

  const kpis: [string, string][] = [];
  if (stockRows.data) kpis.push(["Total stok", `${fmtQty(totalStock)} Kg`]);
  if (s.receivable_total !== undefined) kpis.push(["Piutang berjalan", fmtRupiah(Number(s.receivable_total))]);
  if (draft.count !== null) kpis.push(["RO aktif", String((draft.count ?? 0) + (confirmed.count ?? 0))]);
  if (latestAp) kpis.push(["Laba analisa terakhir", fmtRupiah(Number(latestAp.profit))]);
  const todo = TODO.filter((t) => session.can(t.module, "create"));
  const attention = ATTENTION.filter((a) => s[a.key] !== undefined);

  const tgl = new Intl.DateTimeFormat("id-ID", { day: "2-digit", month: "long", year: "numeric", timeZone: "Asia/Jakarta" }).format(new Date());
  const nama = session.fullName.split(" ")[0];
  const blanks = new Date(Date.UTC(yy, mm - 1, 1)).getUTCDay();

  return (
    <div className="max-w-6xl">
      <h1 className="text-3xl font-bold">Hi, {nama}</h1>
      <p className="mt-1 text-muted">{session.roleName} · {tgl}</p>
      {!allowed && <p className="mt-6 rounded-lg border border-line bg-surface p-6">Role Anda belum memiliki akses ke Dashboard. Gunakan menu di sebelah kiri.</p>}

      <div className="mt-6 grid items-start gap-6 lg:grid-cols-2">
        <div className="grid gap-6">
          {kpis.length > 0 && (
            <section className={card} aria-labelledby="h-ringkasan">
              <h2 id="h-ringkasan" className="text-xl font-bold">Ringkasan</h2>
              <dl className="mt-4 grid gap-3 sm:grid-cols-2">
                {kpis.map(([k, v]) => <div key={k} className="rounded-xl border border-line p-4"><dt className="text-sm text-muted">{k}</dt><dd className="mt-1 text-2xl font-bold tabular-nums">{v}</dd></div>)}
              </dl>
            </section>
          )}

          {canRo && (
            <section className={card} aria-labelledby="h-ro">
              <h2 id="h-ro" className="text-xl font-bold">Request Order</h2>
              <div className="mt-4 flex flex-wrap gap-2">
                {([["DRAFT", "Draf", draft.count], ["CONFIRMED", "Dikonfirmasi", confirmed.count], ["COMPLETED", "Selesai", done.count]] as const).map(([st, label, n]) => (
                  <Link key={st} href={`/d/ro?status=${st}`} className="rounded-full border-2 border-line px-4 py-1.5 font-semibold hover:bg-background">{label} <span className="ml-1 rounded-full bg-background px-2 tabular-nums">{n ?? 0}</span></Link>
                ))}
              </div>
              <ul className="mt-4 grid gap-2">
                {(recent.data ?? []).map((r) => (
                  <li key={r.id}>
                    <Link href={`/d/ro/${r.id}`} className={tile}>
                      <b>{r.doc_number} · {one(r.customers as Rel<{ name: string }>)?.name ?? "-"}</b>
                      <span className="block text-muted">Kirim {r.delivery_date ? fmtDate(String(r.delivery_date)) : "-"} · Estimasi bayar {r.est_pay_date ? fmtDate(String(r.est_pay_date)) : "-"} · {fmtRupiah(Number(r.total_amount))}</span>
                    </Link>
                  </li>
                ))}
                {(recent.data ?? []).length === 0 && <li className="text-muted">Belum ada Request Order.</li>}
              </ul>
            </section>
          )}

          <section className={card} aria-labelledby="h-todo">
            <h2 id="h-todo" className="text-xl font-bold">Things to do</h2>
            {todo.length ? (
              <ul className="mt-4 grid gap-2 sm:grid-cols-2">
                {todo.map((t) => <li key={t.href}><Link href={t.href} className={`${tile} h-full`}><b>{t.label}</b><span className="block text-muted">{t.note}</span></Link></li>)}
              </ul>
            ) : <p className="mt-3 text-muted">Akun ini hanya punya hak lihat.</p>}
          </section>
        </div>

        <div className="grid gap-6">
          {canStock && (
            <section className={card} aria-labelledby="h-low">
              <h2 id="h-low" className="text-xl font-bold">Stok menipis</h2>
              {(low.data ?? []).length ? (
                <>
                  <ul className="mt-3">
                    {(low.data ?? []).map((i) => (
                      <li key={i.product_id} className="flex justify-between gap-3 border-b border-line py-2 last:border-0">
                        <Link href={`/stok/${i.product_id}`} className="underline">{i.name}</Link>
                        <b className="tabular-nums text-danger">{fmtQty(Number(i.qty))} Kg</b>
                      </li>
                    ))}
                  </ul>
                  <p className="mt-3"><Link href="/stok?hanya=menipis" className="font-semibold text-brand underline">Lihat semua yang menipis ({s.low_stock ?? (low.data ?? []).length})</Link></p>
                </>
              ) : <p className="mt-3 text-muted">Semua stok aman</p>}
            </section>
          )}

          {canRo && (
            <section className={card} aria-labelledby="h-kal">
              <h2 id="h-kal" className="text-xl font-bold">{MONTHS[mm - 1]} {yy}</h2>
              <div className="mt-4 grid grid-cols-7 gap-1 text-center" role="grid" aria-label={`Kalender ${MONTHS[mm - 1]} ${yy}`}>
                {DAYS.map((d) => <span key={d} role="columnheader" className="text-sm font-semibold text-muted">{d}</span>)}
                {Array.from({ length: blanks }, (_, i) => <span key={`b${i}`} />)}
                {Array.from({ length: daysInMonth }, (_, i) => {
                  const iso = `${today.slice(0, 7)}-${String(i + 1).padStart(2, "0")}`;
                  const isToday = iso === today;
                  const n = sendCount.get(iso) ?? 0;
                  return (
                    <span key={iso} role="gridcell" aria-label={`${i + 1}${isToday ? ", hari ini" : ""}${n ? `, ${n} jadwal kirim RO` : ""}`}
                      className={`relative rounded-md py-2 tabular-nums ${isToday ? "bg-brand font-bold text-white" : ""}`}>
                      {i + 1}
                      {n > 0 && !isToday && <i aria-hidden className="absolute bottom-0.5 left-1/2 h-1.5 w-1.5 -translate-x-1/2 rounded-full bg-accent" />}
                    </span>
                  );
                })}
              </div>
              <p className="mt-3 text-sm text-muted">Titik oranye = jadwal kirim RO.</p>
            </section>
          )}

          {attention.length > 0 && (
            <section className={card} aria-labelledby="h-att">
              <h2 id="h-att" className="text-xl font-bold">Perlu perhatian</h2>
              <ul className="mt-4 grid gap-2">
                {attention.map((a) => {
                  const v = Number(s[a.key]);
                  const warn = a.warn?.(v);
                  return (
                    <li key={a.key}>
                      <Link href={a.href} className={`flex items-center justify-between gap-3 rounded-xl border p-3 transition hover:border-foreground ${warn ? "border-accent bg-accent-soft" : "border-line bg-surface"}`}>
                        <span className="text-muted">{a.label}</span><b className="text-lg tabular-nums">{a.money ? fmtRupiah(v) : v}</b>
                      </Link>
                    </li>
                  );
                })}
              </ul>
            </section>
          )}
        </div>
      </div>
    </div>
  );
}
