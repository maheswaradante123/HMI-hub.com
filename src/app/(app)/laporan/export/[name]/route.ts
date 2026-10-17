import { getSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { REPORTS, toCsv } from "@/lib/reports";
import { isRealDate } from "@/lib/pricing/schema";

export async function GET(req: Request, { params }: { params: Promise<{ name: string }> }) {
  const { name } = await params;
  const session = await getSession();
  if (!session) return new Response("Silakan masuk terlebih dahulu.", { status: 401 });
  const report = REPORTS.find((r) => r.key === name);
  if (!report) return new Response("Laporan tidak ditemukan.", { status: 404 });
  if (!session.can("report", "export") || !session.can(report.module, "view") || (report.needs && !session.can(...report.needs))) {
    return new Response("Anda tidak memiliki izin mengunduh laporan ini.", { status: 403 });
  }

  const url = new URL(req.url);
  const from = url.searchParams.get("dari") ?? "";
  const to = url.searchParams.get("sampai") ?? "";
  if ((from && !isRealDate(from)) || (to && !isRealDate(to))) return new Response("Tanggal tidak benar.", { status: 400 });

  const supabase = await createClient();
  let q = supabase.from(report.table).select(report.select).order(report.order, { ascending: false }).limit(10000);
  if (report.dateCol && from) q = q.gte(report.dateCol, from);
  if (report.dateCol && to) q = q.lte(report.dateCol, to);
  if (report.filter) {
    const f = report.filter;
    q = f.op === "eq" ? q.eq(f.column, f.value as string) : f.op === "neq" ? q.neq(f.column, f.value as string) : q.in(f.column, f.value as string[]);
  }
  const { data, error } = await q;
  if (error) return new Response("Laporan belum bisa dibuat. Coba lagi.", { status: 500 });

  const stamp = new Date().toLocaleDateString("sv-SE", { timeZone: "Asia/Jakarta" });
  return new Response(toCsv(data ?? [], report.cols), {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="${report.key}-${stamp}.csv"`,
      "Cache-Control": "no-store",
    },
  });
}
