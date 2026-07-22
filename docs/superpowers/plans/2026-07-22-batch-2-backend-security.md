# Batch 2 Backend Security Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden backend file access, browsing, error handling, login throttling, and database TLS without adding model quotas yet.

**Architecture:** Add small focused backend helpers for request IDs, safe errors, file ownership, and SSRF validation. Patch existing routes to call these helpers, preserving backward compatibility for generated/browse public assets.

**Tech Stack:** Node.js/Express, PostgreSQL, AWS S3/R2 SDK, Puppeteer, DNS/IP validation, PM2.

---

## Files

- Create `backend/src/utils/errors.js`: request ID and safe error helpers.
- Create `backend/src/utils/urlSafety.js`: SSRF URL validator.
- Create `backend/src/utils/files.js`: file metadata helpers and owner checks.
- Modify `backend/src/index.js`: request ID middleware and stricter login limiter.
- Modify `backend/src/db.js`: `files` table and verified TLS config.
- Modify `backend/src/routes/upload.js`: create metadata rows and enforce owner reads.
- Modify `backend/src/routes/files.js`: public-prefix only for unauthenticated reads.
- Modify `backend/src/routes/browse.js`: safe URL validation and isolated browser contexts.
- Modify `backend/src/routes/messages.js`: safe URL validation, isolated browser contexts, file owner checks, generic errors.

## Tasks

### Task 1: Add utilities

- [ ] Create `backend/src/utils/errors.js` with `requestIdMiddleware`, `safeError`, `sendError`.
- [ ] Create `backend/src/utils/urlSafety.js` with DNS resolution and private IP blocking.
- [ ] Create `backend/src/utils/files.js` with `recordFile`, `canReadR2Key`, `assertCanReadR2Key`.

### Task 2: Database and Express setup

- [ ] Update `backend/src/db.js` to support verified TLS and create `files` table.
- [ ] Update `backend/src/index.js` to use request ID middleware and stricter login/register route limiters.

### Task 3: File ownership

- [ ] Update upload route to record file metadata and include `id` in upload response.
- [ ] Update authenticated upload download to verify owner.
- [ ] Update public file route to only serve `generated/` and `browse/` prefixes.
- [ ] Update message attachment handling to reject private uploads from other users.

### Task 4: Browser/SSRF hardening

- [ ] Validate browse URLs before `page.goto()` in browse route and message browse helper.
- [ ] Replace shared page reuse with per-request/per-command incognito contexts.
- [ ] Close contexts after use.

### Task 5: Generic errors

- [ ] Return generic public errors with `request_id` in browse and messages routes.
- [ ] Keep detailed errors in server logs.

### Task 6: Verify and deploy

- [ ] Run backend syntax checks.
- [ ] Run Flutter tests.
- [ ] Deploy backend.
- [ ] Restart PM2 backend.
- [ ] Verify health, login/register, file access, direct ports, and SSRF block.

## Self-review

All Batch 2 requested items are covered except model allowlist/quota, which the user explicitly removed from scope.
