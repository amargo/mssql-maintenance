#!/bin/bash
echo "$(date): Starting index optimization..."
sqlcmd -S "${MSSQL_HOST}" -U sa -P "${MSSQL_SA_PASSWORD}" -C -Q "
EXEC master.dbo.IndexOptimize
  @Databases           = 'USER_DATABASES',
  @FragmentationLow    = NULL,
  @FragmentationMedium = 'INDEX_REORGANIZE',
  @FragmentationHigh   = 'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
  @LogToTable          = 'Y';"
echo "$(date): Index optimization done."
