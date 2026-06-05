#!/bin/bash
set -e
LOG=/logs/install-cert.log

if [ -z "${BACKUP_CERT_NAME}" ] || [ -z "${BACKUP_CERT_FILE}" ]; then
    echo "$(date): BACKUP_CERT_NAME/BACKUP_CERT_FILE not set, skipping cert install." | tee -a "$LOG"
    exit 0
fi

INSTALLED=$(sqlcmd -S "${MSSQL_HOST}" -U sa -P "${MSSQL_SA_PASSWORD}" -C \
    -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM master.sys.certificates WHERE name = '${BACKUP_CERT_NAME}'" \
    -h -1 2>/dev/null | tr -d ' \r\n')

if [ "${INSTALLED}" = "1" ]; then
    echo "$(date): Cert '${BACKUP_CERT_NAME}' already installed, skipping." | tee -a "$LOG"
    exit 0
fi

echo "$(date): Installing backup encryption cert '${BACKUP_CERT_NAME}'..." | tee -a "$LOG"

# Ensure database master key exists in master
sqlcmd -S "${MSSQL_HOST}" -U sa -P "${MSSQL_SA_PASSWORD}" -C -Q "
USE master;
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '${BACKUP_MASTER_KEY_PASSWORD}';" >> "$LOG" 2>&1

# Import certificate from file (file must be accessible by SQL Server process)
sqlcmd -S "${MSSQL_HOST}" -U sa -P "${MSSQL_SA_PASSWORD}" -C -Q "
USE master;
CREATE CERTIFICATE [${BACKUP_CERT_NAME}]
FROM FILE = '${BACKUP_CERT_FILE}'
WITH PRIVATE KEY (
    FILE = '${BACKUP_CERT_KEY_FILE}',
    DECRYPTION BY PASSWORD = '${BACKUP_CERT_KEY_PASSWORD}'
);" >> "$LOG" 2>&1

echo "$(date): Cert installed successfully." | tee -a "$LOG"
