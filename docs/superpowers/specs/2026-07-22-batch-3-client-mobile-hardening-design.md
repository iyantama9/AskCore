# Batch 3 Client/Mobile Hardening Design

## Goal

Harden AskCore client/mobile security and reduce token exposure risk while keeping user experience practical.

## Scope

- Generate Android release keystore with random password.
- Store signing credentials in ignored `android/key.properties`.
- Configure Android release signing.
- Disable cleartext traffic for main/release app.
- Use secure storage for mobile tokens with SharedPreferences fallback for web.
- Allowlist markdown images/links.
- Shorten JWT/session lifetime to 24 hours.
- Build/deploy web and generate signed APK.

## Design

### Release signing

Generate `android/app/askcore-release.jks` and `android/key.properties`. The password will be generated randomly and shown once to the user. `android/key.properties` and keystore files must be gitignored.

### Cleartext traffic

Set `android:usesCleartextTraffic="false"` in main manifest. If local HTTP dev is needed later, debug-only manifest/network config can override it.

### Token storage

Add `flutter_secure_storage`. On mobile/desktop, store token, username, and user id in secure storage. On web, continue using SharedPreferences because web secure storage still relies on browser storage. `loadToken()` migrates old mobile SharedPreferences values into secure storage then removes old values.

### Markdown allowlist

Images embedded by model output are allowed only from trusted hosts (`askcore.dev`, `www.askcore.dev`) or safe `data:image/*` URIs. External link/download opens only `http`/`https` URLs; unsafe schemes are blocked.

### Session lifetime

Change backend JWT expiry from 7 days to 24 hours. Expired sessions require re-login.

## Verification

- Flutter analyze/test/build APK.
- Backend syntax checks.
- Web build/deploy still works.
- Signed APK exists.
- Login/register still work.
- Markdown unsafe links/images are blocked in client code.
