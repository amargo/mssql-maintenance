# mssql-maintenance

Automated SQL Server maintenance sidecar for Docker Compose environments, built on [Ola Hallengren's Maintenance Solution](https://ola.hallengren.com/).

Works with **SQL Server Express** (no SQL Agent required — scheduling is handled by Alpine cron).

## How It Works

A lightweight Alpine container runs alongside your SQL Server container. On startup it installs Ola's stored procedures into `master` (idempotent — safe to restart). Busybox cron then triggers the procedures on schedule via `sqlcmd`.

```
docker-compose
├── db  (SQL Server Express)
└── mssql-maintenance  ← this
    ├── installs Ola SPs into master on first run
    ├── runs backup / integrity / index jobs via cron
    └── writes logs to ./config/Logs/maintenance/
```

Backup files are written by SQL Server itself to `/var/opt/mssql/backup/` (i.e., the host path inside your existing SQL Server data volume). Point Syncthing, rclone, or any other sync tool at that directory for offsite replication.

## Prerequisites

- Docker + Docker Compose
- SQL Server container with a volume mounted at `/var/opt/mssql`
- `MSSQL_SA_PASSWORD` available as an env var (or `.env` file)

## Integration

This repository is the maintenance image build context. Add it to the same Compose project as your SQL Server container, either as a sibling directory or as a published image.

Example with this repository checked out as `./mssql-maintenance` next to your `docker-compose.yml`:

```yaml
services:
  db:
    image: mcr.microsoft.com/mssql/server:2022-latest
    environment:
      ACCEPT_EULA: "Y"
      MSSQL_PID: "Express"
      SA_PASSWORD: "${MSSQL_SA_PASSWORD}"
    volumes:
      - ./mssql:/var/opt/mssql
    healthcheck:
      test: ["CMD-SHELL", "sqlcmd -C -S localhost -U sa -P \"$$SA_PASSWORD\" -Q \"SELECT 1\" -b -o /dev/null"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s

  mssql-maintenance:
    build: ./mssql-maintenance
    environment:
      MSSQL_HOST: "db"
      MSSQL_SA_PASSWORD: "${MSSQL_SA_PASSWORD}"
      # BACKUP_COMPRESS: "Y"        # optional; omit if unsupported by your SQL Server edition (e.g. Express)
      TZ: "Europe/Budapest"         # adjust to your timezone
    volumes:
      - ./config/Logs/maintenance:/logs
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped
```

## Default Schedule

| Job | When | Ola SP |
|---|---|---|
| Full backup | Daily 03:00 | `DatabaseBackup` |
| Differential backup | Daily hourly from 07:00 through 17:00 | `DatabaseBackup` |
| Index optimize | Saturday 01:00 | `IndexOptimize` |
| Integrity check | Sunday 04:00 | `DatabaseIntegrityCheck` |
| CommandLog cleanup | Monday 05:00 | `DELETE CommandLog` (30 days) |

Edit `crontab` to change the schedule. Times use the container's `TZ` env var.

## Configuration

| Variable | Required | Description |
|---|---|---|
| `MSSQL_HOST` | Yes | SQL Server container name or hostname |
| `MSSQL_SA_PASSWORD` | Yes | SA password |
| `BACKUP_COMPRESS` | No | Optional Ola `@Compress` value. Leave unset if the SQL Server edition does not support backup compression (e.g. Express) |
| `BACKUP_ENCRYPT_PASSWORD` | No | Enables Ola backup encryption when set; used as the encryption key password |
| `TZ` | No | Timezone for cron (default: UTC) |
| `BACKUP_FILE_COMPRESS` | No | External post-backup compression. `zstd` or `none` (default: `none` — disabled) |
| `BACKUP_FILE_COMPRESS_LEVEL` | No | zstd compression level (default: `6`; lower is faster, higher is smaller) |
| `BACKUP_FILE_COMPRESS_DELETE_ORIGINAL` | No | Delete original `.bak` after successful compression (`Y`/`N`, default: `N` — keep originals) |
| `BACKUP_FILE_COMPRESS_MIN_AGE_MINUTES` | No | Minimum file age in minutes before compressing (default: `5`) |
| `BACKUP_HOST_DIR` | No | Path inside the maintenance container where backup files are accessible (default: `/backup`) |

Backup target directory and retention are set in `scripts/backup-full.sh` and `scripts/backup-diff.sh`:

```bash
@Directory   = '/var/opt/mssql/backup' # path inside SQL Server container
@CleanupTime = 168                      # full backup retention in hours, 168 = 7 days
@CleanupTime = 48                       # differential backup retention in hours, 48 = 2 days
```

## Backup Files

SQL Server writes backups to `/var/opt/mssql/backup/` inside the `db` container, which maps to `./mssql/backup/` on the host (assuming the standard volume mount).

**SQL Server Express** does not support the native `@Compress` backup option. The scripts omit Ola's `@Compress` parameter by default; set `BACKUP_COMPRESS=Y` only on editions where native compression is supported (Standard, Enterprise, Developer).

If `BACKUP_ENCRYPT_PASSWORD` is set, the backup scripts pass Ola's `@Encrypt = 'Y'`, `@EncryptionAlgorithm = 'AES_256'`, and `@EncryptionKey` parameters.

## Post-Backup File Compression

Because SQL Server Express cannot create compressed backups natively, the maintenance sidecar can compress completed `.bak`, `.dif`, and `.trn` files externally using `zstd` after each backup job finishes.

External compression is **disabled by default**. Enable it explicitly by setting `BACKUP_FILE_COMPRESS=zstd`.

**How it works:**

1. SQL Server writes a normal `.bak` file to `/var/opt/mssql/backup/` (inside the `db` container).
2. After `DatabaseBackup` returns successfully, `compress-backups.sh` scans `/backup` (the same host path mounted into the maintenance container) and compresses eligible files.
3. Output: `MyDatabase_FULL_20260605_030000.bak.zst` — the original extension is preserved inside the compressed filename for clarity.
4. If `BACKUP_FILE_COMPRESS_DELETE_ORIGINAL=Y`, the original `.bak` is removed after successful compression (default is `N` — originals are kept).

**Opt-in Compose example** — add to the `mssql-maintenance` service:

```yaml
environment:
  BACKUP_FILE_COMPRESS: "zstd"                  # enable external compression
  BACKUP_FILE_COMPRESS_LEVEL: "6"               # 1 (fastest) – 19 (smallest); 6 is a good balance
  BACKUP_FILE_COMPRESS_DELETE_ORIGINAL: "Y"     # remove .bak after successful .bak.zst creation
volumes:
  - ./config/Logs/maintenance:/logs
  - ./mssql/backup:/backup                      # same host path as SQL Server's /var/opt/mssql/backup
```

`./mssql/backup` on the host is the same directory as `/var/opt/mssql/backup` inside the `db` container (because SQL Server is mounted at `./mssql:/var/opt/mssql`). The `/backup` mount is **required** for compression to work; compression is silently skipped if the directory is not mounted.

**Disabling compression** (explicit):

```yaml
BACKUP_FILE_COMPRESS: "none"
```

**Restore procedure** (two steps required when originals were deleted):

```bash
# Step 1: decompress
zstd -d MyDatabase_FULL_20260605_030000.bak.zst

# Step 2: restore with SQL Server normally
# RESTORE DATABASE [MyDatabase] FROM DISK = '/path/to/MyDatabase_FULL_20260605_030000.bak'
```

**Note on job failure:** If compression fails after a successful SQL backup, the entire backup job script exits non-zero. Monitoring will report the job as failed even though the `.bak` file was written successfully. Check logs to distinguish a SQL backup failure from a post-backup compression failure.

**Note on Ola CleanupTime:** Ola's `@CleanupTime` retention only applies to original `.bak` files. Once originals are replaced by `.zst` files, retention of compressed archives must be managed separately (e.g. a cron job removing old `.zst` files). This is out of scope for the current implementation.

## Logs

All job output is appended to files under the mapped `/logs` volume:

```
./config/Logs/maintenance/
├── backup.log
├── backup-diff.log
├── index-optimize.log
├── integrity-check.log
├── cleanup.log
└── install-ola.log
```

## First Run

```bash
docker compose up -d --build mssql-maintenance
docker compose logs -f mssql-maintenance
```

On first start you should see Ola's stored procedures being installed into `master`. Subsequent restarts detect the existing SPs and skip installation.

## go-sqlcmd on Alpine

The image uses [go-sqlcmd](https://github.com/microsoft/go-sqlcmd) — a pure-Go rewrite that works on musl libc without extra packages. If you encounter dynamic linker errors, add `gcompat` to the `apk add` line in the Dockerfile.

## Updating go-sqlcmd

Change the `SQLCMD_VER` build arg:

```bash
docker compose build --build-arg SQLCMD_VER=1.9.0 mssql-maintenance
```

## Adding Jobs

1. Add a script to `scripts/` (copy an existing one as template).
2. Add a cron line to `crontab`.
3. Rebuild: `docker compose up -d --build mssql-maintenance`.

## Upgrading

### Native backup compression default removed

Previously, the backup scripts defaulted to `@Compress = 'Y'` when `BACKUP_COMPRESS` was not set. This was removed because SQL Server Express does not support native compression and would error on every backup.

**If you are running SQL Server Standard, Enterprise, or Developer** and were relying on the implicit default, you must now explicitly set:

```yaml
environment:
  BACKUP_COMPRESS: "Y"
```

Without this, backups will succeed but produce uncompressed `.bak` files (no error, just larger files).

## License

MIT. Ola Hallengren's Maintenance Solution has its own [license](https://ola.hallengren.com/license.html).
