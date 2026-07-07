#!/bin/bash
set -euo pipefail

echo "$(date): Starting integrity check..."
sqlcmd -S "${MSSQL_HOST}" -U sa -P "${MSSQL_SA_PASSWORD}" -C -b -Q "
EXEC master.dbo.DatabaseIntegrityCheck
  @Databases  = 'USER_DATABASES',
  @LogToTable = 'Y';"
echo "$(date): Integrity check done."
