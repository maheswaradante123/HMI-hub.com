import test from "node:test";
import assert from "node:assert/strict";
import {
  accessToken, resetTokenCache, driveConfigured, validateUpload, folderPath, safeFileName, qEscape,
  ensureFolder, ensurePath, startUpload, finishUpload, cpjFolderPath, shareFolder, folderLink, isDocType, typedName, listFolder, cpjOverview, DriveError, MAX_BYTES,
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

test("cpjFolderPath: CPJ / tahun / Bulan tahun / nomor / item", () => {
  assert.deepEqual(cpjFolderPath({ number: "CPJ-005-X-26", date: "2026-10-15", item: "Rumput Firdaus" }),
    ["HMI Hub Uploads", "CPJ", "2026", "Oktober 2026", "CPJ-005-X-26", "Rumput Firdaus"]);
  assert.deepEqual(cpjFolderPath({ number: "CPJ-001-I-27", date: "2027-01-02", item: "a/b" })!.slice(3), ["Januari 2027", "CPJ-001-I-27", "a_b"]);
  assert.equal(cpjFolderPath({ number: "", date: "2026-10-15", item: "x" }), null);
  assert.equal(cpjFolderPath({ number: "../x", date: "2026-10-15", item: "x" }), null);
  assert.equal(cpjFolderPath({ number: "CPJ-1", date: "2026-13-01", item: "x" }), null);
  assert.equal(cpjFolderPath({ number: "CPJ-1", date: "", item: "x" }), null);
  assert.equal(cpjFolderPath({ number: "CPJ-1", date: "2026-10-01", item: "  " }), null);
});

test("shareFolder membuka folder untuk siapa pun yang punya tautan", async () => {
  const m = mock(() => json({ id: "p" }));
  await shareFolder("t", "FOLD", m.f);
  assert.match(m.calls[0].url, /files\/FOLD\/permissions$/);
  assert.deepEqual(JSON.parse(String(m.calls[0].init!.body)), { role: "reader", type: "anyone" });
  assert.equal(folderLink("FOLD"), "https://drive.google.com/drive/folders/FOLD");
});

test("jenis berkas menjadi awalan nama dan dicatat di appProperties", async () => {
  assert.equal(isDocType("Invoice"), true);
  assert.equal(isDocType("Foto"), false);
  assert.equal(typedName("Surat Jalan", "scan.pdf"), "Surat Jalan - scan.pdf");
  const m = mock(() => new Response(null, { status: 200, headers: { location: "https://u/1" } }));
  await startUpload("t", { name: "Invoice - a.pdf", mime: "application/pdf", size: 1, folderId: "F", origin: "o", by: "b", docType: "Invoice" }, m.f);
  assert.equal(JSON.parse(String(m.calls[0].init!.body)).appProperties.docType, "Invoice");
});

test("listFolder memetakan berkas dan menolak ID aneh", async () => {
  const m = mock(() => json({ files: [{ id: "A1", name: "PO - x.pdf", webViewLink: "https://d/A1", appProperties: { docType: "PO" } }, { id: "B2", name: "y.pdf" }] }));
  const r = await listFolder("t", "FOLDERID123", m.f);
  assert.deepEqual(r.map((x) => [x.id, x.docType]), [["A1", "PO"], ["B2", ""]]);
  assert.match(dq(m.calls[0].url), /'FOLDERID123' in parents/);
  await assert.rejects(listFolder("t", "x' or '1'='1", m.f), DriveError);
});

test("cpjOverview: kelompokkan berkas per folder item, tanpa membuat folder", async () => {
  const m = mock((c) => {
    const q = dq(c.url);
    if (q.includes("mimeType='application/vnd.google-apps.folder' and trashed=false and name=")) return json({ files: [{ id: "PARENTID0001" }] });
    if (q.includes("mimeType='application/vnd.google-apps.folder'") && q.includes("in parents and trashed=false and mimeType=")) return json({ files: [{ id: "ITEMFOLDER01" }, { id: "ITEMFOLDER02" }] });
    return json({ files: [
      { id: "f1", name: "PO - a.pdf", parents: ["ITEMFOLDER01"], appProperties: { docType: "PO" } },
      { id: "f2", name: "Invoice - b.pdf", parents: ["ITEMFOLDER01"], appProperties: { docType: "Invoice" } },
    ] });
  });
  const r = await cpjOverview("t", { number: "CPJ-005-X-26", date: "2026-10-12" }, m.f);
  assert.deepEqual(Object.keys(r).sort(), ["ITEMFOLDER01", "ITEMFOLDER02"]);
  assert.equal(r["ITEMFOLDER01"].length, 2);
  assert.equal(r["ITEMFOLDER02"].length, 0);
  assert.ok(m.calls.every((c) => (c.init?.method ?? "GET") === "GET"));
  const none = mock(() => json({ files: [] }));
  assert.deepEqual(await cpjOverview("t", { number: "CPJ-005-X-26", date: "2026-10-12" }, none.f), {});
  await assert.rejects(cpjOverview("t", { number: "", date: "x" }, none.f), DriveError);
});
