import test from "node:test";
import assert from "node:assert/strict";
import { appBaseUrl, buildEmail, docPath } from "./template.ts";

test("docPath memetakan jenis dokumen ke alamat halaman", () => {
  assert.equal(docPath("RO", "abc"), "/d/ro/abc");
  assert.equal(docPath("PROD", "abc"), "/d/prod/abc");
  assert.equal(docPath("DO", "abc"), "/d/do/abc");
  assert.equal(docPath("PR", "abc"), "/purchase-request/abc");
  assert.equal(docPath("XX", "abc"), "/");
  assert.equal(docPath(null, null), "/");
});

test("appBaseUrl memakai APP_URL tanpa garis miring akhir, lalu cadangan", () => {
  assert.equal(appBaseUrl({ APP_URL: "https://hmihub.com/" }), "https://hmihub.com");
  assert.equal(appBaseUrl({ VERCEL_PROJECT_PRODUCTION_URL: "x.vercel.app" }), "https://x.vercel.app");
  assert.equal(appBaseUrl({}), "https://hmihub.vercel.app");
});

test("buildEmail menyusun subjek, teks, dan HTML yang aman", () => {
  const e = buildEmail("RO baru dikonfirmasi: RO-001", "RO baru dikonfirmasi (RO-001).\nCustomer: <b>Hotel & Co</b>.\nYang perlu dilakukan: Buat Production Order.", "https://x/d/ro/1");
  assert.equal(e.subject, "[HMI Hub] RO baru dikonfirmasi: RO-001");
  assert.ok(e.text.includes("Buka dokumen: https://x/d/ro/1"));
  assert.ok(e.html.includes("Customer: &lt;b&gt;Hotel &amp; Co&lt;/b&gt;."));
  assert.ok(!e.html.includes("<b>Hotel"));
  assert.ok(e.html.includes('href="https://x/d/ro/1"'));
});
