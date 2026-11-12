#!/usr/bin/env python3
"""Membuat supabase/data/tautkan_invoice_pl.sql: menautkan invoice arsip ke Packing List (dan RO) berdasarkan
Rekap_Dokumen_Penjualan_Daging.xlsx (sheet 'Rekap Transaksi'), supaya Packing List lama tidak lagi muncul sebagai 'belum ditagih'.
Pemakaian: python3 scripts/gen_tautkan_inv_pl.py <Rekap.xlsx> <keluaran.sql>"""
import json, re, sys, os, datetime as dt, collections
from openpyxl import load_workbook
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..")
XLSX, OUT = sys.argv[1:3]
js = lambda f: json.loads(re.search(r"\$json\$(.*?)\$json\$", open(os.path.join(ROOT, "supabase", "data", f)).read(), re.S).group(1))
invs = js("migrasi_invoice.sql")["invs"]; pls = js("migrasi_pl_do.sql")["pls"]
sys.path.insert(0, HERE)
CAT = []
by_no = collections.defaultdict(list)
for i in invs:
    base = re.sub(r"-\d$", "", i["no"]) if re.search(r"-[IVX]+-\d{2}-\d$", i["no"]) else i["no"]
    by_no[base].append(i)
pl_by_no = collections.defaultdict(list)
for p in pls: pl_by_no[re.sub(r"-B$", "", p["no"])].append(p)

def code_of(name):
    n = (name or "").lower()
    for k, c in [("raya boga", "RBC"), ("habitare", "HBR"), ("alana", "ALN"), ("harper", "HPR"), ("aston", "AST")]:
        if k in n: return c
    return None

ws = load_workbook(XLSX, data_only=True)["Rekap Transaksi"]
pairs = []; seen_pl = {}
for r in ws.iter_rows(min_row=2, values_only=True):
    tgl, buyer, ro, plno, ino = r[1], r[2], r[3], r[5], r[7]
    if plno in (None, "-") or ino in (None, "-"): continue
    cand = by_no.get(ino, [])
    if not cand:   # nomor di rekap lama bisa berbeda dari PDF terbaru: cari menurut pelanggan, tanggal, dan nilai
        c = code_of(buyer); val = r[8]
        cand = [x for x in invs if x["c"] == c and val and abs(x["total"] - val) < 1.5 and abs((dt.date.fromisoformat(x["d"]) - tgl.date()).days) <= 2]
        if len(cand) == 1: CAT.append(f"{ino}: tidak ada di PDF terbaru; dipasangkan dengan {cand[0]['no']} (pelanggan, tanggal, dan nilai sama)")
        else: CAT.append(f"{ino}: tidak ada di data invoice"); continue
    if len(cand) > 1:
        c = code_of(buyer); sel = [x for x in cand if x["c"] == c]
        if len(sel) != 1: CAT.append(f"{ino} ({buyer}): nomor ganda, pelanggan tidak bisa dipastikan; dilewati"); continue
        cand = sel
    i = cand[0]
    pc = pl_by_no.get(plno, [])
    if len(pc) > 1: CAT.append(f"{plno}: nomor PL ganda; {ino} dilewati"); continue
    if pc:
        p = pc[0]
        dd = abs((dt.date.fromisoformat(p["d"]) - dt.date.fromisoformat(i["d"])).days)
        wp = sum(x["q"] for x in p["it"]); wi = sum(x["q"] for x in i["it"])
        if p["c"] != i["c"]:
            if dd <= 1 and abs(wp - wi) <= 0.01 * wp:
                CAT.append(f"{ino} dan {plno}: nama pelanggan beda ({i['c']} vs {p['c']}) tetapi tanggal dan berat sama; ditautkan")
            else:
                CAT.append(f"{ino} dan {plno}: pelanggan berbeda ({i['c']} vs {p['c']}); dilewati"); continue
        if dd > 3: CAT.append(f"{ino} dan {plno}: selisih tanggal {dd} hari; tetap ditautkan menurut rekap")
    if plno in seen_pl: CAT.append(f"{plno} dipakai {seen_pl[plno]} dan {i['no']}; yang kedua dilewati"); continue
    seen_pl[plno] = i["no"]
    pairs.append(dict(inv=i["no"], pl=plno))
# Tahap 2: PL dan invoice yang belum berpasangan, ditautkan bila hanya satu kemungkinan (pelanggan sama, tanggal sama +-1 hari, berat sama).
linked_inv = {x["inv"] for x in pairs}; linked_pl = {x["pl"] for x in pairs}
free_i = [i for i in invs if i["no"] not in linked_inv]; free_p = [p for p in pls if p["no"] not in linked_pl and not p["no"].endswith("-B")]
pl_dup = {k for k, v in pl_by_no.items() if len(v) > 1}
def near(i, p):
    wp = sum(x["q"] for x in p["it"]); wi = sum(x["q"] for x in i["it"])
    return p["c"] == i["c"] and abs((dt.date.fromisoformat(p["d"]) - dt.date.fromisoformat(i["d"])).days) <= 1 and wi > 0 and abs(wp - wi) <= 0.005 * wp
