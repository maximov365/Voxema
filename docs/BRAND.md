# Voxema — Brand Identity Guide

**Version:** 1.2  
**Status:** Approved  
**Owner:** Iteration Manager  
**Visual reference:** `docs/designs/BRAND-guide.html`

---

## Brand Essence

**Name:** Voxema  
**Origin:** "Vox" (Latin: voice) + "ema" (schema/emblem suffix)  
**Tagline:** *Your meetings. Your data. Your device.*  
**Positioning:** Privacy-first meeting intelligence for macOS professionals.

---

## Logo Mark — Circle + Arcs

### Concept

The Voxema mark is a **white circle ring with three concentric arcs** wrapping almost fully around it.

- The **circle** represents the meeting — a bounded conversation.
- The **three concentric arcs** are audio ripples propagating outward — voice being captured and understood.
- The progressive colour fade (white → mid blue → dim blue) reads as distance and depth.
- All arcs share a ~40° opening in the upper-right quadrant, giving the mark direction without breaking its circular unity.

The mark is stroke-only: no fills, no gradients — built for pixel-perfect scalability and single-colour rendering as a macOS menu bar template image.

### Canonical SVG

```xml
<!-- Voxema Mark — viewBox 0 0 100 100 — stroke-only, no fills -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" fill="none">

  <!-- Circle ring — center anchor -->
  <circle cx="50" cy="50" r="14"
          stroke="white" stroke-width="5"/>

  <!-- Arc 1 — r=23, 320° CW (gap 15°→55°) — white -->
  <path d="M 63.2 68.8 A 23 23 0 1 1 72.2 56.0"
        stroke="white" stroke-width="4.5" stroke-linecap="round"/>

  <!-- Arc 2 — r=32, 320° CW — #80b4ff -->
  <path d="M 68.4 76.2 A 32 32 0 1 1 80.9 58.3"
        stroke="#80b4ff" stroke-width="4" stroke-linecap="round"/>

  <!-- Arc 3 — r=41, 320° CW — #4080c0 -->
  <path d="M 73.5 83.6 A 41 41 0 1 1 89.6 60.6"
        stroke="#4080c0" stroke-width="3.5" stroke-linecap="round"/>

</svg>
```

**Mark construction:**
- Center: `cx=50 cy=50` — all elements share this origin.
- All arcs: 320° clockwise, gap spanning ~15°→55° (upper-right quadrant).
- `stroke-linecap: round` on all paths. Always.
- Scale `stroke-width` up proportionally at small sizes (≤32px rendered).
- Background color must always come from the approved color system.

### Color States

| State | Circle & Arc 1 | Arc 2 | Arc 3 | Background |
|---|---|---|---|---|
| Idle (dark) | `white` | `#80b4ff` | `#4080c0` | `#0f1923` (Ink) |
| Idle (light) | `#1c1c1e` | `#007aff` | `#4090d0` | `#f2f2f7` (Cloud) |
| Recording | `#e53e3e` | `#ff6060` | `#c02020` | `#0f1923` + pulse animation |
| Monochrome / menu bar | `rgba(235,235,245,0.9)` | `rgba(235,235,245,0.5)` | `rgba(235,235,245,0.25)` | System template |

### App Icon

- Shape: macOS superellipse (`corner-radius ≈ 22.37%` of side)
- Background: `#0f1923` (Ink Soft)
- Mark: centered, Idle (dark) state

### Menu Bar Icon

- Format: PDF template image (single-color, system compositing)
- **Idle:** white strokes, system renders at system label color
- **Recording:** all strokes switch to `#e53e3e` + 2s pulse animation (scale 1.0→1.08→1.0, ease-in-out)
- Fallback SF Symbol: `waveform` (idle) / `waveform` with red tint (recording)

### Wordmark

Font: `-apple-system SF Pro Display`, weight 800, letter-spacing −0.8px, title case only.  
Name: **Voxema** — never `VOXEMA`, never `voxema`.

### Wordmark Variants

