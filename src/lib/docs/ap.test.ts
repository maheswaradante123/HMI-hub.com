import { test } from "node:test";
import assert from "node:assert/strict";
import { apNumberPreview, apTotals, syncApItems, type ApCow, type ApProduct } from "./ap.ts";
import { CONFIGS } from "./config.ts";
import { parseDoc } from "./parse.ts";

// Angka dari contoh ANALISA_PEMBELIAN (21-Apr-2026): 22 item, 8 baris non-karkas, 8 biaya.
const items = [[22.115, 118000, 1], [25.83, 123000, 1], [18, 114000, 1], [17.89, 118000, 1], [40.33, 118000, 1], [1.045, 138000, 1], [43.715, 138000, 1], [5.645, 161000, 1], [20.7, 160000, 1], [27.885, 138000, 1], [15.34, 134000, 1],
  [29.245, 100000, 0], [1.325, 114000, 0], [4.295, 126000, 0], [19.175, 31500, 0], [10.385, 67000, 0], [28.375, 37000, 0], [7.245, 12000, 0], [1.46, 69000, 0], [4.375, 72000, 0], [1.86, 25000, 0], [1.58, 15000, 0]]
  .map(([qty, price, meat]) => ({ qty, price, meat: meat === 1 }));
const nonk = [20000, 55000, 57750, 300000, 18000, 15000, 5000, 25000].map((price) => ({ qty: null, price }));
const costs = [115000, 100000, 150000, 240000, 3000000, 0, 0, 750986];

test("angka contoh: Total Penjualan, biaya, Total, daging, persentase dan harga karkas", () => {
  const t = apTotals({ items, nonk, costs, cowPrice: 28000000, manualTotal: null, carcass: 356, lower: 124.165, upper: 114.33 });
  assert.ok(Math.abs(t.all - 37549318) <= 1);
  assert.equal(t.ops, 4355986);
  assert.equal(t.totalCost, 32355986);
  assert.ok(Math.abs(t.profit - 5193331) <= 1);
  assert.equal(Math.round(t.meat * 1000) / 1000, 238.495);
  assert.equal(t.meatPct!.toFixed(2), "66.99");
  assert.equal(Math.round(t.hargaKarkas!), 78652);
  assert.equal(t.lowerRatio!.toFixed(10), "0.5206188809");
  assert.equal(t.upperRatio!.toFixed(10), "0.4793811191");
});

test("Total Biaya manual menggantikan harga sapi + operasional; tanpa karkas tidak ada persen", () => {
  const t = apTotals({ items: [{ qty: 10, price: 100000, meat: true }], nonk: [{ qty: 2, price: 5000 }], costs: [1000], cowPrice: 500000, manualTotal: 600000, carcass: 0 });
  assert.equal(t.totalCost, 600000);
  assert.equal(t.profit, 1000000 + 10000 - 600000);
  assert.equal(t.meatPct, null);
  assert.equal(t.hargaKarkas, null);
});

test("pratinjau nomor: urut-SUPPLIER-JENIS-bulan romawi-tahun", () => {
  assert.equal(apNumberPreview(1, "Ainul", "BX", "2026-04-21"), "001-AINUL-BX-IV-26");
  assert.equal(apNumberPreview(12, "PT. Sapi Jaya", "bx", "2026-12-01"), "012-PTSAPIJAYA-BX-XII-26");
  assert.equal(apNumberPreview(null, "A", "B", "2026-05-02"), "NNN-A-B-V-26");
});

const cows: ApCow[] = [
  { id: "c1", cow_number: "BX-1", doc_number: "CW-1", live: 400, carcass: 200, supplier_id: "s", cow_type_id: "t", items: [{ product_id: "p1", weight: 10.5 }, { product_id: "p2", weight: 3 }] },
  { id: "c2", cow_number: "BX-2", doc_number: "CW-2", live: 300, carcass: 150, supplier_id: "s", cow_type_id: "t", items: [{ product_id: "p1", weight: 4.25 }] },
];
const products: ApProduct[] = [{ id: "p1", code: "A", name: "Topside", meat: true, price: 138000 }, { id: "p2", code: "B", name: "Hati", meat: false, price: null }, { id: "p3", code: "C", name: "Lidah", meat: false, price: null }];

test("jumlah item dijumlah dari sapi terpilih; harga bawaan dari Pricing Toko; harga ketikan dipertahankan", () => {
  const a = syncApItems(["c1", "c2"], cows, products, []);
  assert.deepEqual(a.map((r) => [r.product_id, r.weight, r.price_source]), [["p1", "14,75", "PRICING"], ["p2", "3", "TYPED"]]);
  assert.equal(a[0].unit_price, (138000).toLocaleString("id-ID"));
  const edited = a.map((r) => (r.product_id === "p2" ? { ...r, unit_price: "67.000" } : r));
  const manual = [...edited, { product_id: "p3", weight: "1,5", unit_price: "114.000", price_source: "TYPED", linked: false }];
  const b = syncApItems(["c1"], cows, products, manual);
  assert.deepEqual(b.map((r) => [r.product_id, r.weight, r.unit_price]), [["p1", "10,5", (138000).toLocaleString("id-ID")], ["p2", "3", "67.000"], ["p3", "1,5", "114.000"]]);
  assert.deepEqual(syncApItems([], cows, products, b).map((r) => r.product_id), ["p3"]);
});

test("form AP: data lengkap lolos; supplier, jenis sapi, harga, sapi dan item wajib", () => {
  const cfg = CONFIGS.ap;
  const uuid = (n: number) => `00000000-0000-0000-0000-${String(n).padStart(12, "0")}`;
  const good = {
    header: { analysis_date: "2026-04-21", supplier_id: uuid(1), cow_type_id: uuid(2), top_date: "", supplier_invoice: "", total_purchase: "28.000.000", lower_side: "124,165", upper_side: "", manual_total_cost: "", notes: "" },
    children: {
      cows: [{ cw_id: uuid(3) }],
      items: [{ product_id: uuid(4), weight: "22,115", unit_price: "118.000", price_source: "PRICING" }],
      nonk: [{ name: "Babat", weight: "", unit_price: "20.000" }, { name: "", weight: "", unit_price: "" }],
      costs: [{ cost_type_id: uuid(5), amount: "115.000", note: "" }, { cost_type_id: uuid(6), amount: "", note: "" }],
    },
  };
  const r = parseDoc(cfg, good);
  assert.ok(r.ok);
  if (!r.ok) return;
  assert.equal(r.header.total_purchase, 28000000);
  assert.equal(r.header.lower_side, 124.165);
  assert.equal(r.header.top_date, null);
  assert.deepEqual(r.children.nonk, [{ name: "Babat", weight: null, unit_price: 20000 }]);
  assert.equal(r.children.costs.length, 2);
  assert.equal(r.children.costs[1].amount, 0);
  const bad = (h: Record<string, string>) => parseDoc(cfg, { ...good, header: { ...good.header, ...h } });
  assert.equal(bad({ supplier_id: "" }).ok, false);
  assert.equal(bad({ cow_type_id: "" }).ok, false);
  assert.equal(bad({ total_purchase: "" }).ok, false);
  assert.equal(parseDoc(cfg, { ...good, children: { ...good.children, cows: [] } }).ok, false);
  assert.equal(parseDoc(cfg, { ...good, children: { ...good.children, items: [] } }).ok, false);
});
