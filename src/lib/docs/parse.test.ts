import test from "node:test";
import assert from "node:assert/strict";
import { parseQty, parseGram, parseDoc, lineTotal } from "./parse.ts";
import { CONFIGS } from "./config.ts";

test("parseQty menerima desimal titik/koma dan menolak format ribuan", () => {
  assert.equal(parseQty("12,5"), 12.5);
  assert.equal(parseQty("22.115"), 22.115);
  assert.equal(parseQty(""), null);
  assert.equal(parseQty("1.234.567"), "invalid");
  assert.equal(parseQty("-3"), "invalid");
  assert.equal(parseQty("1,2345"), "invalid");
  assert.equal(parseQty("abc"), "invalid");
});

test("parseGram: bilangan bulat gram, titik = pemisah ribuan, koma ditolak", () => {
  assert.equal(parseGram("14620"), 14620);
  assert.equal(parseGram("14.620"), 14620);
  assert.equal(parseGram(" 1.234.567 "), 1234567);
  assert.equal(parseGram(""), null);
  assert.equal(parseGram("12,5"), "invalid");
  assert.equal(parseGram("-5"), "invalid");
  assert.equal(parseGram("abc"), "invalid");
});

const ro = CONFIGS.ro;
const U1 = "11111111-1111-4111-8111-111111111111";
const U2 = "22222222-2222-4222-8222-222222222222";

test("RO: harga kosong dianggap 0 (otomatis), baris kosong diabaikan", () => {
  const r = parseDoc(ro, {
    header: { customer_id: U1, order_date: "2026-10-08", delivery_date: "", notes: "", customer_po_url: "https://drive.google.com/file/d/ABCDEFGHIJK/view" },
    children: { items: [{ product_id: U2, qty: "12,5", unit_price: "" }, { product_id: "", qty: "", unit_price: "" }] },
  });
  assert.ok(r.ok);
  if (r.ok) {
    assert.deepEqual(r.children.items, [{ product_id: U2, qty: 12.5, unit_price: 0, cut_type: null, packaging: null, notes: null }]);
    assert.equal(r.header.delivery_date, null);
  }
});

test("RO: customer wajib, tanggal harus nyata, produk dobel ditolak", () => {
  assert.equal(parseDoc(ro, { header: { customer_id: "", order_date: "2026-10-08" }, children: { items: [{ product_id: U2, qty: "1" }] } }).ok, false);
  assert.equal(parseDoc(ro, { header: { customer_id: U1, order_date: "2026-02-31", customer_po_url: "https://drive.google.com/file/d/ABCDEFGHIJK/view" }, children: { items: [{ product_id: U2, qty: "1" }] } }).ok, false);
  const dup = parseDoc(ro, { header: { customer_id: U1, order_date: "2026-10-08", customer_po_url: "https://drive.google.com/file/d/ABCDEFGHIJK/view" }, children: { items: [{ product_id: U2, qty: "1" }, { product_id: U2, qty: "2" }] } });
  assert.equal(dup.ok, false);
  const none = parseDoc(ro, { header: { customer_id: U1, order_date: "2026-10-08", customer_po_url: "https://drive.google.com/file/d/ABCDEFGHIJK/view" }, children: { items: [] } });
  assert.equal(none.ok, false);
});

test("RO: lampiran PO customer wajib; nomor PO boleh kosong", () => {
  const items = { items: [{ product_id: U2, qty: "1" }] };
  assert.equal(parseDoc(ro, { header: { customer_id: U1, order_date: "2026-10-08" }, children: items }).ok, false);
  assert.equal(parseDoc(ro, { header: { customer_id: U1, order_date: "2026-10-08", customer_po_url: "  " }, children: items }).ok, false);
  const ok = parseDoc(ro, { header: { customer_id: U1, order_date: "2026-10-08", customer_po_no: "", customer_po_url: "https://drive.google.com/file/d/ABCDEFGHIJK/view" }, children: items });
  assert.equal(ok.ok, true);
});

