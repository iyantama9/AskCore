# Batch 1 Security Hardening Design

## Goal

Apply emergency production hardening for AskCore/GetAI without rotating the AI API key. The work reduces abuse risk, closes direct public service exposure, adds basic browser/API protections, and adds a simple public registration flow protected by IP-based limits.

## Scope

### In scope

- Bind the Node backend to localhost.
- Bind or firewall the local AI router so ports 4000 and 4001 are not publicly reachable.
- Enable UFW and allow only SSH, HTTP, and HTTPS publicly.
- Restrict CORS to AskCore production origins.
- Hide Express `X-Powered-By`.
- Add security headers in Nginx for web and API responses.
- Enable Fail2Ban for SSH.
- Add simple public registration without CAPTCHA.
- Rate-limit register and login to reduce account farming/password spraying.
- Stop using hardcoded seed credentials for production.

### Out of scope

- AI API key rotation.
- CAPTCHA/Turnstile.
- Full SSRF rewrite for browse.
- Full R2 file ownership migration.
- Payment/billing-grade quota system.

## Registration Design

Add `POST /api/auth/register`.

Validation:

- `username`: 3-30 characters, lowercase normalized, only letters, numbers, and underscore.
- `password`: at least 8 characters.
- Reject duplicate usernames.

Anti-abuse controls:

- Register attempts: strict per-IP limiter.
- Account creation: max 3 accounts per IP per 24 hours.
- Login: strict limiter around auth routes to reduce password spraying.
- Store `created_ip` on users when available.

The current seed script will be changed so it refuses to run unless explicitly enabled with an environment flag. This prevents accidental production seeding of known credentials.

## Backend Hardening Design

- `app.disable('x-powered-by')`.
- CORS allowlist: `https://askcore.dev`, `https://www.askcore.dev`, plus localhost only outside production if needed.
- Keep JSON body limits.
- Add separate auth limiter for login/register.
- Ensure backend listens on `127.0.0.1` by default in production.

## Nginx/Server Hardening Design

- Nginx remains the public entry point.
- Proxy `/api/` to `http://127.0.0.1:4001`.
- Add headers with `always` and ensure they apply inside static/API locations:
  - `Strict-Transport-Security`
  - `X-Frame-Options`
  - `X-Content-Type-Options`
  - `Referrer-Policy`
  - `Content-Security-Policy`
  - `Permissions-Policy`
- Enable UFW after verifying SSH remains allowed.
- UFW policy:
  - allow OpenSSH/22
  - allow 80
  - allow 443
  - deny 4000
  - deny 4001
- Enable Fail2Ban for SSH.

## Deployment/Verification

Implementation order:

1. Edit backend code and deployment config.
2. Run local/backend syntax checks where practical.
3. Deploy backend and Nginx changes.
4. Restart backend.
5. Test `https://askcore.dev` and `https://askcore.dev/api/health`.
6. Enable firewall only after confirming SSH and Nginx are OK.
7. Verify direct public ports 4000 and 4001 are no longer reachable.

## Risks and Rollback

Primary risk: firewall or binding changes could break public access if Nginx proxy target is wrong.

Rollback:

- Keep SSH allowed before enabling UFW.
- Backup Nginx config before overwriting.
- If API breaks, restore previous Nginx config and restart Nginx/backend.
- If UFW blocks needed traffic, disable UFW over SSH.
