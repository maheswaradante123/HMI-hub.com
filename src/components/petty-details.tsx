"use client";

import { CpjDocs, folderIdOf } from "@/components/cpj-docs";
import type { FolderFile } from "@/lib/drive/types";
import { parseMoney } from "@/lib/pricing/schema";
import { fmtRupiah } from "@/lib/docs/format";
import { detailFolderName, type JcpDetail } from "@/lib/docs/jcp";

const inp = "w-full rounded-md border-2 border-line bg-white px-2 py-2 text-base";
const money = (v: string) => { const n = parseMoney((v ?? "").trim()); return typeof n === "number" ? n : 0; };

// Rincian bertingkat satu baris Petty Cash: digunakan untuk apa saja, jumlah, dan dokumen (5 jenis) per rincian.
export function PettyDetails({ no, description, defaultDate, target, list, onChange, number, jd, overview, onChanged, hardRule }: {
  no: number; description: string; defaultDate: string; target: number; list: JcpDetail[]; onChange: (l: JcpDetail[]) => void;
  number: string; jd: string; overview: Record<string, FolderFile[]>; onChanged: () => void;
  hardRule: boolean; // true: realisasi baru bisa diselesaikan bila total sama; false: hanya peringatan (jurnal yang sudah direalisasi)
}) {
  const sum = list.reduce((x, d) => x + money(d.amount), 0);
  const diff = target - sum;
  const upd = (k: number, patch: Partial<JcpDetail>) => onChange(list.map((d, j) => (j === k ? { ...d, ...patch } : d)));
  return (
    <div className="rounded-lg border-2 border-brand bg-white p-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="text-lg font-bold">Rincian Petty Cash (baris {no}): digunakan untuk apa saja</h3>
        <p>Realisasi baris ini: <b className="tabular-nums">{fmtRupiah(target)}</b></p>
      </div>
      {list.length === 0 && <p className="mt-2 text-muted">Belum ada rincian. Tambahkan tiap transaksi yang dibayar dari Petty Cash ini; tiap rincian punya dokumen sendiri.</p>}
      <ul className="mt-3 space-y-3">
        {list.map((d, k) => (
          <li key={d.no} className="grid items-start gap-3 md:grid-cols-[2rem_9.5rem_minmax(0,1fr)_10rem_11rem_2.5rem]">
            <span className="pt-2 text-muted">{k + 1}</span>
            <input type="date" aria-label={`Tanggal rincian ${k + 1}`} className={inp} value={d.date} onChange={(e) => upd(k, { date: e.target.value })} />
            <input aria-label={`Digunakan untuk rincian ${k + 1}`} placeholder="Digunakan untuk, mis. Bensin motor" className={inp} value={d.text} onChange={(e) => upd(k, { text: e.target.value })} />
            <input aria-label={`Jumlah rincian ${k + 1}`} inputMode="decimal" placeholder="Jumlah (Rp)" className={`${inp} text-right`} value={d.amount} onChange={(e) => upd(k, { amount: e.target.value })} />
            <div className="flex items-start gap-1">
              <CpjDocs number={number} date={jd} item={detailFolderName(description, d.no)} proof={d.proof} files={overview[folderIdOf(d.proof)] ?? []}
                blocked={!number ? "Simpan dokumen dulu supaya nomor CPJ terbentuk, baru unggah dokumen." : !jd ? "Isi tanggal jurnal dulu." : !d.text.trim() ? "Isi \"Digunakan untuk\" dulu." : undefined}
                onProof={(link) => upd(k, { proof: link })} onChanged={onChanged} />
              {/^https?:\/\//.test(d.proof) && <a href={d.proof} target="_blank" rel="noreferrer" aria-label={`Buka folder dokumen rincian ${k + 1}`} title="Buka folder dokumen" className="px-1 pt-2 text-brand">↗</a>}
            </div>
            <button type="button" aria-label={`Hapus rincian ${k + 1}`} onClick={() => onChange(list.filter((_, j) => j !== k))} className="rounded-md px-2 py-1 text-xl text-danger hover:bg-danger-bg">×</button>
          </li>
        ))}
      </ul>
      <div className="mt-3 flex flex-wrap items-center gap-4">
        <button type="button" onClick={() => onChange([...list, { no: Math.max(0, ...list.map((d) => d.no)) + 1, date: defaultDate || jd, text: "", amount: "", proof: "" }])}
          className="rounded-md border-2 border-brand px-4 py-2 font-semibold text-brand hover:bg-background">+ Tambah rincian</button>
        <p>Total rincian: <b className="tabular-nums">{fmtRupiah(sum)}</b></p>
        <p className={diff === 0 ? "font-semibold text-green-800" : "font-semibold text-danger"}>
          {diff === 0 ? "Sudah sama dengan realisasi" : `Selisih ${fmtRupiah(Math.abs(diff))} (${diff > 0 ? "rincian masih kurang" : "rincian melebihi realisasi"})`}
        </p>
      </div>
      {diff !== 0 && (
        <p className="mt-1 text-sm text-muted">{hardRule ? "Realisasi baru bisa diselesaikan bila total rincian sama dengan Real. Amount baris ini." : "Jurnal ini sudah direalisasi, jadi selisih hanya menjadi peringatan; lengkapi rincian sampai sama."}</p>
      )}
    </div>
  );
}
