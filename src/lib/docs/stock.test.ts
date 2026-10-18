import test from "node:test";
import assert from "node:assert/strict";
import { emptyLast, sortLots, withBalances } from "./stock.ts";

test("saldo sebelum dan sesudah, terbaru di atas", () => {
  const r = withBalances([
    { id: "b", movement_date: "2026-04-02", created_at: "2026-04-02T01:00:00Z", qty: -4 },
    { id: "a", movement_date: "2026-04-01", created_at: "2026-04-01T01:00:00Z", qty: 10 },
    { id: "c", movement_date: "2026-04-02", created_at: "2026-04-02T02:00:00Z", qty: 1.5 },
  ]);
  assert.deepEqual(r.map((x) => [x.id, x.before, x.after]), [["c", 6, 7.5], ["b", 10, 6], ["a", 0, 10]]);
});

test("urutan baris asal sapi", () => {
  const r = sortLots([
    { lot: "HABIS1", first_in: "2026-03-01", qty_in: 5, qty_out: 5, qty_rest: 0 },
    { lot: null, first_in: null, qty_in: 3, qty_out: 0, qty_rest: 3 },
    { lot: "B", first_in: "2026-04-05", qty_in: 5, qty_out: 0, qty_rest: 5 },
    { lot: "A", first_in: "2026-04-01", qty_in: 5, qty_out: 1, qty_rest: 4 },
  ]);
  assert.deepEqual(r.map((x) => x.lot), ["A", "B", "HABIS1", null]);
});

test("item habis di bawah", () => {
  const r = emptyLast([{ name: "Z", qty: 5 }, { name: "A", qty: 0 }, { name: "B", qty: 2 }]);
  assert.deepEqual(r.map((x) => x.name), ["B", "Z", "A"]);
});

test("saldo awal bila riwayat terpotong", () => {
  const r = withBalances([{ id: "a", movement_date: "2026-04-01", created_at: "2026-04-01T01:00:00Z", qty: 5 }], 100);
  assert.deepEqual([r[0].before, r[0].after], [100, 105]);
});
