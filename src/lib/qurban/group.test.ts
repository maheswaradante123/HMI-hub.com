import { test } from "node:test";
import assert from "node:assert/strict";
import { collapseGroups, groupSizes } from "./group.ts";

const o = (id: string, group_id: string | null, status = "PROFORMA") => ({ id, group_id, status });

test("collapseGroups: pesanan tunggal dan kelompok", () => {
  const r = collapseGroups([o("a", null), o("b", "g1"), o("c", "g1"), o("d", "g1"), o("e", null)]);
  assert.equal(r.length, 3);
  assert.deepEqual(r.map((x) => x.head.id), ["a", "b", "e"]);
  assert.deepEqual(r[1].members.map((x) => x.id), ["b", "c", "d"]);
});

test("collapseGroups: anggota batal disembunyikan, semua batal tetap tampil", () => {
  const r = collapseGroups([o("b", "g1", "CANCELLED"), o("c", "g1"), o("x", "g2", "CANCELLED"), o("y", "g2", "CANCELLED")]);
  assert.deepEqual(r[0].members.map((x) => x.id), ["c"]);
  assert.equal(r[0].head.id, "c");
  assert.deepEqual(r[1].members.map((x) => x.id), ["x", "y"]);
});

test("groupSizes menghitung sapi aktif", () => {
  const m = groupSizes([o("b", "g1"), o("c", "g1", "CANCELLED"), o("d", "g1"), o("e", null)]);
  assert.equal(m.get("g1"), 2);
  assert.equal(m.size, 1);
});
