import test from "node:test";
import assert from "node:assert/strict";
import { cleanCwItems, cwCatFromCode, cwTotals } from "./cw.ts";
import { parseQty } from "./parse.ts";

test("kategori master menjadi kategori form", () => {
  assert.equal(cwCatFromCode("TULANG"), "Tulang");
  assert.equal(cwCatFromCode("JEROHAN"), "Jeroan");
  assert.equal(cwCatFromCode("DAGING"), "Daging");
  assert.equal(cwCatFromCode(null), "Daging");
  assert.equal(cwCatFromCode("LAIN"), "Daging");
});

test("total per kategori dan persen daging terhadap karkas", () => {
  const t = cwTotals([{ cat: "Daging", weight: 200 }, { cat: "Daging", weight: 28 }, { cat: "Tulang", weight: 60 }, { cat: "Jeroan", weight: 10 }, { cat: "Non-Karkas", weight: 5 }], 356);
  assert.equal(t.total, 303);
  assert.equal(t.byCat.Daging, 228);
  assert.ok(Math.abs((t.meatPct ?? 0) - 64.04494) < 1e-4);
  assert.equal(t.over, false);
  assert.equal(cwTotals([{ cat: "Daging", weight: 400 }], 356).over, true);
  assert.equal(cwTotals([{ cat: "Daging", weight: 10 }], 0).meatPct, null);
});

test("baris kosong dilewati, baris sebagian ditolak", () => {
  const ok = cleanCwItems([{ name: " Sengkel ", cat: "Tulang", weight: "12,5" }, { name: "", cat: "Daging", weight: "" }], parseQty);
  assert.deepEqual(ok, { ok: true, items: [{ name: "Sengkel", cat: "Tulang", weight: 12.5 }] });
  assert.equal(cleanCwItems([{ name: "A", cat: "Daging", weight: "" }], parseQty).ok, false);
  assert.equal(cleanCwItems([{ name: "", cat: "Daging", weight: "5" }], parseQty).ok, false);
  assert.equal(cleanCwItems([{ name: "A", cat: "Sayur", weight: "5" }], parseQty).ok, false);
  assert.equal(cleanCwItems([{ name: "A", cat: "Daging", weight: "0" }], parseQty).ok, false);
  assert.equal(cleanCwItems([{ name: "A", cat: "Daging", weight: "1x" }], parseQty).ok, false);
  assert.equal(cleanCwItems([], parseQty).ok, false);
});

test("nama kembar (beda huruf besar/kecil) ditolak", () => {
  const r = cleanCwItems([{ name: "Lidah", cat: "Jeroan", weight: "2" }, { name: "lidah", cat: "Jeroan", weight: "3" }], parseQty);
  assert.equal(r.ok, false);
});

import { cwNumberPreview } from "./cw.ts";
test("pratinjau nomor CW", () => {
  assert.equal(cwNumberPreview("012", "amf-014", "2026-04-09"), "CW-012-AMF014-IV-26");
  assert.equal(cwNumberPreview("", "", "2026-12-01"), "CW-NNN-KODE-XII-26");
  assert.equal(cwNumberPreview("001", "A", "bukan tanggal"), "");
});
