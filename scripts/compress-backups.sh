#!/bin/bash
set -euo pipefail

MODE="${BACKUP_FILE_COMPRESS:-none}"
DIR="${BACKUP_HOST_DIR:-/backup}"
LEVEL="${BACKUP_FILE_COMPRESS_LEVEL:-6}"
DELETE_ORIGINAL="${BACKUP_FILE_COMPRESS_DELETE_ORIGINAL:-N}"
MIN_AGE="${BACKUP_FILE_COMPRESS_MIN_AGE_MINUTES:-5}"

if [ "${MODE}" = "none" ] || [ -z "${MODE}" ]; then
    echo "$(date): Backup file compression disabled (BACKUP_FILE_COMPRESS=${MODE})."
    exit 0
fi

if [ ! -d "${DIR}" ]; then
    echo "$(date): Backup directory ${DIR} not mounted; skipping file compression."
    exit 0
fi

case "${MODE}" in
  zstd)
    COMPRESS_ERRORS=0
    while IFS= read -r -d '' FILE; do
        # Skip already-compressed files
        case "${FILE}" in
            *.zst|*.7z|*.gz|*.zip) continue ;;
        esac

        DEST="${FILE}.zst"

        if [ -f "${DEST}" ]; then
            echo "$(date): Skipping (already compressed): ${FILE}"
            continue
        fi

        echo "$(date): Compressing: ${FILE}"
        if [ "${DELETE_ORIGINAL}" = "Y" ] || [ "${DELETE_ORIGINAL}" = "y" ]; then
            if zstd -T0 -"${LEVEL}" --rm -q -- "${FILE}"; then
                echo "$(date): Compressed (original deleted): ${DEST}"
            else
                echo "$(date): ERROR compressing: ${FILE}" >&2
                COMPRESS_ERRORS=$((COMPRESS_ERRORS + 1))
            fi
        else
            if zstd -T0 -"${LEVEL}" --keep -q -- "${FILE}" -o "${DEST}"; then
                echo "$(date): Compressed (original kept): ${DEST}"
            else
                echo "$(date): ERROR compressing: ${FILE}" >&2
                COMPRESS_ERRORS=$((COMPRESS_ERRORS + 1))
            fi
        fi
    done < <(find "${DIR}" -type f \( -name "*.bak" -o -name "*.trn" -o -name "*.dif" \) -mmin +"${MIN_AGE}" -print0)

    if [ "${COMPRESS_ERRORS}" -gt 0 ]; then
        echo "$(date): Compression finished with ${COMPRESS_ERRORS} error(s)." >&2
        exit 1
    fi
    echo "$(date): Compression pass complete."
    ;;
  *)
    echo "$(date): Unsupported BACKUP_FILE_COMPRESS=${MODE}" >&2
    exit 1
    ;;
esac
