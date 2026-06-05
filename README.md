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
      BACKUP_COMPRESS: "Y"          # set to N for older Express editions
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
| `BACKUP_COMPRESS` | No | `Y` by default; set to `N` if the SQL Server edition does not support backup compression |
| `BACKUP_ENCRYPT_PASSWORD` | No | Enables Ola backup encryption when set; used as the encryption key password |
| `TZ` | No | Timezone for cron (default: UTC) |

Backup target directory and retention are set in `scripts/backup-full.sh` and `scripts/backup-diff.sh`:

```bash
@Directory   = '/var/opt/mssql/backup' # path inside SQL Server container
@CleanupTime = 168                      # full backup retention in hours, 168 = 7 days
@CleanupTime = 48                       # differential backup retention in hours, 48 = 2 days
```

## Backup Files

SQL Server writes backups to `/var/opt/mssql/backup/` inside the `db` container, which maps to `./mssql/backup/` on the host (assuming the standard volume mount). The maintenance container does not need access to this path.

SQL Server 2022 Express supports backup compression (`@Compress = 'Y'`). Earlier Express editions may not; set `BACKUP_COMPRESS=N` if you see compression errors.

If `BACKUP_ENCRYPT_PASSWORD` is set, the backup scripts pass Ola's `@Encrypt = 'Y'`, `@EncryptionAlgorithm = 'AES_256'`, and `@EncryptionKey` parameters.

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

## License

MIT. Ola Hallengren's Maintenance Solution has its own [license](https://ola.hallengren.com/license.html).
