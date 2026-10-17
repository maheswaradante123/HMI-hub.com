import test from "node:test";
import assert from "node:assert/strict";
import { parseQty, parseDoc, lineTotal } from "./parse.ts";
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

const ro = CONFIGS.ro;
const U1 = "11111111-1111-4111-8111-111111111111";
const U2 = "22222222-2222-4222-8222-222222222222";

test("RO: harga kosong dianggap 0 (otomatis), baris kosong diabaikan", () => {
  const r = parseDoc(ro, {
    header: { customer_id: U1, order_date: "2026-10-08", delivery_date: "", notes: "" },
    children: { items: [{ product_id: U2, qty: "12,5", unit_price: "" }, { product_id: "", qty: "", unit_price: "" }] },
  });
  assert.ok(r.ok);
  if (r.ok) {
    assert.deepEqual(r.children.items, [{ product_id: U2, qty: 12.5, unit_price: 0, notes: null }]);
    assert.equal(r.header.delivery_date, null);
  }
});

test("RO: customer wajib, tanggal harus nyata, produk dobel ditolak", () => {
  assert.equal(parseDoc(ro, { header: { customer_id: "", order_date: "2026-10-08" }, children: { items: [{ product_id: U2, qty: "1" }] } }).ok, false);
  assert.equal(parseDoc(ro, { header: { customer_id: U1, order_date: "2026-02-31" }, children: { items: [{ product_id: U2, qty: "1" }] } }).ok, false);
  const dup = parseDoc(ro, { header: { customer_id: U1, order_date: "2026-10-08" }, children: { items: [{ product_id: U2, qty: "1" }, { product_id: U2, qty: "2" }] } });
  assert.equal(dup.ok, false);
  const none = parseDoc(ro, { header: { customer_id: U1, order_date: "2026-10-08" }, children: { items: [] } });
  assert.equal(none.ok, false);
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
