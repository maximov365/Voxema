# Lessons learned

Project-specific log of what went wrong in completed workflows, what review feedback repeated, and what worked. **Append-only** by default — do not delete history; Iteration Manager may add a short "superseded by" note if a lesson no longer applies.

**Maintainer:** Iteration Manager appends a new section after each workflow that reached completion (Reviewer approved) or was explicitly closed with a documented outcome.

**Audience:** Every agent reads this file (with `KNOWN_PATTERNS.md`) before starting work, per `AGENTS.md`.

---

## How to write an entry

Use one block per closed workflow. Keep it factual and short.

```markdown
## YYYY-MM-DD — <task id or short title>

**Workflow outcome:** completed | closed (other)

### What went wrong
- ...

### Repeated must_fix / review / security themes
- ... (quote or paraphrase recurring themes from Spec Reviewer, Reviewer, Security Reviewer)

### What worked well
- ... (optional; durable wins also belong in `KNOWN_PATTERNS.md`)

### Follow-ups
- ... (optional — links to `docs/TASKS.md` entries if any)
```

---

## Entries

*(Iteration Manager appends below this line.)*

## 2026-03-29 — PRD-update-v2 (PRD major revision)

**Workflow outcome:** completed

### What went wrong
- none

### Repeated must_fix / review / security themes
- MVP scope inconsistency: Core Capabilities and User Flows described features (JSON export) not listed in MVP scope. Spec Reviewer caught the mismatch. Lesson: when adding capabilities to the PRD body, always cross-check the MVP scope list.
- Data model cardinality must match PIPELINE_CONTRACTS.md. PRD stated Meeting→Summary as 1→1 but pipeline contracts define summary as optional. Lesson: any entity relationships in PRD must be validated against pipeline contracts before committing.

### What worked well
- User provided detailed change requirements upfront, which enabled a single Product pass with no ambiguity.
- Quality loop resolved both must_fix items in one Reviser iteration (7.8 → 8.3).
- Spec Reviewer caught a real source conflict (PRD vs PIPELINE_CONTRACTS.md cardinality) that would have caused schema issues downstream.

### Follow-ups
- FEAT-1: Discovery for monetization strategy
- FEAT-2: Discovery for model packaging strategy
- Spec Reviewer should_fix: clarify summary failure path in Typical Recording Flow; clarify Activation metric when summarization fails; add C++ bridging risk; add ECAPA-TDNN model availability risk; clarify Speaker entity vs SpeakerIdentity distinction

## 2026-03-29 — PRD-update-v3 (Backend Services, CloudProvider dual-mode)

**Workflow outcome:** completed

### What went wrong
- CloudProvider description was rewritten to describe only the backend-proxied mode, creating an MVP scope inconsistency (CloudProvider in MVP scope but requiring post-MVP backend). Exact repeat of the pattern from PRD-update-v2: capabilities described in the body that conflict with MVP scope list.

### Repeated must_fix / review / security themes
- MVP scope inconsistency (second occurrence). Lesson reinforced: when modifying a capability description in the PRD body, ALWAYS check whether the MVP scope list still matches. This is now a documented recurring pattern.
- Adding a new deployment/infrastructure model (backend proxy) changes the semantics of existing components (CloudProvider). All references to the changed component must be updated consistently — Summarization, Monetization, Offline-First UX, Privacy guardrails.

### What worked well
- Spec Reviewer caught the CloudProvider scope inconsistency on iteration 1 — no downstream confusion.
- Dual-mode CloudProvider (direct API for MVP, Voxema proxy for Pro) resolved the tension cleanly: MVP stays self-contained, Pro adds managed experience.
- Quality loop resolved both must_fix items in one Reviser pass (6.6 → 7.6).

### Follow-ups
- FEAT-3: Discovery for backend technology stack
- FEAT-4: ARCHITECTURE.md update for CloudProvider dual-mode
- Spec Reviewer should_fix: qualify Vision statement re cloud opt-in; qualify MVP scope CloudProvider as direct-API-only; plan PIPELINE_CONTRACTS.md update for provider_used granularity

## 2026-03-29 — PRD-update-v4 (Versioning & Update Strategy, Accessibility)

**Workflow outcome:** completed

### What went wrong
- none

### Repeated must_fix / review / security themes
- none (accepted on first pass; MVP scope cross-check lesson applied proactively — no scope inconsistencies introduced)

### What worked well
- Proactive MVP scope cross-checking (lesson from v2 and v3) prevented any must_fix items. First PRD update to pass quality loop on the first iteration.
- Small, focused changes are lower risk and faster through the quality loop.

### Follow-ups
- FEAT-5: Discovery for Sparkle integration
- Spec Reviewer should_fix: tighten Sparkle MVP scope bullet wording to distinguish "check-for-updates" vs "full auto-update"; consider testable acceptance criterion for update mechanism

## 2026-03-29 — FEAT-1 Discovery + PRD monetization update

**Workflow outcome:** completed

### What went wrong
- MVP scope inconsistency (third occurrence): Monetization Free tier claimed "All Whisper model sizes" while MVP scope lists "tiny/base/small". Also Admin Dashboard described as "F&F beta stage" but MVP has no backend.

### Repeated must_fix / review / security themes
- MVP scope vs body mismatch is now a **three-time recurring pattern**. Every PRD update that adds capabilities to the body risks this. Lesson: before submitting ANY PRD change for review, run a literal line-by-line check of MVP In scope and Not in scope against every claim in the body.

### What worked well
- Discovery FEAT-1 produced comprehensive market research (7 competitors, concrete pricing data) and a clear recommendation (39/40 score).
- Subscription-only Pro is the simplest viable choice — no pipeline changes, gating at UI layer only.
- Lemon Squeezy's JWT offline validation aligns perfectly with offline-first design.

### Follow-ups
- FEAT-3: Backend tech stack Discovery (must account for Lemon Squeezy webhook integration)
- Should_fix: qualify Free tier Whisper wording to lead with MVP scope; align Admin Dashboard "post-beta" phrasing

---

## FEAT-2 — Discovery: Model packaging strategy

**Workflow:** Discovery → PRD update (direct, no quality loop — changes limited to two table cells replacing "Requires Discovery" with concrete strategy)
**Date:** 2026-03-29

### Errors / unexpected
- None. Changes were scoped to replacing placeholder text; no new capabilities or scope items added, so MVP scope inconsistency risk was minimal.

### Repeated themes
- None this cycle.

### What worked well
- Discovery produced actionable research from 4 competitors (MacWhisper, Superwhisper, WhisperKit, speech-swift) confirming industry-standard hybrid bundle approach.
- Explicit decision stability annotations (stable vs. temporary) help future agents know which decisions to revisit.
- Pre-commit MVP scope verification check prevented potential issues — pattern from previous cycles applied proactively.

### Follow-ups
- FEAT-3: Backend tech stack Discovery (next)
- Default LLM (Qwen 2.5 3B) marked as temporary — needs benchmarking with real transcripts post-Builder
