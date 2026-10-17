"use client";

import Link from "next/link";
import { useActionState, useMemo, useState } from "react";
import { saveDoc, type DocFormState } from "@/app/(app)/d/actions";
import { RO_PACK } from "@/lib/docs/config";
import type { PoRo } from "@/lib/docs/ro-lists";
import type { RoProduct } from "@/components/ro-form";
import { fmtDate } from "@/lib/docs/format";

type Row = Record<string, string>;
const inp = "w-full rounded-md border-2 border-line bg-white px-3 py-2.5 text-lg";
const ro_inp = `${inp} bg-background text-muted`;
const lab = "mb-1 block text-sm font-semibold uppercase tracking-wide text-muted";
const ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"];

function previewNo(ro: PoRo | undefined, today: string) {
  if (!ro) return "PROD-…";
  const m = /^RO-(.*-\d{3})-[IVX]+-\d{2}$/.exec(ro.no);
  if (!m) return "Otomatis saat disimpan";
  const d = new Date(`${today}T00:00:00Z`);
  return `PROD-${m[1]}-${ROMAN[d.getUTCMonth()]}-${String(d.getUTCFullYear()).slice(2)}${ro.poCount > 0 ? `-R${ro.poCount + 1}` : ""}`;
}

export function PoForm({ id, initial, ros, products, today, number, cancelHref }: {
  id: string; initial: { header: Row; items: Row[] }; ros: PoRo[]; products: RoProduct[]; today: string; number: string; cancelHref: string;
}) {
  const [state, action, pending] = useActionState<DocFormState, FormData>(saveDoc.bind(null, "prod", id), {});
  const restored = useMemo(() => {
    if (!state.payload) return null;
    try { const p = JSON.parse(state.payload); return { header: (p.header ?? {}) as Row, items: (p.children?.items ?? []) as Row[] }; } catch { return null; }
  }, [state.payload]);
  const nameOf = (pid: string) => products.find((p) => p.id === pid)?.name ?? "";
  const withText = (rows: Row[]) => rows.map((r) => ({ ...r, _text: r._text ?? nameOf(r.product_id) }));
  const [h, setH] = useState<Row>(restored?.header ?? initial.header);
  const [items, setItems] = useState<Row[]>(withText(restored?.items ?? initial.items));
  const ro = ros.find((r) => r.id === h.ro_id);
  const locked = Boolean(id);

  const pickRo = (rid: string) => {
    const r = ros.find((x) => x.id === rid);
    setH((x) => ({
      ...x, ro_id: rid,
      delivery_address: r?.address ?? "",
      send_note: r ? `${fmtDate(r.sendDate)} ${r.sendTime}`.trim() : "",
      needed_date: r?.sendDate ?? "",
    }));
    setItems(r ? withText(r.items.map((i) => ({ product_id: i.product_id, ro_product_id: i.product_id, qty: i.qty, cut_type: i.cut, packaging: i.pack, notes: "" }))) : []);
  };
  const set = (k: string, v: string) => setH((x) => ({ ...x, [k]: v }));
  const setItem = (i: number, patch: Row) => setItems((r) => r.map((x, j) => (j === i ? { ...x, ...patch } : x)));
  const typeProduct = (i: number, text: string) => {
    const t = text.trim().toLowerCase();
    const hit = products.find((p) => p.name.toLowerCase() === t || `${p.code} - ${p.name}`.toLowerCase() === t);
    setItem(i, { _text: text, product_id: hit?.id ?? "" });
  };
  const payload = JSON.stringify({ header: h, children: { items: items.map(({ _text, ...r }) => { void _text; return r; }) } });

  return (
    <form action={action} noValidate className="max-w-6xl">
      <input type="hidden" name="payload" value={payload} />
      <div className="space-y-8 rounded-2xl border border-line bg-white p-6 shadow-sm">
        <section>
          <h2 className="mb-4 text-sm font-bold uppercase tracking-widest text-muted">Data Production Order</h2>
          <div className="grid gap-4 md:grid-cols-2">
            <div><label className={lab}>Nomor PO</label><input className={ro_inp} readOnly value={locked ? number : previewNo(ro, today)} /></div>
            <div><label className={lab}>Publish date</label><input className={ro_inp} readOnly value={fmtDate(h.order_date || today)} /></div>
            <div className="md:col-span-2">
              <label className={lab} htmlFor="po-ro">Request Order (RO) *</label>
              <select id="po-ro" className={inp} disabled={locked} value={h.ro_id ?? ""} onChange={(e) => pickRo(e.target.value)}>
                <option value="">— pilih RO —</option>
                {ros.map((r) => <option key={r.id} value={r.id} disabled={Boolean(r.activePo) && r.id !== h.ro_id}>{r.no} — {r.customer}{r.activePo && r.id !== h.ro_id ? ` (sudah ada ${r.activePo})` : ""}</option>)}
              </select>
              <p className="mt-1 text-sm text-muted">RO yang sudah punya PO aktif dikunci. RO yang PO-nya ditolak Owner bisa dipilih lagi (nomor PO pengganti diberi akhiran -R2).</p>
            </div>
          </div>
        </section>

        {ro ? (
          <>
            <section>
              <h2 className="mb-4 text-sm font-bold uppercase tracking-widest text-muted">Dari RO (otomatis)</h2>
              <div className="grid gap-4 md:grid-cols-3">
                <div><label className={lab}>Customer</label><input className={ro_inp} readOnly value={ro.customer} /></div>
                <div><label className={lab}>No. telepon</label><input className={ro_inp} readOnly value={ro.phone} /></div>
                <div><label className={lab}>Order date</label><input className={ro_inp} readOnly value={fmtDate(ro.orderDate)} /></div>
                <div><label className={lab}>Delivery date and time</label><input className={ro_inp} readOnly value={`${fmtDate(ro.sendDate)}${ro.sendTime ? `, ${ro.sendTime}` : ""}`} /></div>
                <div><label className={lab}>Metode pengiriman</label><input className={ro_inp} readOnly value={ro.ship} /></div>
              </div>
            </section>

            <section>
              <h2 className="mb-4 text-sm font-bold uppercase tracking-widest text-muted">Item produksi (boleh diganti)</h2>
              <datalist id="po-products">{products.map((p) => <option key={p.id} value={p.name}>{p.code}</option>)}</datalist>
              <div className="overflow-x-auto">
                <table className="w-full min-w-[900px] text-left">
                  <thead><tr className="text-sm uppercase tracking-wide text-muted"><th className="w-8 pb-2">No</th><th className="pb-2">Nama produk</th><th className="w-28 pb-2">Qty</th><th className="w-20 pb-2">Satuan</th><th className="pb-2">Jenis potongan</th><th className="pb-2">Jenis pengemasan</th><th className="w-10" /></tr></thead>
                  <tbody>
                    {items.map((r, i) => {
                      const unit = products.find((p) => p.id === r.product_id)?.unit ?? "";
                      const changed = r.ro_product_id && r.product_id && r.ro_product_id !== r.product_id;
                      return (
                        <tr key={i} className="align-top">
                          <td className="py-1 pr-2 pt-4 text-muted">{i + 1}</td>
                          <td className="py-1 pr-2">
                            <input list="po-products" aria-label={`Nama produk ${i + 1}`} className={inp} value={r._text ?? ""} onChange={(e) => typeProduct(i, e.target.value)} />
                            {changed && <p className="mt-1 text-sm text-warn">RO: {nameOf(r.ro_product_id)}</p>}
                            {r._text && !r.product_id && <p className="mt-1 text-sm text-danger">Pilih produk dari daftar yang ada.</p>}
                          </td>
                          <td className="py-1 pr-2"><input aria-label={`Qty ${i + 1}`} className={inp} inputMode="decimal" value={r.qty ?? ""} onChange={(e) => setItem(i, { qty: e.target.value })} /></td>
                          <td className="py-1 pr-2 pt-4 text-lg">{unit}</td>
                          <td className="py-1 pr-2"><input aria-label={`Jenis potongan ${i + 1}`} className={inp} value={r.cut_type ?? ""} onChange={(e) => setItem(i, { cut_type: e.target.value })} /></td>
                          <td className="py-1 pr-2">
                            <select aria-label={`Pengemasan ${i + 1}`} className={inp} value={r.packaging ?? ""} onChange={(e) => setItem(i, { packaging: e.target.value })}>
                              <option value="">Pilih...</option>{RO_PACK.map((o) => <option key={o}>{o}</option>)}
                            </select>
                          </td>
                          <td className="py-1 pt-3"><button type="button" aria-label={`Hapus item ${i + 1}`} disabled={items.length === 1} onClick={() => setItems((x) => x.filter((_, j) => j !== i))} className="rounded-md px-3 py-1.5 text-xl text-danger hover:bg-danger-bg disabled:opacity-30">×</button></td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
              <button type="button" onClick={() => setItems((x) => [...x, { product_id: "", _text: "", qty: "", cut_type: "", packaging: "", notes: "", ro_product_id: "" }])} className="mt-3 rounded-md border-2 border-brand px-5 py-2.5 text-lg font-semibold text-brand hover:bg-background">+ Tambah item</button>
            </section>

            <section>
              <h2 className="mb-4 text-sm font-bold uppercase tracking-widest text-muted">Diisi manual</h2>
              <div className="grid gap-4 md:grid-cols-2">
                <div className="md:col-span-2"><label className={lab} htmlFor="po-send">Jadwal pengiriman (dengan catatan)</label><input id="po-send" className={inp} placeholder="mis. 09 Oktober 2026 09:00 WIB (Sebelum 16:00 sudah sampai)" value={h.send_note ?? ""} onChange={(e) => set("send_note", e.target.value)} /></div>
                <div className="md:col-span-2"><label className={lab} htmlFor="po-addr">Alamat pengiriman</label><textarea id="po-addr" rows={2} className={inp} value={h.delivery_address ?? ""} onChange={(e) => set("delivery_address", e.target.value)} /></div>
                <div><label className={lab} htmlFor="po-pic">PIC pengiriman</label><input id="po-pic" className={inp} value={h.pic ?? ""} onChange={(e) => set("pic", e.target.value)} /></div>
                <div><label className={lab} htmlFor="po-cows">Kode sapi yang digunakan (boleh kosong)</label><input id="po-cows" className={inp} placeholder="mis. AMF014, NUR002" value={h.cow_codes ?? ""} onChange={(e) => set("cow_codes", e.target.value)} /></div>
                <div className="md:col-span-2"><label className={lab} htmlFor="po-note">Note</label><input id="po-note" className={inp} placeholder="mis. alasan penggantian CL 90 → CL 70" value={h.notes ?? ""} onChange={(e) => set("notes", e.target.value)} /></div>
              </div>
            </section>
          </>
        ) : (
          <p className="rounded-md bg-background px-4 py-6 text-center text-muted">Pilih RO terlebih dahulu.</p>
        )}

        {state.error && <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-lg text-danger">{state.error}</p>}
        <div className="flex gap-3">
          <button type="submit" disabled={pending || !ro} className="rounded-md bg-brand px-8 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Menyimpan..." : "Simpan Production Order"}</button>
          <Link href={cancelHref} className="rounded-md border-2 border-line px-8 py-3 text-lg font-semibold hover:bg-background">Batal</Link>
        </div>
      </div>
    </form>
  );
}
