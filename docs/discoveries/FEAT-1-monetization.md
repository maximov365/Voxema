# Discovery: FEAT-1 — Monetization Strategy

**Mode:** Combined Technical + Market & Competitive Discovery
**Date:** 2026-03-29

---

## Discovery Question

What is the best monetization strategy for Voxema — pricing, feature gating, payment infrastructure, and go-to-market — given:
- Three tiers defined in PRD: Free (fully local), Pro (managed cloud LLM proxy), Enterprise (corporate perimeter)
- Privacy-first positioning as core differentiator
- macOS-only, Apple Silicon, direct DMG distribution for MVP
- MVP ships Free tier first (no backend), Pro comes post-MVP
- Enterprise is a later phase

---

## Prior Decisions

None found in `docs/DECISIONS.md`. This is the first monetization-related decision.

---

## Context

Voxema's monetization strategy must balance several forces:

1. **Privacy-first positioning** — the core differentiator is "meeting intelligence without your data leaving your device." This directly informs what can be gated: local processing must remain free, cloud features are the natural upsell.
2. **Fully functional Free tier** — the PRD defines Free as a complete meeting pipeline (capture → transcribe → diarize → summarize → export) using local models, plus CloudProvider (direct API) with user's own key. This is more capable than most competitors' free tiers.
3. **No backend at MVP** — monetization infrastructure (billing, license validation) cannot depend on a backend that doesn't exist yet. Feature gating must work offline.
4. **SummaryProvider protocol abstraction** — the architecture cleanly separates local vs cloud summarization behind a protocol. Feature gating can leverage this boundary.
5. **DMG distribution** — no Mac App Store at MVP, so Apple's In-App Purchase is not available. Need an independent payment solution.

---

## Market & Competitive Research

### Reference 1 — Otter.ai

- **What they do:** Cloud-based meeting transcription with real-time notes, speaker ID, and AI summaries. Bot joins Zoom/Meet/Teams calls.
- **UX approach:** Freemium with aggressive usage limits on free tier (300 min/month, 30 min per meeting, 25 transcript history limit). Pro unlocks more minutes and features.
- **Pricing:** Free → Pro $8.33/mo (annual) / $16.99/mo (monthly) → Business $20/mo → Enterprise custom
- **Strengths:** Strong brand recognition, real-time transcription, excellent integrations, generous annual discount (50% off Pro)
- **Weaknesses:** All audio sent to cloud (privacy concern), free tier heavily restricted (unusable for regular users), no local processing option
- **URL:** https://otter.ai/pricing

### Reference 2 — Fireflies.ai

- **What they do:** AI meeting assistant with transcription, summaries, and conversation intelligence. Bot-based recording.
- **UX approach:** Freemium with unlimited free transcription but limited AI summaries and storage. Pro adds unlimited AI features.
- **Pricing:** Free → Pro $10/mo (annual) / $18/mo (monthly) → Business $19/mo → Enterprise $39/mo
- **Strengths:** Lowest paid entry point among cloud competitors, unlimited free transcription, good integrations
- **Weaknesses:** Cloud-only, bot-based recording can fail, free tier AI summaries limited
- **URL:** https://fireflies.ai/pricing

### Reference 3 — Krisp

