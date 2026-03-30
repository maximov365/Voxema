# Voxema — Brand Identity Guide

**Version:** 1.0  
**Status:** Approved  
**Owner:** Iteration Manager  
**Visual reference:** `docs/designs/BRAND-guide.html`  
**Icon concepts:** `docs/designs/` (voxema-icon-v1 through v3, voxema-icon-final)

---

## Brand Essence

**Name:** Voxema  
**Origin:** "Vox" (Latin: voice) + "ema" (schema/emblem suffix)  
**Tagline:** *Your meetings. Your data. Your device.*  
**Positioning:** Privacy-first meeting intelligence for macOS professionals.

---

## Logo & Mark

### Primary Mark — The V Waveform

The Voxema mark is a **V formed from audio equalizer bars**. Each leg of the V is constructed from stacked rectangular segments that graduate in color from white at the top to Voxema Blue at the vertex bottom.

**Meaning encoded:**
- **V** — the initial letter and brand monogram
- **Waveform bars** — the visual language of audio capture and analysis
- **Converging V** — two channels (system audio + microphone) meeting in a single intelligence pipeline

### App Icon

- Shape: macOS superellipse rounded square (`corner-radius ≈ 22.37%` of side)
- Background: Ink (`#0a0e14`) — deep near-black navy
- Mark: V waveform, white-to-blue gradient, subtle inner glow

### Menu Bar Icon

- Same V-waveform mark as PDF/SVG template image
- **Idle state:** white/blue bars
- **Recording state:** bars switch to Record Red (`#e53e3e`)
- Fallback SF Symbol: `mic.fill` (idle) / `mic.fill` with tint (recording)

### Wordmark

Font: **-apple-system SF Pro Display, 800 weight, letter-spacing -0.8px**  
Name: `Voxema` — always title case, never all caps, never all lowercase.

### Logo Variants

| Variant | Background | Mark color |
|---|---|---|
| Primary dark | `#0a0e14` (Ink) | White → Blue gradient |
| On night | `#1c1c1e` (Night) | White → Blue gradient |
| Light | `#f2f2f7` (Cloud) | Dark navy → Blue gradient |
| On brand color | `#0a84ff` | White, progressively transparent |
| Menu bar | System (macOS template) | White/blue or red |

### Minimum Sizes

| Context | Minimum size |
|---|---|
| App icon | 16×16px |
| Wordmark horizontal | 120px wide |
| Wordmark vertical | 80px wide |
| Standalone mark | 20×20px |

---

## Color System

### Primary Palette

| Token | Hex | Role |
|---|---|---|
| `vox-blue` | `#0a84ff` | Primary accent, CTAs, active states, links |
| `vox-blue-light` | `#40a0ff` | Hover, focus ring |
| `vox-blue-glow` | `rgba(10,132,255,0.18)` | Active background tint |
| `ink` | `#0a0e14` | Deepest background, icon bg |
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

**Color Rules:**
1. `vox-blue` is the only blue in the product — never mix with other blues.
2. `rec-red` is reserved exclusively for the active recording indicator and destructive actions. Never use it decoratively.
3. Use semantic colors only for their defined semantic meaning.

### Text Colors (Dark Mode)

| Usage | Value |
|---|---|
| Primary text | `#ebebf5` |
| Secondary text | `rgba(235,235,245,0.6)` |
| Tertiary text | `rgba(235,235,245,0.3)` |
| Quaternary / disabled | `rgba(235,235,245,0.18)` |

---

## Typography

**Typeface:** `-apple-system, BlinkMacSystemFont, "SF Pro Text"` — always use the system font. No custom fonts.

| Style | Size | Weight | Letter-spacing | Usage |
|---|---|---|---|---|
| Display | 34px | 800 | -0.5px | Page titles, large states |
| Title 1 | 22–24px | 700 | -0.3px | Section headers |
| Title 2 | 16–18px | 700 | 0 | Card headers, meeting titles |
| Body | 13px | 400 | 0 | Main content, descriptions |
| Label | 11px | 600 | 0.7px | Section labels (UPPERCASE) |
| Caption | 11px | 400 | 0 | Metadata, timestamps |
| Timer | 34px | 100 (ultraLight) | 0 | Recording duration counter |
| Monospace | 11px | 400 | 0 | Timestamps, file sizes, codes |

**Rules:**
- The recording timer uses **ultra-light weight** exclusively — it gives a precise, instrumental feel.
- All timestamps use **SF Mono** (monospace) with tabular figures.
- Section labels are always **uppercase + letter-spacing 0.7px**.

---

## Spacing System

Base unit: **4px**. All spacing is a multiple of 4.

