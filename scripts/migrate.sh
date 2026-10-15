#!/usr/bin/env bash
# Applies every migration in order, each in its own transaction.
# Stops at the first error so a broken migration never half-applies.
#
# Usage: scripts/migrate.sh            (uses PG* environment variables)
#        PGDATABASE=talentra_test scripts/migrate.sh
set -euo pipefail

cd "$(dirname "$0")/.."

# Migrations act as the system account (user_account id 1) so audit columns are filled.
export PGOPTIONS="${PGOPTIONS:-} -c app.user_id=1 -c client_min_messages=warning"

for file in migrations/*.sql; do
    printf '%-55s' "$file"
    psql --quiet --no-psqlrc --set ON_ERROR_STOP=1 --single-transaction --file "$file" > /dev/null
    echo "ok"
done
