import { test } from "node:test";
import assert from "node:assert/strict";
import { fetchAll } from "./fetch-all.ts";

const source = (n: number) => (from: number, to: number) =>
  Promise.resolve({ data: Array.from({ length: Math.max(0, Math.min(n, to + 1) - from) }, (_, i) => from + i), error: null });

test("fetchAll mengambil semua baris lintas halaman", async () => {
  for (const n of [0, 1, 999, 1000, 1001, 2500, 3000]) {
    const r = await fetchAll<number>(source(n));
    assert.equal(r.data.length, n, `n=${n}`);
    assert.equal(r.error, null);
    assert.deepEqual(r.data.slice(0, 3), [0, 1, 2].slice(0, Math.min(3, n)));
  }
});

test("fetchAll berhenti dan melaporkan galat", async () => {
  let calls = 0;
  const r = await fetchAll<number>((from) => { calls++; return Promise.resolve(from === 0 ? { data: Array(1000).fill(1), error: null } : { data: null, error: new Error("x") }); });
  assert.equal(calls, 2);
  assert.ok(r.error);
});
