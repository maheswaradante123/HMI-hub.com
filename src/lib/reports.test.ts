import test from "node:test";
import assert from "node:assert/strict";
import { csvCell, toCsv, REPORTS } from "./reports.ts";

test("csvCell melindungi dari injeksi rumus dan meloloskan tanda kutip", () => {
  assert.equal(csvCell("=HYPERLINK(\"x\")"), "\"'=HYPERLINK(\"\"x\"\")\"");
  assert.equal(csvCell("+62812"), "'+62812");
  assert.equal(csvCell("Toko, Jaya"), "\"Toko, Jaya\"");
  assert.equal(csvCell(-5000, "num"), "-5000");
  assert.equal(csvCell(null), "");
  assert.equal(csvCell(true, "bool"), "Ya");
});

test("toCsv membaca kolom bersarang", () => {
  const out = toCsv([{ a: 1, c: { name: "Hotel A" } }], [{ h: "A", path: "a", kind: "num" }, { h: "Cust", path: "c.name" }]);
  assert.equal(out, "﻿A,Cust\r\n1,Hotel A\r\n");
});

test("kunci laporan unik", () => {
  assert.equal(new Set(REPORTS.map((r) => r.key)).size, REPORTS.length);
});
