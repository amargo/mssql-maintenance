#!/bin/bash
set -euo pipefail

MODE="${BACKUP_FILE_COMPRESS:-none}"
DIR="${BACKUP_HOST_DIR:-/backup}"
OUT_DIR="${BACKUP_FILE_COMPRESS_DIR:-/backup-compressed}"
LEVEL="${BACKUP_FILE_COMPRESS_LEVEL:-6}"
DELETE_ORIGINAL="${BACKUP_FILE_COMPRESS_DELETE_ORIGINAL:-N}"
MIN_AGE="${BACKUP_FILE_COMPRESS_MIN_AGE_MINUTES:-5}"
BACKUP_FULL_CLEANUP_TIME="${BACKUP_FULL_CLEANUP_TIME-168}"
BACKUP_DIFF_CLEANUP_TIME="${BACKUP_DIFF_CLEANUP_TIME-48}"

if [ "${MODE}" = "none" ] || [ -z "${MODE}" ]; then
    echo "$(date): Backup file compression disabled (BACKUP_FILE_COMPRESS=${MODE})."
    exit 0
fi

case "${MODE}" in
  zstd)
    EXT="zst"
    LEVEL_PATTERN='^([1-9]|1[0-9])$'
    LEVEL_ERROR="zstd compression level must be an integer from 1 to 19."
    ;;
  gz)
    EXT="gz"
    LEVEL_PATTERN='^[1-9]$'
    LEVEL_ERROR="gzip compression level must be an integer from 1 to 9."
    ;;
  7z)
    EXT="7z"
    LEVEL_PATTERN='^[0-9]$'
    LEVEL_ERROR="7z compression level must be an integer from 0 to 9."
    ;;
  *)
    echo "$(date): Unsupported BACKUP_FILE_COMPRESS=${MODE}" >&2
    exit 1
    ;;
esac

if ! [[ "${LEVEL}" =~ ${LEVEL_PATTERN} ]]; then
    echo "$(date): ${LEVEL_ERROR}" >&2
    exit 1
fi

for CLEANUP_VALUE in BACKUP_FULL_CLEANUP_TIME BACKUP_DIFF_CLEANUP_TIME; do
    if ! [[ "${!CLEANUP_VALUE}" =~ ^[1-9][0-9]*$ ]]; then
        echo "$(date): ${CLEANUP_VALUE} must be a positive integer number of hours." >&2
        exit 1
    fi
done

if [ ! -d "${DIR}" ]; then
    echo "$(date): Backup directory ${DIR} not mounted; skipping file compression."
    exit 0
fi

if [ ! -d "${OUT_DIR}" ]; then
    echo "$(date): Compressed backup directory ${OUT_DIR} not mounted; skipping file compression."
    exit 0
fi

COMPRESS_ERRORS=0
while IFS= read -r -d '' FILE; do
    # Skip already-compressed files.
    case "${FILE}" in
        *.zst|*.7z|*.gz|*.zip) continue ;;
    esac

    RELATIVE_FILE="${FILE#"${DIR}"/}"
    DEST="${OUT_DIR}/${RELATIVE_FILE}.${EXT}"
    TMP_DEST="${DEST}.tmp.$$"
    DEST_DIR="$(dirname -- "${DEST}")"

    if [ -f "${DEST}" ]; then
        echo "$(date): Skipping (already compressed): ${FILE}"
        continue
    fi

    echo "$(date): Compressing: ${FILE} -> ${DEST}"
    mkdir -p -- "${DEST_DIR}"
    rm -f -- "${TMP_DEST}"

    COMPRESS_OK=0
    case "${MODE}" in
      zstd)
        if zstd -T0 -"${LEVEL}" --keep -q -o "${TMP_DEST}" -- "${FILE}"; then
            COMPRESS_OK=1
        fi
        ;;
      gz)
        if gzip -"${LEVEL}" -c -- "${FILE}" > "${TMP_DEST}"; then
            COMPRESS_OK=1
        fi
        ;;
      7z)
        if 7z a -t7z -mx="${LEVEL}" -- "${TMP_DEST}" "${FILE}"; then
            COMPRESS_OK=1
        fi
        ;;
    esac

    if [ "${COMPRESS_OK}" -eq 1 ] && mv -- "${TMP_DEST}" "${DEST}"; then
        if [ "${DELETE_ORIGINAL}" = "Y" ] || [ "${DELETE_ORIGINAL}" = "y" ]; then
            rm -- "${FILE}"
            echo "$(date): Compressed (original deleted): ${DEST}"
        else
            echo "$(date): Compressed (original kept): ${DEST}"
        fi
    else
        rm -f -- "${TMP_DEST}"
        echo "$(date): ERROR compressing: ${FILE}" >&2
        COMPRESS_ERRORS=$((COMPRESS_ERRORS + 1))
    fi
done < <(find "${DIR}" -type f \( -name "*.bak" -o -name "*.trn" -o -name "*.dif" \) -mmin +"${MIN_AGE}" -print0)

if [ "${COMPRESS_ERRORS}" -gt 0 ]; then
    echo "$(date): Compression finished with ${COMPRESS_ERRORS} error(s)." >&2
    exit 1
fi

cleanup_compressed_archives() {
    local full_cleanup_minutes=$((BACKUP_FULL_CLEANUP_TIME * 60))
    local diff_cleanup_minutes=$((BACKUP_DIFF_CLEANUP_TIME * 60))
    local full_deleted=0
    local diff_deleted=0
    local backup_type=""

    while IFS= read -r -d '' FILE; do
        case "${FILE}" in
            */FULL/*)
                backup_type="FULL"
                full_deleted=$((full_deleted + 1))
                ;;
            */DIFF/*)
                backup_type="DIFF"
                diff_deleted=$((diff_deleted + 1))
                ;;
            *)
                continue
                ;;
        esac

        rm -- "${FILE}"
        echo "$(date): Deleted expired compressed ${backup_type} backup: ${FILE}"
    done < <(find "${OUT_DIR}" -type f \
        \( \( -path "*/FULL/*" -mmin +"${full_cleanup_minutes}" \) \
           -o \( -path "*/DIFF/*" -mmin +"${diff_cleanup_minutes}" \) \) \
        \( -name "*.bak.zst" -o -name "*.bak.gz" -o -name "*.bak.7z" \
           -o -name "*.dif.zst" -o -name "*.dif.gz" -o -name "*.dif.7z" \
           -o -name "*.trn.zst" -o -name "*.trn.gz" -o -name "*.trn.7z" \) \
        -print0)

    echo "$(date): Compressed FULL cleanup complete (${full_deleted} file(s) deleted, retention ${BACKUP_FULL_CLEANUP_TIME} hour(s))."
    echo "$(date): Compressed DIFF cleanup complete (${diff_deleted} file(s) deleted, retention ${BACKUP_DIFF_CLEANUP_TIME} hour(s))."
}

cleanup_compressed_archives

echo "$(date): Compression pass complete."
