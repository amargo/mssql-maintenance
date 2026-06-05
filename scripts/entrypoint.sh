#!/bin/bash
set -e

mkdir -p /logs

echo "$(date): Waiting for SQL Server..."
until sqlcmd -S "${MSSQL_HOST}" -U sa -P "${MSSQL_SA_PASSWORD}" -C -Q "SELECT 1" > /dev/null 2>&1; do
    sleep 5
done
echo "$(date): SQL Server ready."

/scripts/install-ola.sh

exec crond -f -l 8
