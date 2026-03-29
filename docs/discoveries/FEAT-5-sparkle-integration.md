# Discovery — FEAT-5: Sparkle Framework Integration

**Date:** 2026-03-29
**Mode:** Technical Discovery + Market References
**Status:** produced

---

## Discovery Question

How should Voxema integrate the Sparkle framework for auto-updates in a DMG-distributed macOS app? This covers: framework version and integration method, update feed hosting, code signing and notarization, delta updates, update UX, release pipeline, model update strategy, and interaction with Lemon Squeezy (DEC-1).

## Prior Decisions

- **DEC-1:** Lemon Squeezy for billing — direct DMG distribution, no App Store at MVP. JWT-based offline license validation.
- **DEC-2:** Hybrid model packaging — DMG ~150–180MB. Models stored in `~/Library/Application Support/Voxema/Models/`. `models-manifest.json` shipped with app, "updated via Sparkle alongside the app."
- **DEC-3:** Backend on Railway (TypeScript/Hono) — post-MVP only.

## Context

Voxema distributes via DMG (no App Store at MVP). Without a built-in update mechanism, users on outdated versions miss critical fixes, model manifest updates, and security patches. The PRD explicitly calls out Sparkle as the preferred auto-update framework. ARCHITECTURE.md has an `UpdateManager` slot awaiting this Discovery.

The app is ~150–180MB (bundled Whisper tiny + ECAPA-TDNN). Updates will often change only app code (~15–30MB of Swift binaries) while bundled models remain unchanged, making delta updates potentially valuable.

---

## Market & Competitive Research

### Reference 1 — Raycast

- **What they do:** Launcher/productivity app for macOS, distributed outside App Store
- **UX approach:** Initially used Sparkle, then built a custom update engine. Update appears as a top-level command in the app rather than a modal dialog. Background download, one-keystroke install, release notes shown after relaunch. Users moved to new versions within 24 hours.
- **Strengths:** Non-intrusive UX, inline release notes, background download without user prompt (app is small ~10MB), server-side rollout control
- **Weaknesses:** Custom solution = significant engineering investment, not viable for a solo developer at MVP
- **Key insight:** Raycast's custom engine uses GitHub Releases for binary hosting + a simple API middleware for version comparison. This validates GitHub Releases as a viable hosting strategy.
- **URL:** https://medium.com/raycastapp/how-we-built-an-app-update-flow-our-users-love-89820602e8fe

### Reference 2 — MacWhisper

- **What they do:** Local Whisper-based transcription app for macOS — closest competitor to Voxema's transcription pipeline
- **UX approach:** Distributed via DMG, uses Sparkle for auto-updates with standard Sparkle update dialog
- **Strengths:** Standard Sparkle integration = minimal maintenance, users familiar with the UI pattern
- **Weaknesses:** Standard Sparkle UI is functional but not distinctive
- **Key insight:** A direct competitor with a similar DMG size (~200MB+ with models) successfully uses standard Sparkle. Validates the approach for apps of Voxema's size class.

### Reference 3 — iTerm2

- **What they do:** Terminal emulator for macOS, one of the most popular non-App Store macOS apps
- **UX approach:** Uses Sparkle with standard UI. Appcast hosted on the project website. Supports beta channel via separate appcast feed. Background checks with user notification.
- **Strengths:** Proven at massive scale, beta channel support, simple hosting
- **Weaknesses:** No custom UI innovation — standard Sparkle dialogs
- **Key insight:** Long-running proof that Sparkle scales and is maintainable for years. Beta channel via separate feed URL is a proven pattern.

### Reference 4 — Sindre Sorhus's Apps (Dato, Gifski, etc.)

