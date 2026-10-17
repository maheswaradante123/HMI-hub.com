import { test } from "node:test";
import assert from "node:assert/strict";
import { parseMoney, parsePrice, isRealDate } from "./schema.ts";

const SUP = "11111111-1111-4111-8111-111111111111";
const raw = (o: Partial<Record<"sell" | "buy" | "supplier" | "from" | "note", string>> = {}) =>
  ({ sell: "13.000", buy: "10.000", supplier: SUP, from: "2026-11-01", note: "", ...o });
const full = { canSetCost: true, showCost: true };

test("uang: format Indonesia dan angka polos dibaca benar", () => {
  assert.equal(parseMoney("118.000"), 118000);
  assert.equal(parseMoney("118000"), 118000);
  assert.equal(parseMoney("Rp 1.250.000"), 1250000);
  assert.equal(parseMoney("12.500,50"), 12500.5);
  assert.equal(parseMoney("0"), 0);
  assert.equal(parseMoney(""), null);
  assert.equal(parseMoney("  "), null);
});

test("uang: nilai tidak valid ditolak", () => {
  for (const v of ["abc", "-5", "1,2,3", "12a", "1e5", "99999999999999", "1.5", "1.2345", "12..000"]) {
    assert.equal(parseMoney(v), "invalid", v);
  }
});

test("tanggal: hanya tanggal nyata", () => {
  assert.ok(isRealDate("2026-11-01"));
  assert.ok(!isRealDate("2026-02-30"));
  assert.ok(!isRealDate("01-11-2026"));
  assert.ok(!isRealDate(""));
  assert.ok(!isRealDate("2026-13-01"));
});

test("form lengkap lolos", () => {
  const r = parsePrice(raw(), full);
  assert.ok(r.ok);
  assert.deepEqual(r.data, { sell_price: 13000, buy_price: 10000, supplier_id: SUP, effective_from: "2026-11-01", note: null });
});

test("tanpa izin biaya: harga beli dan supplier diabaikan", () => {
  const r = parsePrice(raw(), { canSetCost: false, showCost: true });
  assert.ok(r.ok);
  assert.equal(r.data.buy_price, null);
  assert.equal(r.data.supplier_id, null);
});

test("produk manufacture (tanpa kolom beli): harga jual saja", () => {
  const r = parsePrice(raw({ sell: "140.000" }), { canSetCost: true, showCost: false });
  assert.ok(r.ok);
  assert.equal(r.data.buy_price, null);
  assert.ok(!parsePrice(raw({ sell: "" }), { canSetCost: true, showCost: false }).ok);
});

test("harus ada minimal satu harga, tanggal valid, supplier valid", () => {
  const e1 = parsePrice(raw({ sell: "", buy: "" }), full);
  assert.ok(!e1.ok); assert.match(e1.error, /harga jual atau harga beli/i);
  assert.ok(!parsePrice(raw({ from: "" }), full).ok);
  assert.ok(!parsePrice(raw({ supplier: "bukan-uuid" }), full).ok);
  assert.ok(!parsePrice(raw({ sell: "-1" }), full).ok);
  assert.ok(!parsePrice(raw({ note: "x".repeat(501) }), full).ok);
});

test("hanya harga beli (tanpa harga jual) boleh untuk pemegang izin biaya", () => {
  const r = parsePrice(raw({ sell: "" }), full);
  assert.ok(r.ok);
  assert.equal(r.data.sell_price, null);
});