| Variant | Background | Mark strokes |
|---|---|---|
| Primary horizontal | `#0a0e14` Ink | white + blue arcs |
| Vertical stacked | `#1c1c1e` Night | white + blue arcs |
| Light | `#f2f2f7` Cloud | dark navy + blue arcs |
| On brand color | `#0a84ff` | all white, progressively transparent |

### Minimum Sizes

| Context | Minimum |
|---|---|
| App icon | 16×16px |
| Mark alone | 20×20px |
| Wordmark horizontal | 120px wide |
| Wordmark vertical | 80px wide |

---

## Color System

### Primary Palette

| Token | Hex | Role |
|---|---|---|
| `vox-blue` | `#0a84ff` | Primary accent, CTAs, active states, links |
| `vox-blue-light` | `#40a0ff` | Hover state, focus ring |
| `vox-blue-glow` | `rgba(10,132,255,0.18)` | Active background tint |
| `ink` | `#0a0e14` | Deepest background, icon bg |
| `ink-soft` | `#0f1923` | App icon bg, hero sections |
| `night` | `#1c1c1e` | App window background (dark mode) |
| `surface` | `#2c2c2e` | Cards, panels, sidebars (dark mode) |
| `surface-raised` | `#3a3a3c` | Elevated cards, selected rows (dark mode) |
| `muted` | `#48484a` | Disabled, placeholder backgrounds |
| `cloud` | `#f2f2f7` | App window background (light mode) |
| `cloud-surface` | `#ffffff` | Cards, panels (light mode) |

### Semantic Colors

| Token | Hex | Role |
|---|---|---|
| `rec-red` | `#e53e3e` | **Recording state only** + destructive actions |
| `ok-green` | `#30d158` | Success, permission granted, checkmarks |
| `caution` | `#ffd60a` | Warning, pending permission |

### Color Rules

1. `vox-blue` (`#0a84ff`) is the only blue in the product — never mix with other blues.
2. `rec-red` (`#e53e3e`) is reserved exclusively for the active recording indicator and destructive actions. Never decorative.
3. Use semantic colors only for their defined semantic meaning.

### Text Colors (Dark Mode)

| Usage | Value |
|---|---|
| Primary | `#ebebf5` |
| Secondary | `rgba(235,235,245,0.6)` |
| Tertiary | `rgba(235,235,245,0.3)` |
| Disabled / quaternary | `rgba(235,235,245,0.18)` |

---

## Typography

**Typeface:** `-apple-system, BlinkMacSystemFont, "SF Pro Text"` — always system font. No custom fonts.

| Style | Size | Weight | Letter-spacing | Usage |
|---|---|---|---|---|
| Display | 34px | 800 | −0.5px | Page titles, large states |
| Title 1 | 22–24px | 700 | −0.3px | Section headers |
| Title 2 | 16–18px | 700 | 0 | Card headers, meeting titles |
| Body | 13px | 400 | 0 | Main content, descriptions |
| Label | 11px | 600 | +0.7px | Section labels (UPPERCASE) |
| Caption | 11px | 400 | 0 | Metadata, timestamps |
| Timer | 34px | 100 (ultraLight) | 0 | Recording duration counter |
| Monospace | 11px | 400 | 0 | Timestamps, sizes, codes (SF Mono) |

**Rules:**
- Recording timer uses **ultra-light weight exclusively** — instrumental, precise feel.
- Timestamps and technical values use **SF Mono** with tabular figures.
- Section labels are always **UPPERCASE + letter-spacing 0.7px**.

---

## Spacing System

Base unit: **4px**. All spacing is a multiple of 4.

| Token | Value | Usage |
|---|---|---|
| `xs` | 4px | Icon padding, micro gaps |
| `sm` | 8px | Button vertical padding, tight gaps |
| `md` | 12px | Default component padding |
| `base` | 16px | Standard element gap |
| `lg` | 20–24px | Section gaps, card padding |
| `xl` | 32px | Page section gaps |
| `xxl` | 48px | Large section separators |

Card padding: 14–18px. Page/window margins: 24–32px.

---

## Corner Radii

