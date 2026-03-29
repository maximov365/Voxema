# Decisions

<!-- Record significant technical decisions here. -->
<!-- Each decision should include: context, options considered, decision, and rationale. -->

| ID | Title | Status | Date |
|----|-------|--------|------|
| DEC-1 | Monetization: Subscription-only Pro with Lemon Squeezy | accepted | 2026-03-29 |

---

## DEC-1 — Monetization: Subscription-only Pro with Lemon Squeezy

**Status:** accepted
**Date:** 2026-03-29
**Source:** Discovery FEAT-1 (`docs/discoveries/FEAT-1-monetization.md`)

### Context

Voxema needs a monetization model that respects privacy-first positioning, supports cloud LLM operating costs for Pro tier, and works with DMG direct distribution (no App Store at MVP).

### Options Considered

1. Subscription-only Pro (recommended)
2. Hybrid: Subscription + Lifetime Local Premium
3. Usage-based Pro
4. Freemium with limits on Free tier

### Decision

**Subscription-only Pro** with Lemon Squeezy as merchant of record.

- **Free:** $0 — full local pipeline, no limits, CloudProvider (direct API) with user's own key
- **Pro:** $12/mo or $96/yr ($8/mo effective) — managed cloud LLM proxy, optimized prompts, no API key management
- **Enterprise:** custom pricing (later phase)
- **Payment:** Lemon Squeezy — merchant of record, built-in license key API, JWT-based offline validation
- **Feature gating:** UI/Settings layer via LicenseManager module; pipeline stages unaffected
- **CloudProvider (direct API) remains in Free tier** — Pro sells convenience + quality, not access

### Rationale

- Aligns with cloud LLM cost structure (Voxema pays per API call, user pays per month)
- $8–$12/mo validated against market (Otter $8.33, Krisp $8, Fireflies $10, Superwhisper $8.49)
- Lemon Squeezy handles tax compliance, supports JWT offline validation (critical for offline-first)
- No monetization code at MVP — Free tier ships alone
- Reversible: can add lifetime option or usage component later
- Scored 39/40 on decision quality (highest of 4 options)

### Subject to adjustment after F&F beta user testing.
