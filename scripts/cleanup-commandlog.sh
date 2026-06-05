#!/bin/bash
echo "$(date): Cleaning up CommandLog (older than 30 days)..."
sqlcmd -S "${MSSQL_HOST}" -U sa -P "${MSSQL_SA_PASSWORD}" -C -Q "
DELETE FROM master.dbo.CommandLog WHERE StartTime < DATEADD(dd, -30, GETDATE());"
echo "$(date): CommandLog cleanup done."
