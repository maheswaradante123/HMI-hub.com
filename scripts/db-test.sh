#!/usr/bin/env bash
# Menjalankan semua migrasi, seed, dan pengujian database pada PostgreSQL KOSONG untuk uji coba.
# JANGAN diarahkan ke database Supabase produksi: skrip ini membuat tiruan schema auth.
#   TEST_DATABASE_URL=postgres://user:pass@localhost:5432/hmitest scripts/db-test.sh
set -euo pipefail
: "${TEST_DATABASE_URL:?Isi TEST_DATABASE_URL dengan database uji yang kosong}"
cd "$(dirname "$0")/.."
run() { echo "== $1"; psql -q -v ON_ERROR_STOP=1 "$TEST_DATABASE_URL" -f "$1"; }

run supabase/tests/00_mock_supabase.sql
for f in supabase/migrations/*.sql; do run "$f"; done
run supabase/seed.sql
for f in supabase/tests/0[1-9]_*.sql; do run "$f"; done
echo "Semua pengujian database selesai."
