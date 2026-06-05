#!/bin/bash
set -e
LOG=/logs/install-ola.log

INSTALLED=$(sqlcmd -S "${MSSQL_HOST}" -U sa -P "${MSSQL_SA_PASSWORD}" -C \
    -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM master.sys.objects WHERE name = 'DatabaseBackup'" \
    -h -1 2>/dev/null | tr -d ' \r\n')

if [ "${INSTALLED}" = "1" ]; then
    echo "$(date): Ola already installed, skipping." | tee -a "$LOG"
    exit 0
fi

echo "$(date): Installing Ola Hallengren maintenance solution..." | tee -a "$LOG"

curl -fsSL "https://raw.githubusercontent.com/olahallengren/sql-server-maintenance-solution/master/MaintenanceSolution.sql" \
    -o /tmp/MaintenanceSolution.sql

sqlcmd -S "${MSSQL_HOST}" -U sa -P "${MSSQL_SA_PASSWORD}" -C \
    -i /tmp/MaintenanceSolution.sql >> "$LOG" 2>&1

rm -f /tmp/MaintenanceSolution.sql
echo "$(date): Ola installed successfully." | tee -a "$LOG"
