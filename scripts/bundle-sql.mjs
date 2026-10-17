// Menggabungkan semua migrasi (berurutan) menjadi satu file untuk SQL Editor Supabase.
// Seed data dummy sengaja dipisah karena hanya untuk development.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";

const dir = new URL("../supabase/migrations/", import.meta.url);
const files = readdirSync(dir).filter((f) => f.endsWith(".sql")).sort();
const out = files.map((f) => `-- ===== ${f} =====\n${readFileSync(new URL(f, dir), "utf8")}`).join("\n\n");
writeFileSync(new URL("../supabase/all_migrations.sql", import.meta.url), out);
console.log(`Digabung ${files.length} migrasi -> supabase/all_migrations.sql`);

// Seed produksi: hanya departemen, role, izin, dan matriks izin (tanpa data dummy).
const seed = readFileSync(new URL("../supabase/seed.sql", import.meta.url), "utf8");
const marker = "-- ===============================================================\n-- Seed Phase 4: master data dummy";
const cut = seed.indexOf(marker);
if (cut < 0) throw new Error("Penanda akhir seed produksi tidak ditemukan di seed.sql");
writeFileSync(new URL("../supabase/seed_production.sql", import.meta.url), seed.slice(0, cut));
console.log("Seed produksi -> supabase/seed_production.sql");
