#!/usr/bin/env bash
# Aplica todos os scripts em ordem num PostgreSQL vazio.
# Uso: PGHOST=localhost PGUSER=postgres ./database/aplicar.sh [--sem-seed]
set -euo pipefail
cd "$(dirname "$0")"
P="psql -v ON_ERROR_STOP=1 -q"
$P -d postgres -c "CREATE DATABASE svp" -c "CREATE DATABASE svp_dw"
for f in scripts/0*.sql; do echo ">> $f"; $P -d svp -f "$f" >/dev/null; done
[[ "${1:-}" == "--sem-seed" ]] || { echo ">> data/seed.sql"; $P -d svp -f data/seed.sql >/dev/null; }
echo ">> dw/01_dw.sql"; $P -d svp_dw -f dw/01_dw.sql >/dev/null
# senhas dos papéis vêm do ambiente (secrets), nunca dos scripts
$P -d postgres \
  -c "ALTER ROLE svp_api PASSWORD '${SVP_API_PASSWORD:?defina SVP_API_PASSWORD}'" \
  -c "ALTER ROLE svp_etl PASSWORD '${SVP_ETL_PASSWORD:?defina SVP_ETL_PASSWORD}'" \
  -c "ALTER ROLE svp_bi  PASSWORD '${SVP_BI_PASSWORD:?defina SVP_BI_PASSWORD}'"
echo "ok"
