#!/usr/bin/env bash
# Prueba las migraciones en un PostgreSQL local vacío (no toca Supabase).
# Uso: DB_URL=postgres://user@localhost/postgres supabase/tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DB_URL="${DB_URL:-postgres://postgres@localhost/postgres}"
psql "$DB_URL" -q -c "drop database if exists ula_test" -c "create database ula_test"
TEST_URL="${DB_URL%/*}/ula_test"
psql "$TEST_URL" -q -v ON_ERROR_STOP=1 -f tests/stub_auth.sql
for f in migrations/*.sql; do psql "$TEST_URL" -q -v ON_ERROR_STOP=1 -f "$f"; done
for t in tests/permisos_test.sql tests/despensa_test.sql; do psql "$TEST_URL" -q -v ON_ERROR_STOP=1 -f "$t"; done
