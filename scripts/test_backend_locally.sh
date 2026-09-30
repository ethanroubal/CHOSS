#!/usr/bin/env bash
# Applies every migration and the seed to a throwaway local Postgres, then runs the behaviour
# tests (acting as signed-in users, so Row Level Security applies). Needs Postgres 15+ with the
# pg_trgm, unaccent and citext extensions (e.g. `brew install postgresql@16`).
#
#   scripts/test_backend_locally.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DIR="$(mktemp -d)"
PORT=55432
trap 'pg_ctl -D "$DIR/data" stop -m fast >/dev/null 2>&1 || true; rm -rf "$DIR"' EXIT

initdb -D "$DIR/data" -A trust -U postgres >/dev/null
pg_ctl -D "$DIR/data" -o "-k $DIR -p $PORT -c listen_addresses=" -l "$DIR/log" start >/dev/null
PSQL=(psql -h "$DIR" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -q)
"${PSQL[@]}" -c "create database choss" >/dev/null

for f in supabase/tests/00_local_supabase_stub.sql supabase/migrations/*.sql supabase/seed.sql; do
  echo "applying $f"
  "${PSQL[@]}" -d choss -f "$f" >/dev/null
done
for f in supabase/tests/1*.sql supabase/tests/2*.sql; do
  echo "== $f"
  "${PSQL[@]}" -d choss -f "$f" | grep -v '^$' | grep -v 'set_config\|^ 0000'
done
echo "All backend checks passed."
