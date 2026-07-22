# Production Smoke Tests

Use this checklist after every deploy or rollback.

## Automated smoke script

Run from the repository root:

```bash
rtk npm --prefix backend run smoke
```

By default this targets `https://askcore.dev`. Override with:

```bash
SMOKE_BASE_URL=https://staging.askcore.dev rtk npm --prefix backend run smoke
```

For authenticated chat checks, provide a dedicated smoke user:

```bash
SMOKE_USERNAME=smoke_user SMOKE_PASSWORD='replace-me' rtk npm --prefix backend run smoke
```

The script checks:

- `/api/health/live`
- `/api/health/ready`
- unauthenticated `/api/chats` rejection
- browse auth guard
- optional login/create-chat/send-message/delete-chat flow

## Manual launch gate

Before broader release, also verify manually:

1. Web loads at `https://askcore.dev/`.
2. Login succeeds on web and Android.
3. Create a new chat.
4. Send a normal streaming prompt.
5. Send an image/file attachment.
6. Try a browse request for a public URL.
7. Confirm private/local browse targets are blocked safely.
8. Confirm generated/request errors include an `X-Request-ID` response header.
9. Confirm PM2 process is online and Nginx is active.
10. Confirm rollback artifact from the previous release is available.

## Expected failure handling

If any smoke step fails:

1. Stop rollout.
2. Capture the request ID and deployment SHA.
3. Check PM2 logs for the request ID.
4. Roll back to the previous artifact if production user impact is visible.
5. File a regression test before fixing.
