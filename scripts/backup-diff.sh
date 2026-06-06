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

BACKUP_DIRECTORY_STRUCTURE="${BACKUP_DIRECTORY_STRUCTURE:-{DatabaseName}{DirectorySeparator}{BackupType}}"
BACKUP_FILE_NAME="${BACKUP_FILE_NAME:-{DatabaseName}_{BackupType}_{Year}{Month}{Day}_{Hour}{Minute}{Second}_{FileNumber}.{FileExtension}}"

BACKUP_DIRECTORY_STRUCTURE_SQL="${BACKUP_DIRECTORY_STRUCTURE//\'/\'\'}"
BACKUP_FILE_NAME_SQL="${BACKUP_FILE_NAME//\'/\'\'}"

echo "$(date): Starting differential backup..."
sqlcmd -S "${MSSQL_HOST}" -U sa -P "${MSSQL_SA_PASSWORD}" -C -Q "
EXEC master.dbo.DatabaseBackup
  @Databases   = 'USER_DATABASES',
  @Directory   = '/var/opt/mssql/backup',
  @BackupType  = 'DIFF',
  ${COMPRESS_PARAMS}
  ${ENCRYPT_PARAMS}
  @DirectoryStructure = '${BACKUP_DIRECTORY_STRUCTURE_SQL}',
  @FileName = '${BACKUP_FILE_NAME_SQL}',
  @CleanupTime = ${BACKUP_DIFF_CLEANUP_TIME},
  @LogToTable  = 'Y';"
echo "$(date): Differential backup done."

/scripts/compress-backups.sh
