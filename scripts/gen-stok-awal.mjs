// Membuat supabase/data/stok_awal_daging.sql dari supabase/data/stok_awal_daging.tsv
// (salinan data aplikasi lama La Mitra: kode, nama, kategori lama, stok, satuan).
// Aturan: semua stok = gram → kg (÷1000) KECUALI Otak (pcs, angka apa adanya);
// kategori = awalan kode terbanyak per jenis item; lot = kode sapi.
import fs from "node:fs";
const dir = new URL("../supabase/data/", import.meta.url);
const rows = fs.readFileSync(new URL("stok_awal_daging.tsv", dir), "utf8").trim().split("\n").map((l) => l.split("\t"));

const COW = /(NUR|AMF|REOT|AINUL|OKA|RPH)\s*(\d{3})\s*$/i;
const ITEMS = [
  [/^tulangsumsum$/, "Tulang Sumsum"], [/^(tulangsup|tulangsop|sop)(kr)?$/, "Tulang Sop"],
  [/^shortribs?$/, "Short Ribs"], [/^babathanduk$/, "Babat Handuk"], [/^sandunglamur$/, "Sandung Lamur"],
  [/^hasluar$/, "Has Luar"], [/^hasdalam$/, "Has Dalam"], [/^sancan$/, "Sancan"], [/^punuk$/, "Punuk"],
  [/^gandik$/, "Gandik"], [/^topside$/, "Topside"], [/^knuckle$/, "Knuckle"], [/^(sampil|saampil)$/, "Sampil"],
  [/^lamusir$/, "Lamusir"], [/^babat$/, "Babat"], [/^(usus|uus)$/, "Usus"], [/^hati$/, "Hati"],
  [/^jantung$/, "Jantung"], [/^paru$/, "Paru"], [/^(limpa|limpah|limfa)$/, "Limpa"], [/^ginjal$/, "Ginjal"],
  [/^otak$/, "Otak"], [/^buntut(rph)?$/, "Buntut"],
];
const CAT = { DG: "Daging", JR: "Jeroan", TL: "Tulang" };

const parsed = rows.map(([code, name, , qty]) => {
  const m = code.match(/^(DG|JR|TL)(\d*)([A-Z]+\d{3})?$/i);
  const prefix = m ? m[1].toUpperCase() : null;
  const cow = (m?.[3] ?? (name.match(COW) ? name.match(COW)[1] + name.match(COW)[2] : null))?.toUpperCase() ?? null;
  const base = name.replace(COW, "").replace(/\s+/g, "").toLowerCase();
  const item = ITEMS.find(([re]) => re.test(base))?.[1];
  if (!item) throw new Error(`Item tak dikenal: ${code} / ${name}`);
  return { code, item, prefix, lot: cow, grams: Number(qty) };
});

// Kategori per jenis item = awalan terbanyak (kode tanpa pola → ikut jenis lain / default Tulang untuk Short Ribs & Tulang Sop)
const tally = {};
for (const r of parsed) if (r.prefix) (tally[r.item] ??= {})[r.prefix] = (tally[r.item][r.prefix] ?? 0) + 1;
const catOf = {};
for (const it of new Set(parsed.map((r) => r.item))) {
  const t = tally[it] ?? { TL: 1 };
  catOf[it] = CAT[Object.entries(t).sort((a, b) => b[1] - a[1])[0][0]];
}
const unitOf = (it) => (it === "Otak" ? "PCS" : "KG");

const agg = new Map();
for (const r of parsed) {
  const k = `${r.item}|${r.lot ?? ""}`;
  const a = agg.get(k) ?? { item: r.item, lot: r.lot, qty: 0, codes: [] };
  a.qty += r.item === "Otak" ? r.grams : r.grams / 1000;
  a.codes.push(r.code);
  agg.set(k, a);
}
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
const list = [...agg.values()].sort((a, b) => a.item.localeCompare(b.item) || (a.lot ?? "").localeCompare(b.lot ?? ""));
const items = [...new Set(list.map((r) => r.item))].sort();

