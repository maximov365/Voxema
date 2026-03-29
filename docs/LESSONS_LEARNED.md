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
