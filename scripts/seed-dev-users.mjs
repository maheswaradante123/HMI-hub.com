// Membuat 6 user dummy untuk development lewat Supabase Auth Admin API.
// Jalankan SETELAH migrasi dan seed.sql, hanya di lokal/server (memakai service role key):
//   DEV_SEED_PASSWORD='isi-password-dev' node --env-file=.env.local scripts/seed-dev-users.mjs
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const password = process.env.DEV_SEED_PASSWORD;
if (!url || !key || !password) {
  console.error("Isi NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, dan DEV_SEED_PASSWORD.");
  process.exit(1);
}

const admin = createClient(url, key, { auth: { persistSession: false } });

const users = [
  { email: "owner@hmi.test", name: "Owner Dummy", role: "OWNER", dept: "Owner" },
  { email: "marketing@hmi.test", name: "Marketing Dummy", role: "MARKETING", dept: "Marketing" },
  { email: "purchasing@hmi.test", name: "Purchasing Dummy", role: "PURCHASING", dept: "Purchasing" },
  { email: "accounting@hmi.test", name: "Accounting Dummy", role: "ACCOUNTING", dept: "Accounting" },
  { email: "produksi@hmi.test", name: "Produksi Dummy", role: "PRODUKSI", dept: "Produksi Toko" },
  { email: "kasir@hmi.test", name: "Kasir Dummy", role: "KASIR", dept: "Kasir" },
];

const { data: roles } = await admin.from("roles").select("id, code");
const { data: depts } = await admin.from("departments").select("id, name");

for (const u of users) {
  let id;
  const created = await admin.auth.admin.createUser({
    email: u.email,
    password,
    email_confirm: true,
  });
  if (created.error) {
    const list = await admin.auth.admin.listUsers({ perPage: 200 });
    id = list.data?.users.find((x) => x.email === u.email)?.id;
    if (!id) {
      console.error(u.email, created.error.message);
      continue;
    }
  } else {
    id = created.data.user.id;
  }
  const { error } = await admin.from("user_profiles").upsert({
    id,
    full_name: u.name,
    role_id: roles.find((r) => r.code === u.role).id,
    department_id: depts.find((d) => d.name === u.dept)?.id ?? null,
    is_active: true,
  });
  console.log(error ? `GAGAL ${u.email}: ${error.message}` : `OK ${u.email} (${u.role})`);
}
