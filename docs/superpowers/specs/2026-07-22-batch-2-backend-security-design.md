# Batch 2 Backend Security Design

## Goal

Harden AskCore backend without adding model allowlists or AI quota limits yet.

## Scope

- Login-specific rate limiter.
- File metadata table and owner checks for private uploads.
- SSRF URL validator with private IP blocking.
- Browser context isolation per browse request/command.
- Generic public errors with request IDs.
- PostgreSQL TLS verification support.

## Design

### Auth rate limits

Keep the global limiter and add route-specific auth limiters. Register remains protected by the existing account-per-IP cap. Login gets a stricter per-IP limiter to reduce password spraying.

### File ownership

Add a `files` table with `owner_id`, `r2_key`, `file_name`, `content_type`, `size`, and `visibility`. Upload creates a `private` file row. Private files can only be read by their owner. Generated images and browse screenshots use `public` visibility and can be served by `/api/files/*`.

For backward compatibility, message attachments can still pass a raw R2 key, but the backend must validate ownership for `uploads/<userId>/...` and must reject another user's upload key. Public `generated/` and `browse/` keys remain readable.

### SSRF protection

Add a URL safety helper that accepts only HTTP/HTTPS URLs, resolves hostnames, and rejects localhost, loopback, link-local, private IPv4 ranges, and local/private IPv6. Browse commands must validate before `page.goto()`.

### Browser isolation

Keep a reusable browser process for performance, but create a fresh incognito/browser context and page for each browse execution. Close the context after extracting screenshot/text. This prevents cookies/storage/page state from crossing users.

### Generic errors and request IDs

Add request ID middleware. Error responses expose a safe message and `request_id`; detailed errors remain in server logs.

### PostgreSQL TLS verification

Support verified TLS by default. Use `DATABASE_SSL_REJECT_UNAUTHORIZED=false` only as an explicit fallback if the database provider requires it temporarily. Support optional `DATABASE_SSL_CA` for CA bundles.

## Verification

- Backend syntax checks pass.
- Flutter tests still pass.
- Production health endpoint stays 200.
- Login/register still work.
- Public generated/browse files still load.
- Private upload keys from other users are rejected.
- Direct internal/private browse URLs are rejected with generic error.
