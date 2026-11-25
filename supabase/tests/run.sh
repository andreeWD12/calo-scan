#!/usr/bin/env bash
# Applica tutte le migrazioni a un database vuoto e lancia i test di sicurezza.
# Uso: PGHOST=... PGPORT=... PGUSER=postgres supabase/tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."
psql -v ON_ERROR_STOP=1 -q -c "drop database if exists caloscan_test" -c "create database caloscan_test"
export PGDATABASE=caloscan_test
psql -v ON_ERROR_STOP=1 -q -f tests/supabase_shim.sql
for f in migrations/*.sql; do psql -v ON_ERROR_STOP=1 -q -f "$f"; done
psql -v ON_ERROR_STOP=1 -q -f tests/security_test.sql
