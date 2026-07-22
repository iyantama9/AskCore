# Database Backup and Restore Runbook

Use this runbook for AskCore/GetAI PostgreSQL backups, restore drills, and migration recovery.

## Targets

- **RPO:** maximum 24 hours of data loss for scheduled backups; lower if the managed database provider offers PITR.
- **RTO:** restore service to staging within 60 minutes; production restore target depends on provider snapshot/PITR speed.
- **Backup scope:** PostgreSQL database plus R2 bucket lifecycle/export coverage for uploaded/generated files.

## Before every production migration

1. Confirm the deployment SHA and migration files to apply.
2. Take or verify a fresh provider snapshot/PITR point.
3. Export a logical backup when practical:

```bash
rtk pg_dump "$DATABASE_URL" --format=custom --file="backup-$(date +%Y%m%d-%H%M%S).dump"
```

4. Restore the backup into staging or a temporary database.
5. Run migrations in staging:

```bash
rtk npm --prefix backend run migrate
```

6. Run smoke tests against staging:

```bash
SMOKE_BASE_URL=https://staging.askcore.dev rtk npm --prefix backend run smoke
```

## Applying migrations

1. Deploy code with `RUN_MIGRATIONS_ON_START=false`.
2. Run migrations explicitly from the release host:

```bash
rtk npm --prefix backend run migrate
```

3. Confirm the applied migration list:

```sql
SELECT id, applied_at FROM schema_migrations ORDER BY id;
```

4. Restart the API and verify readiness:

```bash
rtk curl https://askcore.dev/api/health/ready
```

## Restore drill

1. Create an empty staging database.
2. Restore the latest logical backup:

```bash
rtk pg_restore --clean --if-exists --dbname "$STAGING_DATABASE_URL" latest.dump
```

3. Set the backend staging `DATABASE_URL` to the restored DB.
4. Run:

```bash
rtk npm --prefix backend run migrate
SMOKE_BASE_URL=https://staging.askcore.dev rtk npm --prefix backend run smoke
```

5. Record restore duration, backup timestamp, and any manual steps in the incident/deploy notes.

## Rollback strategy

- Prefer **forward fixes** for additive migrations.
- For destructive migrations, restore from provider PITR/snapshot into a replacement database, then point the API at the restored database.
- If only code is bad and schema is compatible, roll back the app artifact without restoring DB.

## R2/files recovery

- User uploads are private under `uploads/<userId>/`.
- Generated and browse files are public-rendered under `generated/` and `browse/`, with metadata stored in `files`.
- Keep bucket versioning/lifecycle policies enabled where available.
- During restore, verify DB `files.r2_key` entries still exist in R2 for recent uploads.

## Emergency contacts/checks

- Check API readiness: `/api/health/ready`.
- Check DB pool in readiness or `/api/metrics` as admin/internal.
- Preserve request IDs from failed user reports for log lookup.