test("Penimbangan: baris harus produk atau non-karkas, tepat salah satu", () => {
  const cw = CONFIGS.cw;
  const base = { cow_type_id: U1, cow_number: "BX-001", warehouse_id: U1, weigh_date: "2026-10-08", live_weight: "460", carcass_weight: "250" };
  const both = parseDoc(cw, { header: base, children: { items: [{ product_id: U2, non_carcass_type_id: U1, weight: "5" }] } });
  assert.equal(both.ok, false);
  const one = parseDoc(cw, { header: base, children: { items: [{ product_id: U2, non_carcass_type_id: "", weight: "5" }] } });
  assert.equal(one.ok, true);
});

test("lineTotal", () => {
  assert.equal(lineTotal("12,5", "135.000"), 1687500);
  assert.equal(lineTotal("x", "100"), 0);
});

test("setiap konfigurasi punya slug unik dan modul", () => {
  const slugs = Object.values(CONFIGS).map((c) => c.slug);
  assert.equal(new Set(slugs).size, slugs.length);
  for (const c of Object.values(CONFIGS)) assert.ok(c.module && c.table && c.header.length > 0, c.type);
});

test("docUnit: satuan Gram di dokumen tampil Kg, lainnya tetap", async () => {
  const { docUnit } = await import("./format.ts");
  assert.equal(docUnit("Gram"), "Kg");
  assert.equal(docUnit("Kilogram"), "Kilogram");
  assert.equal(docUnit(null), "");
});

test("Kwitansi: customer dan minimal satu invoice wajib", () => {
  const kw = CONFIGS.kw;
  assert.equal(parseDoc(kw, { header: { customer_id: U1, receipt_date: "2026-11-12" }, children: { items: [] } }).ok, false);
  assert.equal(parseDoc(kw, { header: { customer_id: "", receipt_date: "2026-11-12" }, children: { items: [{ invoice_id: U2 }] } }).ok, false);
  assert.equal(parseDoc(kw, { header: { customer_id: U1, receipt_date: "2026-11-12" }, children: { items: [{ invoice_id: U2 }] } }).ok, true);
});

test("kwitansi: invoice yang sama tidak boleh dipilih dua kali", () => {
  const kw = CONFIGS.kw;
  const inv = "11111111-1111-4111-8111-111111111111";
  const r = parseDoc(kw, { header: { customer_id: U1, receipt_date: "2026-11-14" }, children: { items: [{ invoice_id: inv }, { invoice_id: inv }] } });
  assert.equal(r.ok, false);
  assert.match(r.ok ? "" : r.error, /lebih dari sekali/);
});

test("rincian Petty Cash: dinormalkan, baris kosong dibuang, nomor stabil, jumlah wajib benar", () => {
  const jcp = CONFIGS.jcp;
  const line = (details: string) => ({ header: { journal_date: "2026-10-31" }, children: { lines: [{ description: "Petty Cash", price: "500.000", qty: "1", flag: "NONE", details }] } });
  const ok = parseDoc(jcp, line(JSON.stringify([
    { no: 2, date: "2026-10-31", text: "Bensin", amount: "50.000", proof: "" },
    { no: "", date: "", text: "", amount: "", proof: "" },
    { no: 0, date: "2026-11-01", text: "Parkir", amount: "71.000", proof: "https://drive.google.com/drive/folders/x" },
  ])));
  assert.equal(ok.ok, true);
  if (ok.ok) assert.deepEqual(JSON.parse(String(ok.children.lines[0].details)), [
    { no: 2, date: "2026-10-31", text: "Bensin", amount: 50000, proof: "" },
    { no: 3, date: "2026-11-01", text: "Parkir", amount: 71000, proof: "https://drive.google.com/drive/folders/x" },
  ]);
  assert.equal(parseDoc(jcp, line(JSON.stringify([{ text: "Bensin", amount: "abc" }]))).ok, false);
  assert.equal(parseDoc(jcp, line(JSON.stringify([{ text: "", amount: "5.000" }]))).ok, false);
  assert.equal(parseDoc(jcp, line(JSON.stringify([{ text: "A", amount: "0" }]))).ok, false);
  assert.equal(parseDoc(jcp, line(JSON.stringify([{ text: "A", amount: "5.000", date: "2026-02-31" }]))).ok, false);
  assert.equal(parseDoc(jcp, line("bukan json")).ok, false);
  assert.equal(parseDoc(jcp, line("")).ok, true);
});
