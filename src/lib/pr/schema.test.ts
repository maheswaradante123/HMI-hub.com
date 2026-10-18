import { test } from "node:test";
import assert from "node:assert/strict";
import { parsePrRows } from "./schema.ts";
import { weekOfMonth, weekLabel } from "./lines.ts";

const row = (o: Record<string, string> = {}) => ({ ac: "OPR", code: "BP", item_name: "Rumput Prio", price: "750", qty: "3080", unit: "kg", pay_method: "tf", ...o });
const ok = (rows: Record<string, string>[]) => parsePrRows(rows);

test("data benar lolos; harga dan qty format Indonesia dibaca benar", () => {
  const r = ok([row({ price: "1.250.000", qty: "2,5" })]);
  assert.ok(r.ok);
  assert.equal(r.items[0].price, 1250000);
  assert.equal(r.items[0].qty, 2.5);
});

test("qty: satu titik dianggap desimal, banyak titik pemisah ribuan", () => {
  const q = (v: string) => { const r = ok([row({ qty: v })]); assert.ok(r.ok); return r.items[0].qty; };
  assert.equal(q("2.5"), 2.5);
  assert.equal(q("1.250,5"), 1250.5);
  assert.equal(q("1.250.000"), 1250000);
});

test("A/C, kode, dan pembelian punya nilai awal", () => {
  const r = ok([row({ ac: "", code: "", pay_method: "" })]);
  assert.ok(r.ok);
  assert.deepEqual([r.items[0].ac, r.items[0].code, r.items[0].pay_method], ["OPR", "BP", "tf"]);
});

test("harga kosong dianggap 0; baris kosong diabaikan; tanpa baris ditolak", () => {
  const empty = row({ item_name: "", price: "", qty: "" });
  const r = ok([row({ price: "" }), empty]);
  assert.ok(r.ok);
  assert.equal(r.items.length, 1);
  assert.equal(r.items[0].price, 0);
  const none = ok([empty]);
  assert.ok(!none.ok);
  assert.match(none.error, /minimal satu barang/);
});

test("pesan error menyebut nomor baris", () => {
  const r = ok([row(), row({ qty: "0" })]);
  assert.ok(!r.ok);
  assert.match(r.error, /baris 2/);
});

test("nilai tidak valid ditolak", () => {
  assert.ok(!ok([row({ qty: "abc" })]).ok);
  assert.ok(!ok([row({ qty: "-1" })]).ok);
  assert.ok(!ok([row({ qty: "" })]).ok);
  assert.ok(!ok([row({ unit: "" })]).ok);
  assert.ok(!ok([row({ price: "-5" })]).ok);
  assert.ok(!ok([row({ price: "murah" })]).ok);
  assert.ok(!ok([row({ item_name: "   ", qty: "1" })]).ok);
  assert.ok(!ok([row({ ac: "XYZ" })]).ok);
});

test("minggu ke-n dalam bulan sama dengan nomor lembar (April 2026 mulai Rabu)", () => {
  assert.equal(weekOfMonth("2026-04-01"), 1);
  assert.equal(weekOfMonth("2026-04-06"), 2);
  assert.equal(weekOfMonth("2026-04-23"), 4);
  assert.equal(weekLabel("2026-04-23"), "Minggu ke-4 April 2026");
});