| Token | Value | Usage |
|---|---|---|
| `xs` | 4px | Icon padding, micro gaps |
| `sm` | 8px | Button padding vertical, tight gaps |
| `md` | 12px | Default component padding |
| `base` | 16px | Standard element gap |
| `lg` | 20–24px | Section gaps, card padding |
| `xl` | 32px | Page section gaps |
| `xxl` | 48px | Large section separators |

**Content padding inside cards:** 14–18px  
**Page/window margins:** 24–32px

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
| Badges, pills, chips | `100px` (fully rounded) |

---

## UI Component Guidelines

### Buttons

| Type | Style | Usage |
|---|---|---|
| Primary | Blue bg, white text | Main CTA per screen |
| Record | Red bg, white text | Start/stop recording **only** |
| Secondary | Surface bg, muted border | Secondary actions |
| Ghost | Transparent | Back navigation, tertiary actions |
| Destructive | Surface bg, red text | Delete, irreversible actions |

- Only **one primary button** per screen/modal.
- The Record button (`#e53e3e`) is used **only** for recording actions — never repurposed.

### Cards & Surfaces

- Cards use `border-radius: 12px` and a `1px` border at `rgba(255,255,255,0.08)` (dark) or `rgba(0,0,0,0.08)` (light).
- No drop shadows on cards — use borders only.
- Active/selected cards use `vox-blue-glow` background tint + `2px` `vox-blue` border.

### Progress & Download

- Progress bars: `6px` height, `border-radius: 3px`, blue fill.
- Download bars change fill color to green on completion.
- Always show: percentage, transferred amount, and estimated time remaining.

### Status Badges

```
● Recording      rec-red     Background: rgba(229,62,62,0.2)
✓ Granted        ok-green    Background: rgba(48,209,88,0.2)
Not granted      caution     Background: rgba(255,214,10,0.15)
Waiting          muted       Background: var(--muted)
Recommended ✦   vox-blue    Background: vox-blue-glow
```

---

## Voice & Tone

### Personality

Voxema talks like a **precision tool, not a friendly assistant**. Language is:
- **Concise** — say exactly what happened, nothing more
- **Specific** — name the thing (model, file, permission), never vague
- **Action-oriented** — tell the user what to do next
- **Privacy-matter-of-fact** — state privacy properties plainly, don't market them

### Writing Examples

| Context | ✓ Write | ✗ Don't write |
|---|---|---|
| Completion | "Meeting ready" | "🎉 Your meeting summary is ready!" |
| Technical | "whisper-medium · 769 MB" | "Downloading your AI model..." |
| Privacy | "Audio never leaves your device." | "We take your privacy seriously." |
| Error | "Screen Recording permission required. Open System Settings → Privacy." | "Oops! Something went wrong 😅" |
| Destructive | "Permanently delete this meeting?" | "Are you sure? This can't be undone!" |
| Processing | "Transcription · Speaker identification · Summary" | "Crunching the numbers for you..." |

### Rules

- No emoji in functional UI (buttons, alerts, status). Emoji allowed only in onboarding illustrations.
- No ellipsis `...` in button labels. Use `…` (Unicode ellipsis) in status text only.
- Capitalise the first word only in sentences and labels. No Title Case for body text.
- "Meeting" not "session", "recording" not "capture", "summary" not "digest".

---

## Motion & Animation

- Keep animations **short** (100–250ms) and **purposeful**.
- Use `easeInOut` for state transitions.
- Recording indicator: **pulse animation**, 2s cycle, scale 1.0→1.08→1.0, `ease-in-out`.
- Channel pills: **subtle continuous pulse** during active recording.
- No decorative animations. Animation must communicate state change, never entertain.

---

## Iconography

Use **SF Symbols** exclusively. Never use third-party icon libraries.

| Concept | SF Symbol |
|---|---|
| Microphone | `mic`, `mic.fill` |
| System audio / broadcast | `waveform`, `speaker.wave.2` |
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
| Calendar | `calendar` |
| Timer | `timer` |
| Speaker | `person.2` |

---

## Do's and Don'ts

| ✓ Do | ✗ Don't |
|---|---|
| Use `#0a84ff` as the single blue | Mix Voxema Blue with other blues |
| Reserve `#e53e3e` for recording + destructive | Use red decoratively |
| Use SF Pro system font | Import custom typefaces |
| Use SF Symbols for icons | Use third-party icon sets |
| One primary CTA per screen | Stack multiple primary buttons |
| State privacy as fact | Market privacy as a feature |
| Keep animations under 250ms | Add decorative motion |
| Use 4px-multiple spacing | Use arbitrary spacing values |
| Wordmark: "Voxema" | "VOXEMA", "voxema" |
