import test from "node:test";
import assert from "node:assert/strict";
import { compareDocNo, docNoKey, sortDocNoDesc } from "./doc-no.ts";

test("nomor dikenali: awalan, urut, bulan romawi, tahun, akhiran", () => {
  assert.deepEqual(docNoKey("INV-006-X-26-2"), { prefix: "INV", seq: 6, month: 10, year: 2026, extra: 2 });
  assert.deepEqual(docNoKey("RO-HBR-001-II-26"), { prefix: "RO-HBR", seq: 1, month: 2, year: 2026, extra: 0 });
  assert.deepEqual(docNoKey("PROD-HBR-001-II-26-R2"), { prefix: "PROD-HBR", seq: 1, month: 2, year: 2026, extra: 2 });
  assert.equal(docNoKey("ABC"), null);
});

test("urut tahun, lalu bulan, lalu nomor (terbaru di atas)", () => {
  const nos = ["INV-007-VIII-26", "INV-006-XI-26", "INV-001-XI-26", "INV-006-X-26-2", "INV-006-X-26", "INV-012-XII-25", "INV-002-IX-26", "INV-010-IX-26"];
  assert.deepEqual(sortDocNoDesc(nos, (x) => x), [
    "INV-006-XI-26", "INV-001-XI-26", "INV-006-X-26-2", "INV-006-X-26", "INV-010-IX-26", "INV-002-IX-26", "INV-007-VIII-26", "INV-012-XII-25",
  ]);
});

test("nomor tak berpola ikut di paling lama; naik dan turun konsisten", () => {
  assert.ok(compareDocNo("INV-001-I-26", "XYZ") > 0);
  assert.ok(compareDocNo("INV-001-I-26", "INV-001-II-26") < 0);
  assert.ok(compareDocNo("INV-009-X-26", "INV-010-X-26") < 0);
});
