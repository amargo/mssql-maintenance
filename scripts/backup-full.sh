#!/bin/bash
set -euo pipefail

COMPRESS_PARAMS=""
if [ -n "${BACKUP_COMPRESS:-}" ]; then
    COMPRESS_PARAMS="@Compress = '${BACKUP_COMPRESS}',"
fi

ENCRYPT_PARAMS=""
if [ -n "${BACKUP_ENCRYPT_PASSWORD:-}" ]; then
    ENCRYPT_PARAMS="@Encrypt = 'Y', @EncryptionAlgorithm = 'AES_256', @EncryptionKey = '${BACKUP_ENCRYPT_PASSWORD}',"
fi

echo "$(date): Starting full backup..."
sqlcmd -S "${MSSQL_HOST}" -U sa -P "${MSSQL_SA_PASSWORD}" -C -Q "
EXEC master.dbo.DatabaseBackup
  @Databases   = 'USER_DATABASES',
  @Directory   = '/var/opt/mssql/backup',
  @BackupType  = 'FULL',
  ${COMPRESS_PARAMS}
  ${ENCRYPT_PARAMS}
  @CleanupTime = 168,
  @LogToTable  = 'Y';"
echo "$(date): Full backup done."

/scripts/compress-backups.sh
