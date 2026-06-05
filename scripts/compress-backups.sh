#!/bin/bash
set -euo pipefail

MODE="${BACKUP_FILE_COMPRESS:-none}"
DIR="${BACKUP_HOST_DIR:-/backup}"
OUT_DIR="${BACKUP_FILE_COMPRESS_DIR:-/backup-compressed}"
LEVEL="${BACKUP_FILE_COMPRESS_LEVEL:-6}"
DELETE_ORIGINAL="${BACKUP_FILE_COMPRESS_DELETE_ORIGINAL:-N}"
MIN_AGE="${BACKUP_FILE_COMPRESS_MIN_AGE_MINUTES:-5}"

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

    echo "$(date): Compressing: ${FILE}"
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

echo "$(date): Compression pass complete."
