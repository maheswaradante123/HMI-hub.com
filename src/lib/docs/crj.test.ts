import { test } from "node:test";
import assert from "node:assert/strict";
import { sumBy, weekRange } from "./crj.ts";

test("weekRange: Senin sampai Minggu", () => {
  assert.deepEqual(weekRange("2026-11-03"), { from: "2026-11-02", to: "2026-11-08" }); // Selasa
  assert.deepEqual(weekRange("2026-11-02"), { from: "2026-11-02", to: "2026-11-08" }); // Senin
  assert.deepEqual(weekRange("2026-11-08"), { from: "2026-11-02", to: "2026-11-08" }); // Minggu
  assert.deepEqual(weekRange("2026-03-01"), { from: "2026-02-23", to: "2026-03-01" }); // lintas bulan
});

test("sumBy menjumlah per kunci", () => {
  const r = sumBy([{ k: "a", v: 1 }, { k: "b", v: 5 }, { k: "a", v: 2 }], (x) => x.k, (x) => x.v);
  assert.deepEqual(r, [["a", 3], ["b", 5]]);
});