const sql = `-- ============================================================================
-- Migrasi stok awal daging/tulang/jeroan dari aplikasi lama (Product Management La Mitra)
-- DIBUAT OTOMATIS oleh scripts/gen-stok-awal.mjs dari supabase/data/stok_awal_daging.tsv
-- Jalankan SEKALI di Supabase SQL Editor (aman diulang: berhenti jika sudah pernah dijalankan).
--
-- UBAH 2 BARIS INI SEBELUM MENJALANKAN:
--   v_date : tanggal stok dihitung ("cut-off"), tidak boleh di masa depan
--   v_wh   : kode gudang tujuan
-- ============================================================================
do $mig$
declare
  v_date  date := (now() at time zone 'Asia/Jakarta')::date;   -- << tanggal cut-off
  v_wh    text := 'GD-TOKO';                                   -- << kode gudang
  v_whid  uuid; v_pid uuid; v_cat uuid; v_unit uuid; v_code text; v_i int;
  r record; n_new int := 0; n_old int := 0; n_mov int := 0;
  c_marker constant text := 'Migrasi stok awal La Mitra';
begin
  select id into v_whid from public.warehouses where code = v_wh and is_active;
  if v_whid is null then raise exception 'Gudang % tidak ditemukan', v_wh; end if;
  if v_date > (now() at time zone 'Asia/Jakarta')::date then raise exception 'Tanggal cut-off tidak boleh di masa depan'; end if;
  if exists (select 1 from public.stock_movements where note like c_marker || '%') then
    raise exception 'Migrasi ini sudah pernah dijalankan — dihentikan agar stok tidak ganda';
  end if;

  -- 1) Master item: cocokkan nama (tanpa huruf besar/kecil); belum ada → dibuat (MANUFACTURE)
  for r in select * from (values
${items.map((it) => `    (${q(it)}, ${q(catOf[it])}, ${q(unitOf(it))})`).join(",\n")}
  ) as t(name, cat, unit) loop
    select id into v_pid from public.products where lower(name) = lower(r.name);
    if v_pid is null then
      select id into v_cat from public.product_categories where code = case r.cat when 'Tulang' then 'TULANG' when 'Jeroan' then 'JEROHAN' else 'DAGING' end;
      select id into v_unit from public.units where code = r.unit;
      if v_cat is null or v_unit is null then raise exception 'Kategori/satuan untuk % belum ada di master', r.name; end if;
      v_code := trim(both '-' from left(upper(regexp_replace(r.name, '[^A-Za-z0-9]+', '-', 'g')), 30)); v_i := 0;
      while exists (select 1 from public.products where code = case when v_i = 0 then v_code else v_code || '-' || v_i end) loop v_i := v_i + 1; end loop;
      insert into public.products (code, name, product_type, category_id, unit_id)
      values (case when v_i = 0 then v_code else v_code || '-' || v_i end, r.name, 'MANUFACTURE', v_cat, v_unit);
      n_new := n_new + 1;
    else
      n_old := n_old + 1;
    end if;
  end loop;

  -- 2) Stok awal per item per kode sapi (kg; Otak = pcs). lot kosong = tanpa kode sapi.
  for r in select * from (values
${list.map((a) => `    (${q(a.item)}, ${a.lot ? q(a.lot) : "null::text"}, ${Number(a.qty.toFixed(3))}::numeric, ${q(a.codes.join(", "))})`).join(",\n")}
  ) as t(name, lot, qty, codes) loop
    select id into v_pid from public.products where lower(name) = lower(r.name);
    perform public.post_stock(v_pid, v_whid, 'OPENING', r.qty, null, 'MANUAL', null,
      c_marker || ' (kode lama: ' || r.codes || ')', v_date, r.lot);
    n_mov := n_mov + 1;
  end loop;

  raise notice 'Selesai: % item baru, % item sudah ada di master, % baris stok awal.', n_new, n_old, n_mov;
end
$mig$;

-- Cek hasil (jalankan terpisah):
-- select p.name, sum(m.qty) as total from public.stock_movements m join public.products p on p.id = m.product_id
--  where m.note like 'Migrasi stok awal La Mitra%' group by p.name order by p.name;
`;
fs.writeFileSync(new URL("stok_awal_daging.sql", dir), sql);

// Ringkasan untuk laporan
const kg = list.filter((r) => r.item !== "Otak").reduce((s, r) => s + r.qty, 0);
console.log(`baris sumber ${rows.length} → baris stok ${list.length}, jenis item ${items.length}, kode sapi ${new Set(list.map((r) => r.lot)).size - 1}`);
console.log(`total non-Otak ${kg.toFixed(3)} kg; Otak ${list.filter((r) => r.item === "Otak").reduce((s, r) => s + r.qty, 0)} pcs`);
console.log("gabungan (>1 kode lama):", list.filter((r) => r.codes.length > 1).map((r) => `${r.item}/${r.lot}: ${r.codes}`));
console.log("kategori:", Object.entries(catOf).map(([k, v]) => `${k}=${v}`).join(", "));
console.log("tally tidak bulat:", Object.entries(tally).filter(([, t]) => Object.keys(t).length > 1).map(([k, t]) => `${k}:${JSON.stringify(t)}`));
