import { test } from "node:test";
import assert from "node:assert/strict";
import { parsePr } from "./schema.ts";

const U = "11111111-1111-4111-8111-111111111111";
const P = "22222222-2222-4222-8222-222222222222";
const row = (o: Record<string, string> = {}) => ({
  product_id: "", item_name: "Kertas HVS", qty: "5", unit_id: U, estimated_price: "", notes: "", ...o,
});
const ok = (rows: Record<string, string>[], extra = {}) =>
  parsePr({ reason: "Stok habis", priority: "NORMAL", rows, ...extra });

test("data benar lolos; harga format Indonesia dan koma desimal dibaca benar", () => {
  const r = ok([row({ product_id: P, qty: "2,5", estimated_price: "1.250.000" })]);
  assert.ok(r.ok);
  assert.equal(r.data.items[0].qty, 2.5);
  assert.equal(r.data.items[0].estimated_price, 1250000);
  assert.equal(r.data.items[0].product_id, P);
});

test("estimasi harga boleh kosong", () => {
  const r = ok([row()]);
  assert.ok(r.ok);
  assert.equal(r.data.items[0].estimated_price, null);
});

test("baris kosong diabaikan, tanpa baris sama sekali ditolak", () => {
  const empty = row({ item_name: "", qty: "", unit_id: "" });
  assert.ok(ok([row(), empty]).ok);
  const r = ok([empty]);
  assert.ok(!r.ok);
  assert.match(r.error, /minimal satu barang/);
});

test("pesan error menyebut nomor baris", () => {
  const r = ok([row(), row({ qty: "0" })]);
  assert.ok(!r.ok);
  assert.match(r.error, /baris 2/);
  assert.match(r.error, /lebih dari 0/);
});

test("nilai tidak valid ditolak", () => {
  assert.ok(!ok([row({ qty: "abc" })]).ok);
  assert.ok(!ok([row({ qty: "-1" })]).ok);
  assert.ok(!ok([row({ qty: "" })]).ok);
  assert.ok(!ok([row({ unit_id: "" })]).ok);
  assert.ok(!ok([row({ estimated_price: "-5" })]).ok);
  assert.ok(!ok([row({ estimated_price: "murah" })]).ok);
  assert.ok(!ok([row({ item_name: "   ", qty: "1" })]).ok);
  assert.ok(!ok([row({ product_id: "bukan-uuid" })]).ok);
});

test("alasan dan prioritas wajib valid", () => {
  assert.ok(!parsePr({ reason: "  ", priority: "NORMAL", rows: [row()] }).ok);
  assert.ok(!parsePr({ reason: "x", priority: "ASAP", rows: [row()] }).ok);
});
