# Batch 3 Client/Mobile Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden Android release distribution, client token storage, markdown URL handling, and session lifetime.

**Architecture:** Keep API shape unchanged. Add secure local storage with web fallback, configure release signing through ignored key properties, tighten Android network policy, validate markdown URLs before loading/opening, and shorten backend JWT expiry.

**Tech Stack:** Flutter/Dart, Android Gradle Kotlin DSL, flutter_secure_storage, Node/Express JWT, Nginx deployment.

---

## Files

- Modify `pubspec.yaml`: add `flutter_secure_storage`.
- Modify `lib/services/api_service.dart`: secure storage with web fallback and token migration.
- Modify `lib/widgets/message_bubble.dart`: markdown link/image allowlist.
- Modify `android/app/src/main/AndroidManifest.xml`: disable cleartext.
- Modify `android/app/build.gradle.kts`: release signing from `android/key.properties`.
- Modify `.gitignore`: ignore keystore and key properties.
- Create `android/key.properties`: generated secret signing config, ignored.
- Create `android/app/askcore-release.jks`: generated release keystore, ignored.
- Modify `backend/src/routes/auth.js`: JWT expires in 24h.

## Tasks

### Task 1: Release signing

- [ ] Generate random password.
- [ ] Generate release keystore with `keytool`.
- [ ] Write `android/key.properties` with store/key passwords.
- [ ] Configure Gradle release signing to read `key.properties`.
- [ ] Ensure `.gitignore` excludes `android/key.properties` and `*.jks`.

### Task 2: Disable cleartext

- [ ] Set `android:usesCleartextTraffic="false"` in main manifest.

### Task 3: Secure token storage

- [ ] Add `flutter_secure_storage`.
- [ ] Use secure storage on non-web platforms and SharedPreferences on web.
- [ ] Migrate old mobile SharedPreferences token values into secure storage.

### Task 4: Markdown URL allowlist

- [ ] Allow images only from `askcore.dev`, `www.askcore.dev`, and `data:image/*`.
- [ ] Open links/downloads only for `http`/`https` URLs.
- [ ] Block unsafe schemes and show a safe placeholder for blocked images.

### Task 5: Short session lifetime

- [ ] Change JWT expiry from `7d` to `24h`.

### Task 6: Verify/build/deploy

- [ ] Run `flutter pub get`, backend syntax checks, and Flutter tests.
- [ ] Build web and deploy to production.
- [ ] Deploy backend auth change and restart backend.
- [ ] Build signed release APK.
- [ ] Verify APK path and production health.

## Self-review

All requested Batch 3 items are covered. The keystore/password are intentionally not committed and must be saved by the user outside the repository.