| Context | Radius |
|---|---|
| Tags, code blocks | 4px |
| Small buttons, input fields | 8px |
| List rows, progress bars | 10px |
| Cards, panels | 12px |
| Windows, modals, sheets | 14px |
| App icon | ≈22.37% of size (superellipse) |
| Badges, pills, chips | 100px (fully rounded) |

---

## UI Component Guidelines

### Buttons

| Type | Style | Usage |
|---|---|---|
| Primary | Blue bg (`#0a84ff`), white text | One per screen — main CTA |
| Record | Red bg (`#e53e3e`), white text | Start/stop recording only |
| Secondary | Surface bg, muted border | Secondary actions |
| Ghost | Transparent, stroke border | Back, tertiary actions |
| Destructive | Transparent bg, red text + border | Delete, irreversible actions |

### Cards

- `border-radius: 12px`, `1px` border at `rgba(255,255,255,0.08)` dark / `rgba(0,0,0,0.08)` light.
- No drop shadows — borders only.
- Active/selected: `vox-blue-glow` background tint + `2px` `vox-blue` border.

### Status Badges

```
● Recording     rec-red    rgba(229,62,62,0.2)
✓ Granted       ok-green   rgba(48,209,88,0.2)
! Required      caution    rgba(255,214,10,0.15)
Waiting         muted      #48484a
✦ Recommended   vox-blue   rgba(10,132,255,0.2)
```

---

## Voice & Tone

### Personality

Precision tool, not a friendly assistant. Language is concise, specific, action-oriented. Privacy stated as fact, never marketed.

### Examples

| Context | ✓ Write | ✗ Don't write |
|---|---|---|
| Completion | "Meeting ready" | "🎉 Your summary is ready!" |
| Technical | "whisper-medium · 769 MB" | "Downloading your AI model..." |
| Privacy | "Audio never leaves your device." | "We take your privacy seriously." |
| Error | "Screen Recording permission required. Open System Settings → Privacy." | "Oops! Something went wrong 😅" |
| Destructive | "Permanently delete this meeting?" | "Are you sure? This can't be undone!" |

### Rules

- No emoji in functional UI (buttons, alerts, status messages).
- No ellipsis `...` in button labels. Use `…` (Unicode) in status text only.
- "Meeting" not "session", "recording" not "capture", "summary" not "digest".

---

## Motion

- Duration: **100–250ms**. No decorative animation.
- Recording pulse: scale 1.0→1.08→1.0, 2s cycle, `ease-in-out`.
- State transitions: `easeInOut`.
- Animation must communicate state change — never entertain.

---

## Iconography

**SF Symbols exclusively.** No third-party icon libraries.

| Concept | SF Symbol |
|---|---|
| Microphone | `mic`, `mic.fill` |
| System audio | `waveform`, `speaker.wave.2` |
| Meeting / document | `doc.text` |
| Recording active | `stop.fill`, `record.circle` |
| Processing | `clock`, `hourglass` |
| Summary | `doc.text.magnifyingglass` |
| Export Markdown | `doc.text` |
| Export JSON | `curlybraces` |
| Search | `magnifyingglass` |
| Settings | `gearshape` |
| Rename | `pencil` |
| Delete | `trash` |
| Permissions | `lock.shield`, `checkmark.circle` |
| Timer | `timer` |
| Speaker identification | `person.2` |

---

## Do's and Don'ts

| ✓ Do | ✗ Don't |
|---|---|
| Use `#0a84ff` as the single blue | Mix Voxema Blue with other blues |
| Reserve `#e53e3e` for recording + destructive | Use red decoratively |
| Use system SF Pro font | Import custom typefaces |
| Use SF Symbols exclusively | Use third-party icon sets |
| One primary CTA per screen | Stack multiple primary buttons |
| State privacy as fact | Market privacy as a feature |
| Keep animations under 250ms | Add decorative motion |
| Use 4px-multiple spacing | Use arbitrary spacing values |
| Wordmark: "Voxema" | "VOXEMA", "voxema" |
| `stroke-linecap: round` on all mark paths | Square or butt stroke caps on the mark |
