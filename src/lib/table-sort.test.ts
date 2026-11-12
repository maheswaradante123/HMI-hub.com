import { test } from "node:test";
import assert from "node:assert/strict";
import { cellValue } from "./table-sort.ts";

test("tanggal dengan bulan singkat terbaca sebagai tanggal dan berurutan", () => {
  const rows = ["5 Mei 2026", "1 Apr 2026", "1 Des 2025", "1 Okt 2025", "12 Jun 2026", "3 Agu 2026", "9 Sep 2026", "2 Jan 2026"];
  const sorted = [...rows].sort((a, b) => (cellValue(a).n as number) - (cellValue(b).n as number));
  assert.deepEqual(sorted, ["1 Okt 2025", "1 Des 2025", "2 Jan 2026", "1 Apr 2026", "5 Mei 2026", "12 Jun 2026", "3 Agu 2026", "9 Sep 2026"]);
  for (const r of rows) assert.equal(typeof cellValue(r).n, "number", r);
});

test("nama bulan lengkap tetap dikenali", () => {
  assert.equal(cellValue("5 Agustus 2026").n, cellValue("5 Agu 2026").n);
  assert.equal(cellValue("1 Desember 2025").n, cellValue("1 Des 2025").n);
});

test("angka rupiah dan teks", () => {
  assert.equal(cellValue("Rp 2.359.665").n, 2359665);
  assert.equal(cellValue("Rp 0").n, 0);
  assert.equal(cellValue("30 hari").n, 30);
  assert.deepEqual(cellValue("Lunas"), { s: "lunas" });
});
