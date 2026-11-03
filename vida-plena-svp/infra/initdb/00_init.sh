#!/usr/bin/env bash
# Executado uma única vez pela imagem oficial do PostgreSQL na primeira
# subida (volume vazio). Cria os bancos, aplica os scripts e define as
# senhas dos papéis a partir das variáveis de ambiente (secrets).
set -euo pipefail
P="psql -v ON_ERROR_STOP=1 -q --username $POSTGRES_USER"

$P -d postgres -c "CREATE DATABASE svp" -c "CREATE DATABASE svp_dw"
for f in /svp/database/scripts/0*.sql; do
  echo ">> $f"; $P -d svp -f "$f" >/dev/null
done
if [[ "${SVP_CARREGAR_DEMO:-sim}" == "sim" ]]; then
  echo ">> seed de demonstração"; $P -d svp -f /svp/database/data/seed.sql >/dev/null
fi
echo ">> data warehouse"; $P -d svp_dw -f /svp/database/dw/01_dw.sql >/dev/null

$P -d postgres <<SQL
ALTER ROLE svp_api PASSWORD '${SVP_API_PASSWORD}';
ALTER ROLE svp_etl PASSWORD '${SVP_ETL_PASSWORD}';
ALTER ROLE svp_bi  PASSWORD '${SVP_BI_PASSWORD}';
SQL
echo "SVP: bancos prontos"