- **What they do:** Prolific indie macOS developer shipping dozens of apps outside the App Store
- **UX approach:** Uses Sparkle via SPM. Created `appcast-workflow` — a reusable GitHub Actions workflow that generates Sparkle appcast.xml automatically from GitHub Releases. Hosts appcast on GitHub Pages.
- **Strengths:** Fully automated CI/CD pipeline, zero hosting cost, open-source workflow reusable by others
- **Weaknesses:** Tied to GitHub ecosystem
- **Key insight:** `appcast-workflow` (https://github.com/sindresorhus/appcast-workflow) is a production-validated, open-source GitHub Actions workflow for Sparkle appcast generation. Directly reusable by Voxema.
- **URL:** https://github.com/sindresorhus/appcast-workflow

### Patterns Observed

1. **Sparkle is the de facto standard** for non-App Store macOS apps. Only teams with significant engineering resources (Raycast) build custom solutions.
2. **GitHub Releases + GitHub Pages** is the most common hosting pattern for indie developers — free, version-controlled, CDN-backed.
3. **Standard Sparkle UI is acceptable** for most apps. Custom update UX is a post-MVP optimization.
4. **Background check + user notification** is the universal pattern. Silent auto-install is rare outside power-user tools.
5. **Beta channels** via separate appcast feeds are common for apps with active development cycles.

---

## Area 1: Sparkle Version and Integration Method

### Options Considered

1. **Sparkle 2 via Swift Package Manager (SPM)**
2. **Sparkle 2 via Carthage**
3. **Sparkle 2 via manual framework embedding**
4. ~~Sparkle 1~~ (eliminated: legacy, no EdDSA, no sandbox support, deprecated)

### Comparison

#### Option 1 — Sparkle 2 via SPM

- **Pros:** Native Xcode integration, version pinning via `Package.swift`, no extra tooling, consistent with Swift ecosystem conventions, Sparkle officially supports SPM since 2.x
- **Cons:** SPM distributes Sparkle as a binary XCFramework (not source) — tools like `generate_keys` and `sign_update` require manual discovery in the SPM artifacts directory
- **Dependency friendliness:** Excellent — SPM is the standard Swift dependency manager
- **Implementation simplicity:** High — `File > Add Package Dependencies` in Xcode, add URL `https://github.com/sparkle-project/Sparkle`, pin to 2.x
- **Operational simplicity:** High
- **Value-to-complexity:** High
- **Reversibility:** Easy — remove SPM dependency
- **Pipeline fit:** Fits cleanly — no pipeline stage affected
- **MVP fit:** Excellent
- **Long-term fit:** Excellent

#### Option 2 — Sparkle 2 via Carthage

- **Pros:** Source-level access, mature tooling
- **Cons:** Extra dependency (Carthage itself), additional build step, less common in modern Swift projects, Carthage maintenance has slowed
- **Dependency friendliness:** Medium — requires Carthage binary
- **Implementation simplicity:** Medium
- **Operational simplicity:** Medium
- **Value-to-complexity:** Medium
- **Reversibility:** Easy
- **Pipeline fit:** Fits cleanly
- **MVP fit:** Acceptable but unnecessary
- **Long-term fit:** Declining (Carthage losing adoption)

#### Option 3 — Sparkle 2 via manual embedding

- **Pros:** Full control, no dependency manager
- **Cons:** Manual version updates, error-prone framework embedding, no automatic dependency resolution
- **Dependency friendliness:** Low — manual management
- **Implementation simplicity:** Low
- **Operational simplicity:** Low
- **Value-to-complexity:** Low
- **Reversibility:** Easy
- **Pipeline fit:** Fits cleanly
- **MVP fit:** Acceptable but unnecessary friction
- **Long-term fit:** Poor (maintenance burden)

### Decision Quality Score — Area 1

| Criterion | SPM (Option 1) | Carthage (Option 2) | Manual (Option 3) |
|---|---|---|---|
| MVP fit | 5 | 3 | 3 |
| Architecture fit | 5 | 4 | 4 |
| Implementation simplicity | 5 | 3 | 2 |
| Reversibility | 5 | 5 | 5 |
| Dependency friendliness | 5 | 3 | 2 |
| Operational simplicity | 5 | 3 | 2 |
| Testability | 4 | 4 | 4 |
| Long-term fit | 5 | 2 | 2 |
| **Total** | **39/40** | **27/40** | **24/40** |

### Recommendation — Area 1

**Sparkle 2 via SPM.** It is the clearly simplest viable choice. Official support, native Xcode integration, zero additional tooling.

**SwiftUI-specific considerations:**
- Initialize `SPUStandardUpdaterController` in the `@main` App struct with `startingUpdater: true`
- Add "Check for Updates…" menu item via SwiftUI `CommandGroup(after: .appInfo)`
- Sparkle's standard UI works with SwiftUI apps — no special adaptation needed
- Hardened Runtime is compatible — required for notarization anyway

**Decision stability:** Stable

---

## Area 2: Update Feed (Appcast) Hosting

### Options Considered

1. **GitHub Releases + GitHub Pages (appcast on Pages, DMGs on Releases)**
2. **Cloudflare R2 / S3 bucket**
3. **Railway backend (same as DEC-3)**
4. ~~Lemon Squeezy~~ (eliminated: no appcast support, file hosting is for product delivery not update feeds)

### Comparison

#### Option 1 — GitHub Releases + GitHub Pages

- **Pros:** Free, CDN-backed (GitHub Pages uses Fastly CDN), version-controlled appcast, proven pattern (Sindre Sorhus apps, iTerm2-like workflows), `appcast-workflow` GitHub Action available off-the-shelf, DMGs attached to releases with automatic download URLs, release notes in GitHub markdown format
- **Cons:** GitHub Pages has soft bandwidth limits (100GB/month — sufficient for thousands of users), public appcast (acceptable — contains no secrets), tied to GitHub ecosystem
- **Dependency friendliness:** Excellent — GitHub is already the code host
- **Implementation simplicity:** High — use `sindresorhus/appcast-workflow` or `generate_appcast`
- **Operational simplicity:** High — push tag → CI builds → release created → appcast auto-generated
- **Value-to-complexity:** High
- **Reversibility:** Easy — appcast URL in Info.plist can be changed to any HTTPS endpoint
- **Pipeline fit:** Fits cleanly — no pipeline stage affected
- **MVP fit:** Excellent — zero cost, zero infrastructure
- **Long-term fit:** Good for indie scale. If bandwidth becomes an issue at >10K users, migrate DMG hosting to R2/S3 while keeping appcast on Pages.

#### Option 2 — Cloudflare R2 / S3

- **Pros:** No bandwidth limits (R2 has zero egress fees), full control over hosting, CDN-native
- **Cons:** Requires bucket setup, IAM/API key management, CI pipeline to upload, monthly cost (minimal but nonzero), operational overhead for solo dev
- **Dependency friendliness:** Medium — new infrastructure dependency
- **Implementation simplicity:** Medium — bucket setup, upload scripts, CDN config
- **Operational simplicity:** Medium
- **Value-to-complexity:** Medium
- **Reversibility:** Easy
- **Pipeline fit:** Fits cleanly
- **MVP fit:** Overkill for MVP
- **Long-term fit:** Excellent at scale

#### Option 3 — Railway backend

- **Pros:** Consolidates infrastructure (DEC-3), could serve appcast dynamically (license-gated updates in future)
- **Cons:** Backend is post-MVP — would need to exist before it's planned, adds dependency on backend availability for updates, backend downtime blocks update checks
- **Dependency friendliness:** Poor — creates MVP dependency on post-MVP infrastructure
- **Implementation simplicity:** Low (for MVP)
- **Operational simplicity:** Low — backend must be running for updates to work
- **Value-to-complexity:** Low
- **Reversibility:** Easy — change appcast URL
- **Pipeline fit:** Conflicts — creates cross-dependency between app updates and backend availability
- **MVP fit:** Not viable — backend doesn't exist at MVP
- **Long-term fit:** Possible post-MVP for license-gated updates

### Appcast Format

The appcast is an RSS 2.0 XML file with Sparkle-specific namespace extensions:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Voxema Changelog</title>
    <language>en</language>
    <item>
      <title>Version 1.0.1</title>
      <sparkle:version>2</sparkle:version>
      <sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
      <sparkle:releaseNotesLink>
        https://your-pages-site.github.io/release-notes/1.0.1.html
      </sparkle:releaseNotesLink>
      <pubDate>Mon, 29 Mar 2026 12:00:00 +0000</pubDate>
      <enclosure
        url="https://github.com/user/repo/releases/download/v1.0.1/Voxema.dmg"
        sparkle:edSignature="..."
        length="157286400"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
```

Key fields for Voxema:
- `sparkle:minimumSystemVersion` → `13.0` (macOS Ventura, per PRD)
- `sparkle:hardwareRequirements` → `arm64` (Apple Silicon only, per PRD)
- `sparkle:criticalUpdate` → for security patches that override "skip this version"
- `sparkle:channel` → `beta` for future beta channel support

### Appcast Generation

Sparkle includes a `generate_appcast` CLI tool that:
1. Scans a directory of DMG/ZIP files
2. Reads version info from each app bundle's `Info.plist`
3. Signs each archive with the EdDSA private key
4. Generates (or updates) the `appcast.xml`

For CI/CD, use `sindresorhus/appcast-workflow` (GitHub Actions) which automates this from GitHub Releases.

### Decision Quality Score — Area 2

| Criterion | GitHub (Option 1) | R2/S3 (Option 2) | Railway (Option 3) |
|---|---|---|---|
| MVP fit | 5 | 3 | 1 |
| Architecture fit | 5 | 4 | 2 |
| Implementation simplicity | 5 | 3 | 2 |
| Reversibility | 5 | 5 | 5 |
| Dependency friendliness | 5 | 3 | 2 |
| Operational simplicity | 5 | 3 | 2 |
| Testability | 4 | 4 | 3 |
| Long-term fit | 4 | 5 | 3 |
| **Total** | **38/40** | **30/40** | **20/40** |

### Recommendation — Area 2

**GitHub Releases (DMG hosting) + GitHub Pages (appcast hosting).** Zero cost, zero infrastructure, proven pattern, off-the-shelf GitHub Actions workflow. Migrate DMG hosting to R2/S3 only if bandwidth becomes a constraint at scale (>10K active users).

**Decision stability:** Stable (hosting can be migrated by changing `SUFeedURL` in a future app update)

---

## Area 3: Code Signing & Notarization

This area is not a choice between options — it is a set of mandatory requirements that must all be satisfied. All items below are required for DMG distribution outside the App Store.

### Requirements

#### Apple Developer ID Certificate
- **Developer ID Application** certificate — required to code-sign the `.app` bundle
- **Developer ID Installer** certificate — optional, only needed if distributing `.pkg` installers (not needed for DMG)
- Both obtained from Apple Developer Program ($99/year) — prerequisite for any macOS distribution outside the App Store

#### Notarization
- Apple requires all software distributed outside the App Store to be notarized (since macOS 10.15 Catalina)
- Notarization workflow: Build → Sign with Developer ID → Submit to Apple's notarization service → Staple the notarization ticket to the DMG
- Requires Apple ID + app-specific password (or API key) for `notarytool`
- Compatible with Hardened Runtime (already required by Sparkle and notarization)

#### Hardened Runtime
- Required for notarization
- Sparkle 2 is fully compatible with Hardened Runtime
- Entitlements needed for Voxema (regardless of Sparkle): `com.apple.security.device.audio-input` (microphone), `com.apple.security.temporary-exception.mach-lookup.global-name` (ScreenCaptureKit)
- No additional entitlements needed specifically for Sparkle (when not using App Sandbox)

#### EdDSA Signatures (Sparkle-specific)
- Sparkle 2 uses EdDSA (Ed25519) for update verification — this is independent of Apple code signing
- Generate key pair via `generate_keys` tool (shipped with Sparkle)
- Public key embedded in `Info.plist` as `SUPublicEDKey`
- Private key stored in macOS Keychain (development) or as CI secret (CI/CD)
- Sparkle verifies both EdDSA signature AND Apple code signature on updates (belt and suspenders)

#### Dual Verification Flow
1. User's app downloads the update DMG
2. Sparkle verifies the EdDSA signature against `SUPublicEDKey` in the running app's bundle
3. Sparkle verifies the new `.app` bundle's Apple code signature matches the running app's Team ID
4. On macOS 14.4+, Sparkle also performs a Gatekeeper scan to prevent verification dialogs on relaunch
5. Only if both checks pass does Sparkle proceed with installation

#### Key Management

| Key | Storage (Dev) | Storage (CI) | Rotation |
|---|---|---|---|
| EdDSA private key | macOS Keychain | GitHub Secret (`SPARKLE_PRIVATE_KEY`) | Requires new app release with updated `SUPublicEDKey` — avoid rotation |
| Developer ID cert (.p12) | macOS Keychain | GitHub Secret (base64-encoded) | Standard Apple renewal cycle (5 years) |
| Apple ID / notarytool credentials | macOS Keychain | GitHub Secret | App-specific password, rotate as needed |

### Risks
- **EdDSA key loss** = cannot ship updates that existing users will accept. Mitigation: backup the private key securely (e.g., encrypted in a password manager, never stored unencrypted outside Keychain).
- **Developer ID cert expiration** = app won't pass Gatekeeper. Mitigation: set calendar reminder for renewal.

### Recommendation — Area 3

No option to choose — all components are mandatory. Implementation is straightforward and well-documented. The only decision is key backup strategy: store the EdDSA private key backup in a password manager (1Password/Bitwarden) as an encrypted note.

**Decision stability:** Stable (these are Apple platform requirements, not changeable)

---

## Area 4: Delta Updates

### Options Considered

1. **Enable delta updates at MVP**
2. **Defer delta updates to post-MVP**

### Comparison

#### Option 1 — Enable delta updates at MVP

- **Pros:** Significant bandwidth savings — Voxema's DMG is ~150–180MB but most updates only change Swift binaries (~15–30MB), so deltas could be ~10–30MB. Better user experience (faster downloads). Sparkle 2.1+ has improved v3 delta format that handles large apps well.
- **Cons:** `generate_appcast` needs access to previous release DMGs to compute deltas — adds CI/CD complexity. Must store N previous DMGs for delta generation. Slightly more complex release pipeline. If delta application fails, Sparkle falls back to full download automatically.
- **Dependency friendliness:** No new dependencies — Sparkle includes `BinaryDelta` tool
- **Implementation simplicity:** Medium — CI must persist previous DMGs and pass them to `generate_appcast`
- **Operational simplicity:** Medium
- **Value-to-complexity:** High — for a 150MB+ app, delta = ~80% bandwidth reduction per update
- **Reversibility:** Easy — stop generating deltas, full updates still work
- **Pipeline fit:** Fits cleanly — affects only the release pipeline, not the app pipeline
- **MVP fit:** Acceptable — adds CI complexity but meaningful user benefit
- **Long-term fit:** Excellent

#### Option 2 — Defer delta updates to post-MVP

- **Pros:** Simpler CI pipeline at MVP. Full update download is still functional. Focus MVP engineering on core pipeline, not release optimization.
- **Cons:** Users download ~150MB on every update. Poor experience on slow connections. Higher bandwidth usage from day one.
- **Dependency friendliness:** N/A
- **Implementation simplicity:** High (nothing to implement)
- **Operational simplicity:** High
- **Value-to-complexity:** N/A
- **Reversibility:** N/A (can add later)
- **Pipeline fit:** N/A
- **MVP fit:** Simpler
- **Long-term fit:** Must be added eventually

### Decision Quality Score — Area 4

| Criterion | MVP deltas (Option 1) | Defer deltas (Option 2) |
|---|---|---|
| MVP fit | 3 | 5 |
| Architecture fit | 5 | 5 |
| Implementation simplicity | 3 | 5 |
| Reversibility | 5 | 5 |
| Dependency friendliness | 5 | 5 |
| Operational simplicity | 3 | 5 |
| Testability | 3 | 5 |
| Long-term fit | 5 | 3 |
| **Total** | **32/40** | **38/40** |

### Recommendation — Area 4

**Defer delta updates to post-MVP.** The MVP release pipeline should be as simple as possible. Full DMG downloads (~150–180MB) are acceptable for early users. Add delta updates as a fast follow when the release pipeline is proven and stable.

**Why this is simplest viable:** Delta generation requires CI to persist and manage previous DMGs. At MVP, a simple "build → sign → notarize → upload" pipeline is sufficient. Delta support adds nothing to core product value.

**Decision stability:** Temporary — revisit after 3–5 releases when the pipeline is stable.

---

## Area 5: Update UX Patterns

### Options Considered

1. **Sparkle standard UI (built-in)**
2. **Custom SwiftUI update UI**
3. **Hybrid: Sparkle standard UI at MVP, custom post-MVP**

### Comparison

#### Option 1 — Sparkle standard UI

- **Pros:** Zero implementation — Sparkle provides a complete, localized, accessible update dialog. Includes: update available notification, release notes display, download progress, install prompt, "Skip This Version" and "Remind Me Later" buttons. Familiar to macOS users.
- **Cons:** Generic appearance — doesn't match Voxema's brand. Can't deeply integrate updates into the app's navigation flow (like Raycast does).
- **Implementation simplicity:** Highest — `SPUStandardUpdaterController` handles everything
- **Operational simplicity:** High
- **Value-to-complexity:** High
- **Reversibility:** Easy — replace with custom `SPUUserDriver` later
- **MVP fit:** Excellent
- **Long-term fit:** Acceptable (functional but not distinctive)

#### Option 2 — Custom SwiftUI update UI

- **Pros:** Brand-consistent design, can integrate into app navigation (like Raycast), full control over UX
- **Cons:** Significant implementation effort — must implement `SPUUserDriver` protocol. Must handle all states: checking, downloading, extracting, installing, error, restart. Must implement release notes rendering. Must maintain feature parity with Sparkle's built-in UI (accessibility, localization).
- **Implementation simplicity:** Low
- **Operational simplicity:** Medium (custom code to maintain)
- **Value-to-complexity:** Low at MVP
- **Reversibility:** Easy (revert to standard UI)
- **MVP fit:** Over-engineered for MVP
- **Long-term fit:** Good (differentiation opportunity)

#### Option 3 — Hybrid approach

- **Pros:** Ship fast with standard UI, iterate post-MVP when UX patterns are validated
- **Cons:** Two UX transitions for users (standard → custom)
- **Implementation simplicity:** High at MVP
- **Operational simplicity:** High
- **Value-to-complexity:** High
- **Reversibility:** N/A (progressive refinement)
- **MVP fit:** Excellent
- **Long-term fit:** Excellent

### Update Check Behavior

Regardless of UI choice, the update check behavior should be:

| Setting | Value | Rationale |
|---|---|---|
| Automatic update checks | Enabled by default | Users should get updates without manual action |
| Check interval | Default (Sparkle default: every 24 hours) | Balanced — not too aggressive, not too infrequent |
| Minimum check interval | 1 hour (Sparkle-enforced) | Cannot go lower |
| Background download | Enabled | Download silently, prompt only for install |
| "Skip This Version" | Enabled (Sparkle default) | Respects user choice |
| Critical update override | Use `sparkle:criticalUpdate` tag | Security patches bypass "Skip This Version" |
| Network dependency | Check `NetworkManager` before update check | Don't attempt update checks offline |
| First launch prompt | Sparkle asks user on first launch if they want automatic checks | Standard Sparkle behavior, GDPR-friendly |

### Mandatory Updates (Security Patches)

Sparkle supports critical updates via the `<sparkle:criticalUpdate>` tag in the appcast:
- When present, the update cannot be skipped by the user
- The update dialog shows "Install Update" without a "Skip" option
- Can be version-targeted: `<sparkle:criticalUpdate sparkle:version="1.0.2">` means "critical only for users on version ≤ 1.0.2"

For Voxema: use `criticalUpdate` sparingly — only for security vulnerabilities or data-loss bugs.

### Decision Quality Score — Area 5

| Criterion | Standard UI (Opt 1) | Custom UI (Opt 2) | Hybrid (Opt 3) |
|---|---|---|---|
| MVP fit | 5 | 1 | 5 |
| Architecture fit | 5 | 5 | 5 |
| Implementation simplicity | 5 | 1 | 5 |
| Reversibility | 5 | 5 | 5 |
| Dependency friendliness | 5 | 4 | 5 |
| Operational simplicity | 5 | 3 | 5 |
| Testability | 4 | 3 | 4 |
| Long-term fit | 3 | 5 | 5 |
| **Total** | **37/40** | **27/40** | **39/40** |

### Recommendation — Area 5

**Hybrid: Sparkle standard UI at MVP, custom SwiftUI UI post-MVP.** The standard UI is complete, localized, accessible, and familiar to macOS users. It is the simplest viable choice for MVP. Custom UI is a post-MVP refinement opportunity.

**Decision stability:** Standard UI at MVP: stable. Custom UI post-MVP: optional.

---

## Area 6: Release Pipeline

### End-to-End Release Flow

```
Developer pushes tag (e.g., v1.0.1)
       │
       ▼
┌─────────────────────────────────────┐
│      GitHub Actions CI/CD            │
│                                      │
│  1. Build (xcodebuild archive)       │
│  2. Sign (Developer ID Application)  │
│  3. Create DMG (create-dmg or hdiutil)│
│  4. Notarize (notarytool submit)     │
│  5. Staple (stapler staple)          │
│  6. Sign DMG with EdDSA (sign_update)│
│  7. Create GitHub Release            │
│  8. Upload DMG to Release            │
│  9. Generate appcast.xml             │
│ 10. Push appcast to GitHub Pages     │
└─────────────────────────────────────┘
       │
       ▼
Users receive update notification
```

### GitHub Actions Workflow

**Trigger:** Push tag matching `v*` (e.g., `v1.0.1`)

**Required secrets:**

| Secret | Purpose |
|---|---|
| `DEVELOPER_ID_APPLICATION_CERT` | Base64-encoded .p12 of Developer ID Application certificate |
| `DEVELOPER_ID_APPLICATION_PASSWORD` | Password for the .p12 file |
| `APPLE_ID` | Apple ID for notarization |
| `APPLE_ID_PASSWORD` | App-specific password for notarization |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key for Sparkle signing |
| `PAGES_DEPLOY_KEY` | SSH deploy key for pushing to GitHub Pages repo |

**Workflow steps (high-level):**

1. **Checkout** code at tag
2. **Install certificates** — decode and import Developer ID cert into temporary keychain
3. **Resolve dependencies** — `xcodebuild -resolvePackageDependencies`
4. **Build & archive** — `xcodebuild archive` with `CODE_SIGN_IDENTITY="Developer ID Application"`
5. **Export** — `xcodebuild -exportArchive`
6. **Create DMG** — use `create-dmg` (npm tool) or `hdiutil` for a branded installer DMG
7. **Notarize** — `xcrun notarytool submit Voxema.dmg --apple-id ... --wait`
8. **Staple** — `xcrun stapler staple Voxema.dmg`
9. **Create GitHub Release** — `gh release create v$VERSION --draft --generate-notes`
10. **Upload DMG** — `gh release upload v$VERSION Voxema.dmg`
11. **Generate appcast** — run `generate_appcast` or use `sindresorhus/appcast-workflow`
12. **Publish release** — `gh release edit v$VERSION --draft=false`

### Versioning Scheme

| Field | Convention | Example |
|---|---|---|
| `CFBundleShortVersionString` | Semver (user-facing) | `1.2.3` |
| `CFBundleVersion` | Monotonically increasing integer (build number) | `42` |
| Sparkle `sparkle:shortVersionString` | Maps to `CFBundleShortVersionString` | `1.2.3` |
| Sparkle `sparkle:version` | Maps to `CFBundleVersion` | `42` |
| Git tag | `v` + semver | `v1.2.3` |

Sparkle uses `CFBundleVersion` (build number) for version comparison by default. Semver is for user display. Both must be set correctly.

### Recommendation — Area 6

Use GitHub Actions with tag-triggered releases. The pipeline is: build → sign → create DMG → notarize → staple → EdDSA-sign → GitHub Release → generate appcast → publish to Pages. Use `sindresorhus/appcast-workflow` for appcast generation where possible; fall back to manual `generate_appcast` if customization is needed.

**Decision stability:** Stable (GitHub Actions is the standard CI for GitHub-hosted projects)

---

## Area 7: Model Updates

### Context

Per DEC-2:
- Bundled models (Whisper tiny, ECAPA-TDNN) ship in the DMG
- Downloaded models live in `~/Library/Application Support/Voxema/Models/`
- `models-manifest.json` defines the curated model catalog with SHA-256 checksums
- DEC-2 states: "models-manifest.json updated via Sparkle alongside the app"

### Options Considered

1. **Model manifest updated only via app updates (Sparkle)**
2. **Independent model update mechanism (separate from Sparkle)**

### Comparison

#### Option 1 — Manifest updates via Sparkle only

- **Pros:** Simplest approach — manifest changes ship with app releases. No additional update infrastructure. Manifest version always matches app version (no compatibility mismatches). SHA-256 checksums verified by the app version that ships them.
- **Cons:** Adding a new model to the catalog requires an app release. Users on old app versions don't get new model options until they update the app.
- **Dependency friendliness:** No new dependencies
- **Implementation simplicity:** High — manifest is a bundled resource, updated via Sparkle like any other app resource
- **Operational simplicity:** High
- **Value-to-complexity:** High
- **Reversibility:** Easy
- **Pipeline fit:** Fits cleanly
- **MVP fit:** Excellent
- **Long-term fit:** Good for MVP/early stage. May need independent mechanism if model catalog changes frequently without app code changes.

#### Option 2 — Independent model update mechanism

- **Pros:** Model catalog can be updated independently of app releases. New models available without requiring app update.
- **Cons:** Requires a remote manifest endpoint (backend or static hosting). Requires manifest versioning and compatibility checking. Introduces a new update vector (security surface). Could lead to manifest-app version mismatches. Adds complexity for unclear MVP benefit.
- **Dependency friendliness:** Adds network dependency for model discovery
- **Implementation simplicity:** Medium
- **Operational simplicity:** Medium
- **Value-to-complexity:** Low at MVP
- **Reversibility:** Easy
- **Pipeline fit:** Requires adaptation — new update channel for manifest
- **MVP fit:** Over-engineered
- **Long-term fit:** Good if model catalog changes frequently

### Decision Quality Score — Area 7

| Criterion | Via Sparkle (Option 1) | Independent (Option 2) |
|---|---|---|
| MVP fit | 5 | 2 |
| Architecture fit | 5 | 4 |
| Implementation simplicity | 5 | 3 |
| Reversibility | 5 | 5 |
| Dependency friendliness | 5 | 3 |
| Operational simplicity | 5 | 3 |
| Testability | 4 | 3 |
| Long-term fit | 4 | 4 |
| **Total** | **38/40** | **27/40** |

### Recommendation — Area 7

**Model manifest updated only via Sparkle at MVP.** This is consistent with DEC-2 and the simplest approach. The model catalog changes infrequently (DEC-2: "curated list will expand as models are benchmarked"). Each app release ships a manifest compatible with that version's `ModelManager` code.

Post-MVP consideration: If model catalog needs to change between app releases (e.g., model deprecation, urgent model swap), introduce a lightweight remote manifest check that downloads an updated `models-manifest.json` from a static URL (GitHub Pages or R2). This would complement, not replace, the Sparkle-bundled manifest.

**Decision stability:** Stable for MVP. Revisit post-MVP if model catalog cadence exceeds app release cadence.

---

## Area 8: Interaction with Lemon Squeezy (DEC-1)

### Context

Per DEC-1:
- Lemon Squeezy is the merchant of record for Pro tier
- JWT-based license validation with offline support
- No monetization code at MVP — Free tier ships alone
- Pro tier (post-MVP) adds managed cloud LLM summarization

### Analysis

- **Updates are not gated by license at MVP.** All users (Free tier) receive the same updates via Sparkle. There is no Pro-exclusive app binary — Pro features are gated at the UI/Settings layer (DEC-1).
- **Lemon Squeezy does not provide an update distribution mechanism.** It provides file hosting for product downloads (initial install) and license key validation, but not an appcast-compatible update feed.
- **Post-MVP license-gated updates** are a common pattern (e.g., "updates included for 1 year") but NOT planned per DEC-1 (subscription model = updates always included for active subscribers). This simplifies the architecture: Sparkle serves all users equally, license validation is orthogonal.

### Interaction Points

| Concern | MVP | Post-MVP |
|---|---|---|
| Initial download | Voxema website → DMG (no Lemon Squeezy gating) | Same |
| Update delivery | Sparkle → all users equally | Same (subscription includes updates) |
| License validation | None | LicenseManager checks JWT on launch, gates Pro UI features |
| Sparkle ↔ LicenseManager | No interaction | No interaction (updates are not license-gated) |

### Recommendation — Area 8

**No Sparkle-Lemon Squeezy integration needed.** Updates are delivered to all users equally via Sparkle. License validation is a separate concern handled by `LicenseManager` at the UI layer (DEC-1). This separation is architecturally clean and avoids coupling update delivery to billing infrastructure.

**Decision stability:** Stable (follows directly from DEC-1 subscription model)

---

## Implementation: UpdateManager Integration

Based on the recommendations above, here is the concrete `UpdateManager` specification for ARCHITECTURE.md:

### UpdateManager (MVP)

| Concern | Detail |
|---|---|
| Framework | Sparkle 2.x via SPM (`https://github.com/sparkle-project/Sparkle`) |
| Integration class | `SPUStandardUpdaterController` initialized in `@main` App struct |
| UI | Sparkle standard UI (built-in dialogs) |
| Menu integration | "Check for Updates…" via SwiftUI `CommandGroup(after: .appInfo)` |
| Update feed | Appcast XML hosted on GitHub Pages |
| DMG hosting | GitHub Releases |
| Signing | EdDSA (Ed25519) + Apple Developer ID code signing |
| Key storage | EdDSA public key in `Info.plist` (`SUPublicEDKey`) |
| Network dependency | Uses `NetworkManager` for connectivity check before update checks |
| Automatic checks | Enabled by default (user prompted on first launch per Sparkle standard) |
| Check interval | Sparkle default (24 hours) |
| Critical updates | Via `sparkle:criticalUpdate` appcast tag |
| Delta updates | Not at MVP — full DMG download |
| Beta channel | Not at MVP — single appcast feed |

### Info.plist Keys

| Key | Value | Purpose |
|---|---|---|
| `SUPublicEDKey` | (generated EdDSA public key) | Sparkle update signature verification |
| `SUFeedURL` | `https://your-org.github.io/voxema-updates/appcast.xml` | Appcast feed URL |
| `SUEnableAutomaticChecks` | `true` | Enable automatic background checks |

### File Changes

| File | Change |
|---|---|
| `Package.swift` / Xcode SPM | Add Sparkle 2.x dependency |
| `Info.plist` | Add `SUPublicEDKey`, `SUFeedURL` |
| `App/VoxemaApp.swift` | Initialize `SPUStandardUpdaterController`, add "Check for Updates" command |
| `Core/UpdateManager/` | Thin wrapper coordinating Sparkle with `NetworkManager` |
| `.github/workflows/release.yml` | Build → sign → notarize → DMG → EdDSA sign → GitHub Release → appcast |

---

## Recommended Approach — Summary

Integrate **Sparkle 2 via Swift Package Manager** with **GitHub Releases for DMG hosting** and **GitHub Pages for appcast hosting**. Use **Sparkle's standard built-in UI** at MVP. Code-sign with **Apple Developer ID** and verify updates with **EdDSA signatures**. Ship **full DMG updates** (no deltas at MVP). Update `models-manifest.json` **only through app releases** via Sparkle. **No integration with Lemon Squeezy** needed — updates are delivered to all users equally.

This is the simplest viable approach: zero hosting cost, zero custom UI code, zero additional infrastructure, one well-maintained open-source dependency (Sparkle), and a fully automated release pipeline via GitHub Actions.

---

## Decision Stability Summary

| Area | Decision | Stability |
|---|---|---|
| Framework | Sparkle 2 via SPM | Stable |
| Appcast hosting | GitHub Pages | Stable (can migrate by changing SUFeedURL) |
| DMG hosting | GitHub Releases | Stable (migrate to R2/S3 at scale) |
| Code signing | Apple Developer ID + EdDSA | Stable (platform requirement) |
| Delta updates | Defer to post-MVP | Temporary — revisit after 3–5 releases |
| Update UI | Sparkle standard UI | Stable for MVP, custom UI post-MVP optional |
| Model manifest | Via Sparkle only | Stable for MVP, revisit if model cadence exceeds release cadence |
| Lemon Squeezy | No integration needed | Stable |

---

## MVP vs Post-MVP Breakdown

### MVP — Implement Now

- [ ] Add Sparkle 2 as SPM dependency
- [ ] Generate EdDSA key pair, embed public key in `Info.plist`
- [ ] Set `SUFeedURL` in `Info.plist` pointing to GitHub Pages
- [ ] Initialize `SPUStandardUpdaterController` in `VoxemaApp.swift`
- [ ] Add "Check for Updates…" menu item via `CommandGroup`
- [ ] Create thin `UpdateManager` wrapper in `Core/UpdateManager/`
- [ ] Set up GitHub Actions release workflow (build → sign → notarize → DMG → upload → appcast)
- [ ] Set up GitHub Pages repo/branch for appcast hosting
- [ ] Securely backup EdDSA private key

### Post-MVP — Defer

- [ ] Delta updates (after pipeline is stable, ~3–5 releases)
- [ ] Custom SwiftUI update UI (after MVP UX is validated)
- [ ] Beta channel via separate appcast feed or `sparkle:channel`
- [ ] Phased rollouts via `sparkle:phasedRolloutInterval`
- [ ] Independent model manifest updates (if model catalog cadence warrants it)
- [ ] Migrate DMG hosting to R2/S3 (if bandwidth exceeds GitHub limits)

---

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| EdDSA private key loss | **Critical** — cannot ship accepted updates | Backup in password manager, never store unencrypted outside Keychain |
| Developer ID certificate expiration | **High** — app fails Gatekeeper | Calendar reminder, Apple sends renewal notices |
| GitHub Pages bandwidth limit (~100GB/mo) | **Low** at MVP scale | Monitor; migrate to R2 at scale |
| GitHub Releases file size limit (2GB per asset) | **None** — DMG is ~150–180MB | Well within limits |
| Sparkle SPM binary target updates lag | **Low** — Sparkle releases are infrequent | Pin to minor version range (2.x) |
| Notarization service downtime | **Low** — Apple's service is reliable | Retry in CI; manual release as fallback |
| Large DMG download on every update (no deltas) | **Medium** — poor UX on slow connections | Accept at MVP; add deltas post-MVP |

---

## Follow-up Implications

1. **ARCHITECTURE.md** must be updated with the concrete `UpdateManager` specification from this document
2. **PRD Technical Constraints** `Update mechanism` row should be updated from "Requires Discovery" to the concrete decision
3. An Apple Developer Program membership ($99/year) is a prerequisite — confirm enrollment
4. EdDSA key pair generation should happen early (before first build pipeline setup)
5. GitHub Pages setup (repo or branch) for appcast hosting should be part of the first CI/CD task
6. The release pipeline (GitHub Actions workflow) is a distinct implementation task

---

## Should This Go Into DECISIONS.md?

**Yes — record after implementation confirms the choice.** The Sparkle integration decision is architecturally significant (new dependency, new infrastructure in release pipeline, new keys to manage). Record as DEC-4 after the Architect plan is accepted and Builder confirms the approach works.

---

## Assumptions Made

1. Voxema's GitHub repository is on a plan that supports GitHub Pages and GitHub Releases with sufficient limits (free plan provides 100GB/month Pages bandwidth, 2GB per release asset — both sufficient).
2. The developer has (or will obtain) an active Apple Developer Program membership with Developer ID certificates.
3. The project uses Xcode 15+ with Swift 5.9+ as stated in PRD Technical Constraints.
4. The DMG size will remain in the ~150–180MB range as projected in DEC-2.
5. Model catalog changes will be infrequent enough to ship with app releases at MVP.

---

## Recommended Next Step

Product should update the PRD's `Update mechanism` Technical Constraint and ARCHITECTURE.md's `UpdateManager` section with the concrete Sparkle integration decisions from this Discovery. Then Architect should produce an implementation plan for the `UpdateManager` module and release pipeline.

---

```json
{
  "handoff": {
    "agent": "Discovery",
    "artifact_type": "design_note",
    "artifact_path": "docs/discoveries/FEAT-5-sparkle-integration.md",
    "status": "produced",
    "next_recommended_agent": "Product",
    "next_recommended_reason": "Discovery complete; update PRD Technical Constraints and ARCHITECTURE.md UpdateManager with Sparkle integration decisions.",
    "blocking_issues": [],
    "workflow_state": {
      "task_id": "FEAT-5",
      "artifact_id": null,
      "current_stage": "discovery",
      "quality_loop_iteration": 0,
      "builder_cycle_count": 0,
      "analytics_used": false,
      "product_spec_accepted": false
    }
  }
}
```
