# Releasing Voxema

This document describes the complete release process for Voxema.

---

## Overview

The release pipeline uses:

- **GitHub Actions** — build, sign, notarize, package, publish
- **GitHub Releases** — DMG artifact hosting
- **GitHub Pages** (`gh-pages` branch) — `appcast.xml` hosting for Sparkle auto-update
- **Sparkle 2** — in-app auto-update framework (EdDSA-signed updates)

Trigger: push a semver tag (e.g., `v0.1.0`). The workflow runs automatically.

---

## One-time Setup

### 1. Generate EdDSA key pair (Sparkle)

Run once, locally:

```bash
./scripts/generate_sparkle_keys.sh
```

You will see:
- A **public key** — copy this into `Voxema/Info.plist` as `SUPublicEDKey`
- A **private key** — store this as the `SPARKLE_PRIVATE_KEY` GitHub secret (base64-encoded)

**The private key must never be committed to git.**

### 2. Set up GitHub Pages

```bash
# Create an empty gh-pages branch
git checkout --orphan gh-pages
git rm -rf .
cp appcast.xml .
git add appcast.xml
git commit -m "chore: initial appcast"
git push origin gh-pages
git checkout main
```

Then, in GitHub repo settings → Pages:
- Source: Deploy from branch
- Branch: `gh-pages` / `/ (root)`

The appcast URL is:
```
https://voxema.pages.dev/appcast.xml
```

This URL is already set as `SUFeedURL` in `Voxema/Info.plist`.

### 3. Configure GitHub Secrets

Go to: **Settings → Secrets and variables → Actions → New repository secret**

| Secret | Required | Description |
|---|---|---|
| `SPARKLE_PRIVATE_KEY` | Yes (for signed updates) | Base64-encoded EdDSA private key from step 1 |
| `DEVELOPER_ID_APPLICATION_CERT_P12` | No (for F&F beta) | Base64-encoded Developer ID Application certificate (.p12) |
| `DEVELOPER_ID_APPLICATION_CERT_PASS` | No (for F&F beta) | Password for the .p12 |
| `KEYCHAIN_PASSWORD` | No (for F&F beta) | Any strong password for the CI temporary keychain |
| `NOTARIZE_APPLE_ID` | No (for F&F beta) | Apple ID email for notarytool |
| `NOTARIZE_TEAM_ID` | No (for F&F beta) | Apple Developer Team ID (10-char) |
| `NOTARIZE_APP_SPECIFIC_PASSWORD` | No (for F&F beta) | App-specific password from appleid.apple.com |

**For F&F beta:** Only `SPARKLE_PRIVATE_KEY` is needed. The DMG will be ad-hoc signed.
Users must right-click → Open the first time to bypass Gatekeeper.

**For public beta / production:** All secrets are required. This needs an enrolled Apple Developer Program membership ($99/year).

### 4. Developer ID certificate (for notarized builds)

1. Enroll in [Apple Developer Program](https://developer.apple.com/programs/) ($99/year)
2. In Xcode → Preferences → Accounts → Add Apple ID → your paid account
3. Manage Certificates → Create "Developer ID Application" certificate
4. Export the certificate as .p12 from Keychain Access
5. Base64-encode it: `base64 -i cert.p12 | pbcopy`
6. Paste into `DEVELOPER_ID_APPLICATION_CERT_P12` secret

---

## Local DMG (for testing)

Build a local ad-hoc DMG without CI:

```bash
./scripts/create_dmg.sh 0.1.0
# Output: dist/Voxema-0.1.0.dmg
```

---

## Releasing

```bash
# Bump version in Xcode project (or via xcodebuild)
# Then tag and push:
git tag v0.1.0
git push origin v0.1.0
```

GitHub Actions will:
1. Build and archive the app
2. Sign (Developer ID if configured, otherwise ad-hoc)
3. Notarize + staple (if `NOTARIZE_APPLE_ID` configured)
4. Package as DMG
5. Sign DMG with EdDSA (if `SPARKLE_PRIVATE_KEY` configured)
6. Create GitHub Release with DMG attached
7. Update `appcast.xml` on `gh-pages` branch

---

## Pre-release / Beta tags

Tags containing `-beta` or `-alpha` are automatically marked as pre-releases on GitHub:

```bash
git tag v0.1.0-beta.1
git push origin v0.1.0-beta.1
```

---

## Sparkle auto-update behaviour

- Voxema checks for updates at launch (~24h interval)
- Users can check manually: Voxema menu → Check for Updates…
- Updates are downloaded and installed via Sparkle's standard UI
- `SUFeedURL` in `Info.plist` points to the GitHub Pages appcast

---

## Current status

| Component | Status |
|---|---|
| Sparkle 2 in app (SPUStandardUpdaterController) | ✅ Implemented |
| `SUFeedURL` in Info.plist | ✅ Configured |
| `SUPublicEDKey` in Info.plist | ⚠️ PLACEHOLDER — run `generate_sparkle_keys.sh` |
| GitHub Actions workflow | ✅ `.github/workflows/release.yml` |
| GitHub Pages (`gh-pages` branch) | ⏳ Run setup steps above |
| DMG local script | ✅ `scripts/create_dmg.sh` |
| Developer ID certificate | ⏳ Requires paid Developer Program |
| Notarization | ⏳ Requires Developer ID + secrets |
