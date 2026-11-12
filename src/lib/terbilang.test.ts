import test from "node:test";
import assert from "node:assert/strict";
import { terbilang, terbilangRupiah } from "./terbilang.ts";

test("terbilang: contoh kwitansi Habitare", () => {
  assert.equal(terbilangRupiah(14466325), "Empat Belas Juta Empat Ratus Enam Puluh Enam Ribu Tiga Ratus Dua Puluh Lima Rupiah");
  assert.equal(terbilangRupiah(460000), "Empat Ratus Enam Puluh Ribu Rupiah");
});

test("terbilang: bentuk khusus seribu, seratus, sebelas, belasan", () => {
  assert.equal(terbilang(1000), "Seribu");
  assert.equal(terbilang(1100), "Seribu Seratus");
  assert.equal(terbilang(100), "Seratus");
  assert.equal(terbilang(111000), "Seratus Sebelas Ribu");
  assert.equal(terbilang(2000), "Dua Ribu");
  assert.equal(terbilang(11), "Sebelas");
  assert.equal(terbilang(15), "Lima Belas");
  assert.equal(terbilang(21), "Dua Puluh Satu");
  assert.equal(terbilang(1000000), "Satu Juta");
  assert.equal(terbilang(1001000), "Satu Juta Seribu");
  assert.equal(terbilang(2500000000), "Dua Miliar Lima Ratus Juta");
});

test("terbilang: nol, pembulatan, minus", () => {
  assert.equal(terbilang(0), "Nol");
  assert.equal(terbilang(1999.6), "Dua Ribu");
  assert.equal(terbilang(-500), "Minus Lima Ratus");
});