for i in free_i:
    m = [p for p in free_p if near(i, p) and p["no"] not in pl_dup]
    if len(m) == 1 and len([x for x in free_i if near(x, m[0])]) == 1:
        pairs.append(dict(inv=i["no"], pl=m[0]["no"])); CAT.append(f"TAMBAHAN (tidak ada di rekap): {i['no']} dan {m[0]['no']}: pelanggan, tanggal, dan berat sama")
sql = f"""-- ============================================================================
-- Tautkan invoice arsip ke Packing List (dan RO)
-- DIBUAT OTOMATIS oleh scripts/gen_tautkan_inv_pl.py dari Rekap_Dokumen_Penjualan_Daging.xlsx — jangan diubah tangan.
-- Jalankan SEKALI di Supabase SQL Editor, SETELAH migrasi_invoice.sql dan migrasi_pl_do.sql.
-- Akibatnya Packing List lama tidak lagi muncul sebagai "belum ditagih" di form Invoice Baru.
-- Aman diulang: pasangan yang sudah tertaut dilewati; pasangan yang dokumennya tidak ada hanya dilaporkan.
-- ============================================================================
do $mig$
declare
  v jsonb := $json${json.dumps(pairs, ensure_ascii=False, separators=(",", ":"))}$json$;
  v_all jsonb := $json${json.dumps([i['no'] for i in invs], separators=(',', ':'))}$json$;
  r jsonb; v_inv uuid; v_pl uuid; v_cur uuid; v_taken text;
  n_ok int := 0; n_already int := 0; n_miss int := 0; n_auto int := 0; miss text := '';
begin
  for r in select * from jsonb_array_elements(v) loop
    select id, pl_id into v_inv, v_cur from public.invoices where doc_number = r->>'inv' and deleted_at is null;
    select id into v_pl from public.packing_lists where doc_number = r->>'pl' and deleted_at is null;
    if v_inv is null or v_pl is null then
      n_miss := n_miss + 1; miss := miss || case when miss = '' then '' else ', ' end || (r->>'inv') || '/' || (r->>'pl'); continue;
    end if;
    if v_cur is not null then n_already := n_already + 1; continue; end if;
    select doc_number into v_taken from public.invoices where pl_id = v_pl and status <> 'VOID' and deleted_at is null;
    if v_taken is not null then n_miss := n_miss + 1; miss := miss || case when miss = '' then '' else ', ' end || (r->>'pl') || ' sudah dipakai ' || v_taken; continue; end if;
    update public.invoices i set pl_id = v_pl, ro_id = coalesce(i.ro_id, (select ro_id from public.packing_lists where id = v_pl)) where i.id = v_inv;
    n_ok := n_ok + 1;
  end loop;
  -- Tahap 2: invoice arsip yang masih belum bertaut (mis. invoice terbaru yang belum ada di rekap) dipasangkan otomatis
  -- bila hanya ada satu Packing List yang cocok: pelanggan sama, tanggal sama (+-1 hari), berat sama (+-0,5%) dan belum ditagih.
  with c as (
    select i.id as inv_id, p.id as pl_id,
           (select coalesce(sum(qty), 0) from public.pl_items where pl_id = p.id) as wp,
           (select coalesce(sum(qty), 0) from public.inv_items where inv_id = i.id) as wi
      from public.invoices i
      join public.packing_lists p on p.customer_id = i.customer_id and abs(p.pack_date - i.invoice_date) <= 1
     where i.pl_id is null and i.status <> 'VOID' and i.deleted_at is null and i.doc_number in (select jsonb_array_elements_text(v_all))
       and p.deleted_at is null and p.status in ('PACKED','DELIVERED')
       and not exists (select 1 from public.invoices x where x.pl_id = p.id and x.status <> 'VOID' and x.deleted_at is null)
  ), m as (
    select * from c where wi > 0 and abs(wp - wi) <= 0.005 * greatest(wp, 0.001)
  ), u as (
    select inv_id, pl_id from m
     where inv_id in (select inv_id from m group by 1 having count(*) = 1) and pl_id in (select pl_id from m group by 1 having count(*) = 1)
  )
  update public.invoices i set pl_id = u.pl_id, ro_id = coalesce(i.ro_id, (select ro_id from public.packing_lists where id = u.pl_id))
    from u where i.id = u.inv_id;
  get diagnostics n_auto = row_count;
  raise notice 'Selesai: % invoice ditautkan menurut rekap, % ditautkan otomatis (tahap 2), % sudah tertaut sebelumnya, % dilewati (dokumen tidak ditemukan / PL terpakai).', n_ok, n_auto, n_already, n_miss;
  if miss <> '' then raise notice 'Dilewati: %', miss; end if;
end
$mig$;
"""
open(OUT, "w").write(sql)
print(f"pasangan {len(pairs)}")
for c in CAT: print("CATATAN:", c)
