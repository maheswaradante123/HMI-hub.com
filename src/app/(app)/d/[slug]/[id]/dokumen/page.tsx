import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { JcpDocsForm } from "@/components/jcp-docs-form";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Melengkapi atau merevisi dokumen CPJ yang sudah lewat (ACC atau direalisasi). Angka jurnal tidak berubah.
export default async function JcpDocsPage({ params }: { params: Promise<{ slug: string; id: string }> }) {
  const { slug, id } = await params;
  if (slug !== "jcp" || !UUID.test(id)) notFound();
  const session = await requireSession();
  if (!session.can("cpj_journal", "edit")) return <Forbidden roleName={session.roleName} what="pelengkapan dokumen CPJ" />;

  const supabase = await createClient();
  const { data } = await supabase.from("cash_journals").select("id, doc_number, journal_date, status, cash_journal_lines(*)").eq("id", id).is("deleted_at", null).maybeSingle();
  if (!data) notFound();
  const doc = data as unknown as { doc_number: string; journal_date: string; status: string; cash_journal_lines: Record<string, unknown>[] };
  if (doc.status === "VOID") {
    return (
      <div className="max-w-2xl">
        <h1 className="text-3xl font-bold">Tidak bisa diubah</h1>
        <p className="mt-3 rounded-md bg-warn-bg px-4 py-3">Jurnal ini sudah dibatalkan.</p>
      </div>
    );
  }
  const lines = doc.cash_journal_lines.slice().sort((a, b) => Number(a.line_no) - Number(b.line_no)).map((l) => ({
    line_no: Number(l.line_no), trans_date: String(l.trans_date ?? ""), ac: String(l.ac ?? ""), code: String(l.code ?? ""), description: String(l.description ?? ""),
    price: Number(l.price), qty: Number(l.qty), flag: String(l.flag),
    real_price: l.real_price === null ? null : Number(l.real_price), real_qty: l.real_qty === null ? null : Number(l.real_qty),
    proof: String(l.proof ?? ""), details: l.details ?? [],
  }));
  return (
    <div className="max-w-[1500px]">
      <p className="text-sm text-muted"><Link href="/d/jcp" className="underline">Cash Payment Journal</Link> › <Link href={`/d/jcp/${id}`} className="underline">{doc.doc_number}</Link> › Lengkapi dokumen</p>
      <h1 className="mb-2 mt-1 text-3xl font-bold">Lengkapi dokumen {doc.doc_number}</h1>
      <p className="mb-6 max-w-3xl text-muted">Tambah atau revisi dokumen pendukung dan rincian Petty Cash untuk jurnal ini. Angka rencana dan realisasi tidak berubah di sini. File langsung tersimpan di Google Drive saat diunggah; tekan Simpan supaya tautan foldernya tercatat di jurnal.</p>
      <JcpDocsForm id={id} number={doc.doc_number} journalDate={doc.journal_date} status={doc.status} lines={lines} cancelHref={`/d/jcp/${id}`} />
    </div>
  );
}
