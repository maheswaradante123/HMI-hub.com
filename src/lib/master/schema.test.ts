import { test } from "node:test";
import assert from "node:assert/strict";
import { RESOURCES } from "./config.ts";
import { buildSchema } from "./schema.ts";

const UNIT = "11111111-1111-4111-8111-111111111111";

test("produk: data benar lolos, kode diubah ke huruf besar", () => {
  const r = buildSchema(RESOURCES.produk, "create").safeParse({
    code: "mf-topside", name: " Topside ", product_type: "MANUFACTURE",
    category_id: "", unit_id: UNIT, min_stock: "12,5", notes: "",
  });
  assert.ok(r.success, JSON.stringify(r.error?.issues));
  assert.equal(r.data.code, "MF-TOPSIDE");
  assert.equal(r.data.name, "Topside");
  assert.equal(r.data.category_id, null);
  assert.equal(r.data.min_stock, 12.5);
  assert.equal(r.data.notes, null);
});

test("produk: jenis tidak dikenal, satuan kosong, stok negatif ditolak", () => {
  const s = buildSchema(RESOURCES.produk, "create");
  const base = { code: "A1", name: "A", product_type: "MANUFACTURE", category_id: "", unit_id: UNIT, min_stock: "0", notes: "" };
  assert.ok(s.safeParse(base).success);
  assert.ok(!s.safeParse({ ...base, product_type: "LAIN" }).success);
  assert.ok(!s.safeParse({ ...base, unit_id: "" }).success);
  assert.ok(!s.safeParse({ ...base, unit_id: "bukan-uuid" }).success);
  assert.ok(!s.safeParse({ ...base, min_stock: "-1" }).success);
  assert.ok(!s.safeParse({ ...base, min_stock: "abc" }).success);
});

test("kode: spasi dan simbol aneh ditolak, pesan berbahasa Indonesia", () => {
  const s = buildSchema(RESOURCES.satuan, "create");
  assert.ok(s.safeParse({ code: "KG", name: "Kilogram" }).success);
  const bad = s.safeParse({ code: "K G", name: "Kilogram" });
  assert.ok(!bad.success);
  assert.match(bad.error.issues[0].message, /tanpa spasi/);
  const empty = s.safeParse({ code: "", name: "" });
  assert.ok(!empty.success);
  assert.match(empty.error.issues[0].message, /wajib diisi/);
});

test("customer: termin harus bilangan bulat tidak negatif, kosong dianggap 0", () => {
  const s = buildSchema(RESOURCES.customer, "create");
  const base = { code: "H1", name: "H", type: "HOREKA", address: "", contact_name: "", phone: "", payment_term_days: "14" };
  assert.equal(s.parse(base).payment_term_days, 14);
  assert.equal(s.parse({ ...base, payment_term_days: "" }).payment_term_days, 0);
  assert.ok(!s.safeParse({ ...base, payment_term_days: "1.5" }).success);
  assert.ok(!s.safeParse({ ...base, payment_term_days: "-3" }).success);
});

test("field tidak dikenal dibuang (tidak bisa menyelipkan kolom lain)", () => {
  const r = buildSchema(RESOURCES.satuan, "create").parse({ code: "KG", name: "Kilogram", is_active: false, created_by: "x" });
  assert.deepEqual(Object.keys(r).sort(), ["code", "name"]);
});
