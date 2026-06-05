#!/bin/bash
set -euo pipefail

COMPRESS_PARAMS=""
if [ -n "${BACKUP_COMPRESS:-}" ]; then
    COMPRESS_PARAMS="@Compress = '${BACKUP_COMPRESS}',"
fi

BACKUP_DIFF_CLEANUP_TIME="${BACKUP_DIFF_CLEANUP_TIME-48}"
if ! [[ "${BACKUP_DIFF_CLEANUP_TIME}" =~ ^[1-9][0-9]*$ ]]; then
    echo "$(date): BACKUP_DIFF_CLEANUP_TIME must be a positive integer number of hours." >&2
    exit 1
fi

ENCRYPT_PARAMS=""
if [ -n "${BACKUP_ENCRYPT_PASSWORD:-}" ]; then
    ENCRYPT_PARAMS="@Encrypt = 'Y', @EncryptionAlgorithm = 'AES_256', @EncryptionKey = '${BACKUP_ENCRYPT_PASSWORD}',"
fi

echo "$(date): Starting differential backup..."
sqlcmd -S "${MSSQL_HOST}" -U sa -P "${MSSQL_SA_PASSWORD}" -C -Q "
EXEC master.dbo.DatabaseBackup
  @Databases   = 'USER_DATABASES',
  @Directory   = '/var/opt/mssql/backup',
  @BackupType  = 'DIFF',
  ${COMPRESS_PARAMS}
  ${ENCRYPT_PARAMS}
  @CleanupTime = ${BACKUP_DIFF_CLEANUP_TIME},
  @LogToTable  = 'Y';"
echo "$(date): Differential backup done."

/scripts/compress-backups.sh
