import test from "node:test";
import assert from "node:assert/strict";
import {
  accessToken, resetTokenCache, driveConfigured, validateUpload, folderPath, safeFileName, qEscape,
  ensureFolder, ensurePath, startUpload, finishUpload, DriveError, MAX_BYTES,
} from "./core.ts";

const ENV = { GOOGLE_CLIENT_ID: "id", GOOGLE_CLIENT_SECRET: "sec", GOOGLE_REFRESH_TOKEN: "rt" };
const dq = (u: string) => decodeURIComponent(u.replace(/\+/g, " "));
const json = (body: unknown, init: ResponseInit = {}) =>
  new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" }, ...init });

type Call = { url: string; init?: RequestInit };
function mock(handler: (c: Call) => Response | Promise<Response>) {
  const calls: Call[] = [];
  const f = (async (url: string | URL | Request, init?: RequestInit) => {
    const c = { url: String(url), init };
    calls.push(c);
    return handler(c);
  }) as typeof fetch;
  return { f, calls };
}

test("driveConfigured butuh ketiga variabel", () => {
  assert.equal(driveConfigured(ENV), true);
  assert.equal(driveConfigured({ ...ENV, GOOGLE_REFRESH_TOKEN: "" }), false);
  assert.equal(driveConfigured({}), false);
});

test("validateUpload: menerima PDF, menolak yang tidak didukung / kosong / terlalu besar", () => {
  assert.deepEqual(validateUpload({ name: "a.pdf", mime: "application/pdf", size: 10 }), { ok: true, name: "a.pdf", mime: "application/pdf", size: 10 });
  assert.equal(validateUpload({ name: "a.exe", mime: "application/x-msdownload", size: 10 }).ok, false);
  assert.equal(validateUpload({ name: "a.pdf", mime: "application/pdf", size: 0 }).ok, false);
  assert.equal(validateUpload({ name: "a.pdf", mime: "application/pdf", size: MAX_BYTES + 1 }).ok, false);
  assert.equal(validateUpload({ name: 5, mime: "application/pdf", size: 5 }).ok, false);
  assert.equal(validateUpload({ name: "a.JPG", mime: "IMAGE/JPEG", size: 5 }).ok, true);
});

test("safeFileName membuang pemisah path dan merapikan spasi", () => {
  assert.equal(safeFileName("../a/b\\c  d.pdf"), ".._a_b_c d.pdf");
  assert.equal(safeFileName("   "), "file");
  assert.equal(safeFileName("x".repeat(300)).length, 150);
});

test("folderPath memakai bulan WIB", () => {
  assert.deepEqual(folderPath("CPJ", new Date("2026-10-31T18:00:00Z")), ["HMI Hub Uploads", "CPJ", "2026-11"]);
  assert.deepEqual(folderPath("DO", new Date("2026-10-31T16:00:00Z")), ["HMI Hub Uploads", "DO", "2026-10"]);
});

test("qEscape meloloskan kutip dan backslash", () => {
  assert.equal(qEscape("a'b\\c"), "a\\'b\\\\c");
});

test("accessToken: menukar refresh token, menyimpan di cache, dan melapor invalid_grant", async () => {
  resetTokenCache();
  const m = mock(() => json({ access_token: "T1", expires_in: 3600 }));
  assert.equal(await accessToken(ENV, m.f, 1_000), "T1");
  assert.equal(await accessToken(ENV, m.f, 2_000), "T1");
  assert.equal(m.calls.length, 1);
  assert.match(String(m.calls[0].init?.body), /grant_type=refresh_token/);
  // kedaluwarsa -> tukar lagi
  const m2 = mock(() => json({ access_token: "T2", expires_in: 3600 }));
  assert.equal(await accessToken(ENV, m2.f, 1_000 + 3600_000), "T2");

  resetTokenCache();
  const bad = mock(() => json({ error: "invalid_grant" }, { status: 400 }));
  await assert.rejects(accessToken(ENV, bad.f), (e: unknown) => e instanceof DriveError && /GOOGLE-DRIVE\.md/.test(e.message));
  resetTokenCache();
  await assert.rejects(accessToken({}, bad.f), (e: unknown) => e instanceof DriveError && e.status === 503);
});

test("ensureFolder memakai folder yang ada, atau membuatnya", async () => {
  const found = mock(() => json({ files: [{ id: "F1" }] }));
  assert.equal(await ensureFolder("t", "A'B", "P", found.f), "F1");
  assert.equal(found.calls.length, 1);
  assert.match(dq(found.calls[0].url), /name='A\\'B'/);
  assert.match(dq(found.calls[0].url), /'P' in parents/);

  const made = mock((c) => (c.init?.method === "POST" ? json({ id: "NEW" }) : json({ files: [] })));
  assert.equal(await ensureFolder("t", "X", null, made.f), "NEW");
  assert.deepEqual(JSON.parse(String(made.calls[1].init?.body)), { name: "X", mimeType: "application/vnd.google-apps.folder" });
  assert.match(dq(made.calls[0].url), /'root' in parents/);
});

test("ensurePath menyusuri tiap tingkat dan mengembalikan id terdalam", async () => {
  let n = 0;
  const m = mock(() => json({ files: [{ id: `F${++n}` }] }));
  assert.equal(await ensurePath("t", ["a", "b", "c"], m.f), "F3");
  assert.match(dq(m.calls[2].url), /'F2' in parents/);
});

test("startUpload mengirim Origin + appProperties dan mengembalikan Location", async () => {
  const m = mock(() => new Response(null, { status: 200, headers: { location: "https://upload.example/s1" } }));
  const url = await startUpload("tok", { name: "a.pdf", mime: "application/pdf", size: 9, folderId: "F", origin: "https://hub.example", by: "budi" }, m.f);
  assert.equal(url, "https://upload.example/s1");
  const h = m.calls[0].init!.headers as Record<string, string>;
  assert.equal(h.Origin, "https://hub.example");
  assert.equal(h["X-Upload-Content-Length"], "9");
  const body = JSON.parse(String(m.calls[0].init!.body));
  assert.deepEqual(body.parents, ["F"]);
  assert.equal(body.appProperties.hmiHub, "1");

  const none = mock(() => new Response(null, { status: 403 }));
  await assert.rejects(startUpload("tok", { name: "a", mime: "application/pdf", size: 1, folderId: "F", origin: "o", by: "b" }, none.f), DriveError);
});

test("finishUpload: tolak file yang bukan hasil HMI Hub, buka akses link untuk yang sah", async () => {
  const foreign = mock(() => json({ id: "ABCDEFGHIJK", name: "x", appProperties: {} }));
  await assert.rejects(finishUpload("t", "ABCDEFGHIJK", foreign.f), (e: unknown) => e instanceof DriveError && e.status === 403);
  assert.equal(foreign.calls.length, 1);

  const ok = mock((c) => (c.url.endsWith("/permissions") ? json({ id: "p" }) : json({ id: "ABCDEFGHIJK", name: "scan.pdf", webViewLink: "https://drive.google.com/file/d/ABCDEFGHIJK/view", appProperties: { hmiHub: "1" } })));
  const r = await finishUpload("t", "ABCDEFGHIJK", ok.f);
  assert.deepEqual(r, { id: "ABCDEFGHIJK", name: "scan.pdf", link: "https://drive.google.com/file/d/ABCDEFGHIJK/view" });
  assert.deepEqual(JSON.parse(String(ok.calls[1].init!.body)), { role: "reader", type: "anyone" });

  await assert.rejects(finishUpload("t", "../x", ok.f), (e: unknown) => e instanceof DriveError && e.status === 400);
});