- **What they do:** On-device noise cancellation + meeting transcription + AI notes. Local audio processing with cloud AI features.
- **UX approach:** No free tier — 7-day trial only, then paid. Core plan is the entry point. Emphasizes bot-free recording (similar to Voxema's approach).
- **Pricing:** Core $8/mo (annual) / $16/mo (monthly) → Advanced custom → Enterprise custom
- **Strengths:** Bot-free recording, noise cancellation differentiator, local audio processing, positioned similarly on privacy
- **Weaknesses:** No permanent free tier (reduces top-of-funnel), cloud dependency for AI features, limited by 16 languages
- **URL:** https://krisp.ai/pricing

### Reference 4 — MacWhisper

- **What they do:** Local Whisper-based transcription for macOS. One-time purchase model. No meeting intelligence (transcription only).
- **UX approach:** Free tier with small models, one-time purchase for Pro features and larger models. Also available on Mac App Store with subscription.
- **Pricing:** Free (tiny/base models) → Lifetime $69–$80 (Gumroad) or $29.99/yr / $99.99 lifetime (App Store). Assistant subscription $9.99/mo for cloud features.
- **Strengths:** One-time purchase option (loved by users), local-first, simple value proposition, dual distribution (Gumroad + App Store)
- **Weaknesses:** Transcription only (no meeting intelligence, no diarization, no summaries), cloud features are add-on subscription on top of purchase
- **URL:** https://goodsnooze.gumroad.com/l/macwhisper

### Reference 5 — Superwhisper

- **What they do:** Local Whisper-based dictation/transcription for macOS. System-wide voice-to-text.
- **UX approach:** Free tier with small local models, Pro subscription for cloud models and advanced features. Also offers lifetime purchase.
- **Pricing:** Free → Pro $8.49/mo or $84.99/yr → Lifetime $249.99
- **Strengths:** Clean free-to-Pro upgrade path, local models free with cloud as upsell (very similar to Voxema's model), lifetime option
- **Weaknesses:** Dictation-focused (not meeting intelligence), lifetime price is high
- **URL:** https://superwhisper.com

### Reference 6 — Talat

- **What they do:** Privacy-first meeting notes for Mac. Local processing on Apple Neural Engine.
- **UX approach:** One-time purchase with free evaluation hours.
- **Pricing:** $49 pre-release → $99 at full release (one-time)
- **Strengths:** Direct competitor positioning (privacy-first, Mac-only, meeting intelligence), one-time purchase appeals to privacy audience
- **Weaknesses:** Early stage, limited features, no free tier, no subscription revenue
- **URL:** https://talat.app

### Reference 7 — Meetily (open-source)

- **What they do:** Open-source meeting assistant with local Whisper transcription, speaker diarization, and Ollama summarization.
- **UX approach:** Fully free and open-source. No monetization.
- **Strengths:** Validates that the local pipeline approach works, community-driven
- **Weaknesses:** No business model, rough UX, requires technical setup
- **URL:** https://github.com/Zackriya-Solutions/meetily

### Patterns Observed

1. **Usage-limited free tier is standard.** Otter, Fireflies, and Superwhisper all offer free tiers with meaningful limitations (minutes, features, model sizes). This creates a natural upgrade trigger.

2. **$8–$10/mo (annual) is the sweet spot for individual Pro tiers** across Fireflies ($10), Krisp ($8), Otter ($8.33), and Superwhisper ($8.49). Monthly pricing is roughly 2× annual.

3. **Cloud AI features are the natural upsell.** Superwhisper's model (free local + paid cloud) is nearly identical to Voxema's planned approach and validates the strategy.

4. **One-time purchase resonates with privacy-conscious users.** MacWhisper and Talat both use one-time pricing. Privacy users distrust subscriptions because they imply ongoing data relationships. However, one-time purchase doesn't support Voxema's cloud LLM proxy costs.

5. **Annual billing with 40–50% discount drives commitment.** Every competitor with subscriptions offers steep annual discounts.

6. **No competitor offers both full local pipeline AND managed cloud — Voxema's unique position.** Cloud tools (Otter, Fireflies) have no local option. Local tools (MacWhisper, Talat) have limited or no cloud option. Voxema bridges both worlds.

---

## Options Considered

1. **Subscription-only Pro** — Monthly/annual subscription for Pro tier with managed cloud LLM access
2. **Hybrid: Subscription Pro + Lifetime Local Premium** — Subscription for cloud features, one-time purchase for advanced local features
3. **Usage-based Pro** — Pay per cloud summarization minute/token
4. **Freemium with limits on Free tier** — Restrict Free tier (e.g., meeting count, export limits) to drive upgrades

---

## Comparison

### Option 1 — Subscription-only Pro

- **pros:** Predictable recurring revenue; aligns with cloud LLM operating costs (Voxema pays per API call, user pays per month); simple pricing communication; standard in the market
- **cons:** Subscription fatigue among privacy-conscious users; requires billing infrastructure; Free tier must remain compelling enough to attract users
- **dependency friendliness:** Works with any payment provider (Paddle, Lemon Squeezy, Stripe)
- **implementation simplicity:** High — single billing model, clear tier boundary
- **operational simplicity:** medium — requires subscription lifecycle management (renewals, cancellations, grace periods)
- **value-to-complexity:** high
- **reversibility:** easy — can add lifetime option or usage-based component later
- **pipeline fit:** fits cleanly — SummaryProvider protocol already separates local/cloud; gating is a UI/settings concern, not a pipeline concern
- **MVP fit:** Strong — Free tier ships alone at MVP, subscription infrastructure added with Pro launch post-MVP
- **long-term fit:** Strong — supports Enterprise tier extension

### Option 2 — Hybrid: Subscription + Lifetime Local Premium

- **pros:** Captures one-time purchase audience (privacy users who hate subscriptions); subscription covers cloud costs; more revenue streams
- **cons:** Complex pricing communication; two billing models to maintain; "what do I get for what?" confusion; splits engineering effort
- **dependency friendliness:** Requires payment provider supporting both subscriptions and one-time purchases
- **implementation simplicity:** Low — two separate entitlement systems, two validation flows
- **operational simplicity:** low — managing two pricing models, handling upgrades between them
- **value-to-complexity:** medium
- **reversibility:** hard — removing a tier after users purchased it creates support burden
- **pipeline fit:** fits cleanly — same SummaryProvider boundary applies
- **MVP fit:** Weak — too complex for initial monetization launch
- **long-term fit:** Medium — could revisit as a "Lifetime Local" add-on once subscription is stable

### Option 3 — Usage-based Pro

- **pros:** Users pay only for what they use; aligns costs perfectly with Voxema's cloud LLM costs; low barrier to try
- **cons:** Unpredictable revenue; hard to communicate value; users avoid using features to save money (anti-engagement); complex metering infrastructure
- **dependency friendliness:** Requires usage tracking backend and metering system
- **implementation simplicity:** Low — requires per-request tracking, usage dashboards, billing calculations
- **operational simplicity:** low — metering disputes, usage caps, overage handling
- **value-to-complexity:** low
- **reversibility:** easy — can switch to flat subscription
- **pipeline fit:** requires adaptation — needs usage tracking hooks in Summarize stage
- **MVP fit:** Weak — too much infrastructure needed
- **long-term fit:** Medium — could be a component within Enterprise pricing

### Option 4 — Freemium with Limits on Free Tier

- **pros:** Creates urgency to upgrade; standard freemium playbook
- **cons:** Directly contradicts Voxema's positioning — "meeting intelligence without your data leaving your device" implies the local pipeline is complete and unrestricted; artificial limits on local processing feel dishonest; reduces word-of-mouth ("this tool is amazing AND free locally")
- **dependency friendliness:** Requires local usage tracking
- **implementation simplicity:** Medium — needs local counters, limit enforcement, upgrade prompts
- **operational simplicity:** medium — limit thresholds need tuning, user complaints about limits
- **value-to-complexity:** low — damages brand for marginal revenue
- **reversibility:** hard — removing limits after users hit them causes expectation reset
- **pipeline fit:** conflicts — introduces artificial constraints into a pipeline designed to be complete
- **MVP fit:** Weak — undermines the "fully local, fully free" MVP story
- **long-term fit:** Weak — conflicts with core positioning

---

## Decision Quality Score

Scoring rule: 1 = poor, 3 = acceptable, 5 = strong. Scores support reasoning but do not determine the decision.

### Option 1 — Subscription-only Pro

- MVP fit: 5
- architecture fit: 5
- implementation simplicity: 5
- reversibility: 5
- dependency friendliness: 5
- operational simplicity: 4
- testability: 5
- long-term fit: 5
- **Total: 39/40**

### Option 2 — Hybrid Subscription + Lifetime

- MVP fit: 2
- architecture fit: 4
- implementation simplicity: 2
- reversibility: 2
- dependency friendliness: 3
- operational simplicity: 2
- testability: 3
- long-term fit: 3
- **Total: 21/40**

### Option 3 — Usage-based Pro

- MVP fit: 1
- architecture fit: 3
- implementation simplicity: 1
- reversibility: 4
- dependency friendliness: 2
- operational simplicity: 1
- testability: 2
- long-term fit: 3
- **Total: 17/40**

### Option 4 — Freemium with Free Tier Limits

- MVP fit: 1
- architecture fit: 2
- implementation simplicity: 3
- reversibility: 2
- dependency friendliness: 4
- operational simplicity: 3
- testability: 3
- long-term fit: 1
- **Total: 19/40**

---

## Decision Stability

**Stable** — subscription model for cloud features is the industry standard for this category and aligns with Voxema's cost structure. Revisit only if user research during F&F beta reveals strong demand for one-time purchase (consider Hybrid as future add-on).

---

## Recommendation

**Option 1 — Subscription-only Pro** with the following specific parameters:

### Pricing

| Tier | Monthly | Annual | Effective Monthly (Annual) |
|------|---------|--------|---------------------------|
| **Free** | $0 | $0 | $0 |
| **Pro** | $12/mo | $96/yr | $8/mo |

**Rationale for $8–$12 range:**
- Competitive with Krisp ($8/annual), Fireflies ($10/annual), Otter ($8.33/annual), Superwhisper ($8.49)
- $8/mo effective annual rate is the market sweet spot
- $12/mo monthly rate provides 33% annual discount incentive (less aggressive than Otter's 50% but more sustainable)
- Voxema offers MORE than competitors at this price: full local pipeline is free, Pro adds managed cloud on top

### Feature Gating

**Free tier (MVP and beyond) — no limits on local functionality:**
- Full pipeline: capture → transcribe → diarize → summarize → export
- LocalProvider (llama.cpp) — unlimited
- CloudProvider (direct API) with user's own key — unlimited
- All Whisper model sizes
- Meeting library, search, all export formats
- Voice profile management
- No meeting count limits, no time limits

**Pro tier (post-MVP):**
- Everything in Free
- Managed cloud LLM summarization (Voxema proxy) — no API key management
- Server-side optimized prompts (better summaries without prompt engineering)
- Priority model access (latest/largest cloud models as they release)
- Advanced export templates (custom Markdown templates, structured formats)
- Cloud prompt iteration (prompts improve without app updates)
- Email support

**Enterprise tier (later phase):**
- Everything in Pro
- OnPremProvider support (custom LLM endpoints)
- Volume licensing
- SSO/SCIM
- Admin dashboard
- Custom deployment support

**CloudProvider (direct API) stays in Free tier.** This is critical:
- Users who bring their own API key are power users; they become evangelists
- Gating it behind Pro would feel hostile to the privacy audience
- Pro's value is convenience (no key management) + quality (optimized prompts), not access

### Payment Infrastructure

**Recommended: Lemon Squeezy** as the payment processor / merchant of record.

| Criteria | Lemon Squeezy | Paddle | Stripe |
|----------|--------------|--------|--------|
| Merchant of record | Yes | Yes | No |
| Tax handling | Included | Included | You handle it |
| Fee | 5% + $0.50 | 5% + $0.50 | 2.9% + $0.30 |
| License key API | Built-in | Built-in (Mac SDK) | No (need separate service) |
| Indie/small team fit | Excellent | Good | Good |
| Setup complexity | Low | Medium | High (tax compliance) |
| macOS app support | Via license key API | Native Mac SDK | Via Stripe API + custom license system |
| Offline validation | JWT-based via license key | Paddle SDK supports | Custom implementation needed |

**Why Lemon Squeezy over Paddle:**
- Simpler setup for a solo/small team at MVP stage
- Built-in license key API with activation/validation endpoints
- Supports offline validation via JWT tokens (critical for Voxema's offline-first design)
- Paddle's Mac SDK (v3) is at end-of-life; v4 direction uncertain
- Same pricing as Paddle (5% + $0.50) but lower setup overhead
- Can migrate to Paddle later if Enterprise needs demand it

**Why not Stripe:**
- No merchant of record = VAT/tax compliance burden from day one
- Lower fees (2.9%) offset by tax compliance costs ($5K–$20K/yr)
- No built-in license key system
- Better suited for the backend billing system (post-MVP), not the initial launch

### Technical Implementation — Feature Gating

**MVP (Free tier only — no gating needed):**
- Ship with all local features enabled
- No license validation code needed
- SummaryProvider defaults to LocalProvider and CloudProvider (direct API)
- Settings UI shows provider selection: Local / Cloud (API Key)

**Post-MVP (Free + Pro):**

1. **License validation via Lemon Squeezy license key API:**
   - User purchases Pro on Voxema website (Lemon Squeezy checkout)
   - Receives license key via email
   - Enters key in app Settings → activates via Lemon Squeezy API
   - App stores signed JWT token in Keychain
   - JWT contains: expiry, product ID, subscription status
   - Offline validation: verify JWT signature with embedded public key (no network needed)
   - Periodic online refresh when connectivity available (e.g., every 7 days)

2. **Feature gating in code:**
   - `LicenseManager` — new module in `Core/` that manages license state
   - `LicenseStatus` enum: `.free`, `.pro`, `.expired`, `.trial`
   - SummaryProvider selection gated: VoxemaProxyProvider only available when `LicenseStatus == .pro`
   - Settings UI conditionally shows Pro features based on license status
   - No pipeline changes needed — gating happens at the UI/configuration layer, not inside pipeline stages

3. **Impact on SummaryProvider protocol:**
   - No protocol changes required
   - Add new `VoxemaProxyProvider` conformance (post-MVP) alongside existing providers
   - Provider selection logic in Settings/UI checks license status
   - Pipeline receives whichever provider was selected — no pipeline-level awareness of licensing

4. **Transition path (Free-only → Free+Pro):**
   - Add `LicenseManager` module
   - Add `VoxemaProxyProvider` (SummaryProvider conformance)
   - Add license key entry in Settings
   - Add upgrade prompt in Summarize settings when user sees Local/CloudAPI options
   - No changes to existing Free functionality
   - No changes to pipeline stages or contracts

### Go-to-Market

**Distribution path:**
1. **F&F Beta** — Direct DMG via TestFlight or direct download. Free tier only. Collect feedback on core pipeline quality.
2. **Public Beta** — Launch on ProductHunt, Hacker News. Free tier only. Build audience and mailing list.
3. **Pro Launch** — Enable Pro tier with Lemon Squeezy checkout on voxema.com. Announce to beta audience.
4. **Steady state** — Content marketing (privacy-focused meeting productivity), community building, word-of-mouth.

**Mac App Store (later):**
- Consider after Pro tier is stable
- 30% cut is significant but offset by discoverability
- Would require adapting from license key to In-App Purchase (or keeping both)
- RevenueCat can manage Mac App Store subscriptions if/when needed
- Decision point: when organic growth plateaus and App Store discoverability is needed

**User acquisition channels for privacy-focused tools:**
- Hacker News / ProductHunt launches (privacy tools perform well here)
- Reddit: r/macapps, r/productivity, r/privacy
- Developer and privacy-focused podcasts
- Blog content: "How to keep your meeting data private," comparisons with cloud tools
- Word-of-mouth: the "fully free local" tier is the viral engine — users recommend it freely because there's no catch

**Key insight:** The generous Free tier IS the marketing strategy. Unlike Otter/Fireflies where the free tier is a demo, Voxema's free tier is a complete product. Users adopt it, love it, tell others. Some percentage naturally upgrade to Pro for convenience.

---

## Score Interpretation

Option 1 (Subscription-only Pro) scores 39/40 because it aligns perfectly with every constraint:
- MVP ships without any monetization code (MVP fit: 5)
- Gating boundary maps directly to the SummaryProvider protocol boundary (architecture fit: 5)
- Single billing model with a proven third-party service (implementation simplicity: 5)
- Can add lifetime, usage-based, or hybrid pricing later without rework (reversibility: 5)

No other option comes close because Options 2–4 all introduce complexity that doesn't pay off at this stage.

---

## Why This Is the Simplest Viable Choice

Subscription-only Pro is the simplest choice because:
1. **No monetization code at MVP** — ship Free tier, iterate on quality
2. **One billing model** — Lemon Squeezy handles checkout, tax, license keys
3. **One gating boundary** — SummaryProvider type (local/cloud-direct = free, Voxema proxy = Pro)
4. **Offline-friendly** — JWT-based license validation works without persistent connectivity
5. **Zero pipeline changes** — feature gating lives in UI/Settings, not in pipeline stages

---

## Risks / Trade-offs

1. **Free tier might be "too good"** — Risk that users never upgrade because local + own API key covers all needs. Mitigation: Pro's value is convenience (no key management) + quality (optimized prompts) + ongoing improvement (server-side prompt iteration). Monitor conversion rate during beta; if <2% convert, consider adding Pro-exclusive features (advanced export templates, multi-language summarization, custom prompt library).

2. **Subscription fatigue** — Privacy-conscious users may prefer one-time purchase. Mitigation: Monitor user feedback during F&F beta. If demand for lifetime license is strong, add a "Lifetime Pro" option (e.g., $149–$199) as a complement to subscription, not a replacement. Lemon Squeezy supports both models.

3. **Lemon Squeezy dependency** — Single payment provider. Mitigation: License validation is JWT-based with a public key — the validation logic is provider-independent. Migration to another provider requires changing the checkout and key issuance, not the in-app validation.

4. **Cloud LLM cost exposure** — Pro subscription at $8/mo must cover Voxema's per-user cloud LLM costs. Mitigation: Monitor cost-per-user during Pro beta. If heavy users exceed cost, add soft usage guidance (e.g., "You've used 50 cloud summaries this month") or tiered Pro plans. Server-side prompt optimization reduces token usage.

5. **No backend at MVP means no Pro at MVP** — This is by design. Pro launch depends on backend services (FEAT-3). Plan the backend with billing/licensing integration from the start.

---

## Follow-up Implications

- **FEAT-3 (Backend Technology Stack)** must account for: LLM proxy, subscription validation, usage tracking, license key webhook from Lemon Squeezy
- **PRD Monetization Model** should be updated with specific pricing, feature gating details, and payment infrastructure choice
- `docs/ARCHITECTURE.md` will need a `LicenseManager` module when Pro tier is implemented
- `docs/PIPELINE_CONTRACTS.md` does NOT need changes — gating is outside the pipeline
- Enterprise pricing and volume licensing are deferred; revisit after Pro tier has traction

---

## Should This Go Into DECISIONS.md?

**Yes — record after Product agent updates the PRD Monetization Model** with these specific recommendations and the user approves.

Proposed decision entry:

> **Monetization Model: Subscription-only Pro with Lemon Squeezy**
> Free tier is fully functional local pipeline (no limits). Pro tier ($8–$12/mo) adds managed cloud LLM proxy. Payment via Lemon Squeezy (merchant of record) with JWT-based offline license validation. CloudProvider (direct API with user's own key) remains in Free tier. No gating of local features.

---

## Optional Follow-ups

- Research Lemon Squeezy webhook integration patterns for subscription lifecycle events (activation, renewal, cancellation, refund)
- Evaluate whether a 14-day Pro trial should be offered at launch (common in the market; Krisp does 7 days, Grain does 14 days)
- Research referral program mechanics (e.g., "give 1 month Pro, get 1 month Pro" — aligns with word-of-mouth growth)
- Investigate whether Mac App Store distribution would use In-App Purchase (RevenueCat) alongside Lemon Squeezy direct, or replace it

---

## Assumptions Made

- Voxema's per-user cloud LLM cost will be manageable at $8/mo effective price (typical meeting summarization uses 2K–10K tokens per summary; at current API prices this is well under $1 per summary)
- Privacy-conscious users will accept a subscription model if the free tier is genuinely complete and the subscription only adds optional cloud convenience
- Lemon Squeezy will remain operational and maintain their license key API (mitigated by provider-independent JWT validation)
- Pro tier launch will coincide with backend availability (FEAT-3)

---

## Recommended Next Step

Product agent should update the PRD Monetization Model section with specific pricing ($8–$12/mo Pro), feature gating details (what's in Free vs Pro vs Enterprise), payment infrastructure (Lemon Squeezy), and the technical gating approach (LicenseManager + JWT). This gives Architect a concrete specification to plan the LicenseManager module and VoxemaProxyProvider implementation.

---

```json
{
  "handoff": {
    "agent": "Discovery",
    "artifact_type": "design_note",
    "artifact_path": "docs/discoveries/FEAT-1-monetization.md",
    "status": "produced",
    "next_recommended_agent": "Product",
    "next_recommended_reason": "Discovery complete; Product agent should update PRD Monetization Model with specific pricing, feature gating, payment infrastructure, and gating approach recommendations.",
    "blocking_issues": [],
    "workflow_state": {
      "task_id": "FEAT-1",
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
