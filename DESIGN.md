---
name: Symphonia Homepage
version: 1.0.0
description: "Marketing landing page for Symphonia — a spec-to-agent workspace that turns repository-connected specs into planned, executed, and reviewed code."

# ─── Palette ────────────────────────────────────────────────────────
colors:
  # Brand
  primary: "#0070d7"
  primary-hover: "#005fbb"
  accent: "#f81ce5"
  accent-soft: "rgba(248, 28, 229, 0.10)"
  accent-text: "#9f118f"

  # Surfaces
  page: "#f7f5ef"
  card: "#fefefe"
  card-alt: "#fbfaf7"
  warm-bg: "#fffdf8"
  white: "#ffffff"
  black: "#000000"

  # Text
  heading: "#000000"
  body: "#27251f"
  body-secondary: "#37352f"
  body-muted: "#5f5c55"
  body-subtle: "#6a6861"
  body-faint: "#8c8780"
  body-ghost: "#77746c"
  hero-subtext: "#36342f"
  hero-muted: "#6a6861"
  cta-sub: "#aaa7a0"

  # Borders
  border-default: "#e6e0d7"
  border-card: "#ebe6de"
  border-card-outer: "rgba(61, 59, 53, 0.16)"
  border-footer: "#e1dbd2"
  border-input: "#ded8cf"

  # Semantic
  success-bg: "#e9f6ef"
  success-text: "#168b4a"

  # Hero decorative
  doodle-stroke: "#5a5a5a"
  dot-neutral: "#d9d9d9"

# ─── Typography ─────────────────────────────────────────────────────
typography:
  font-sans: "Inter, system-ui, -apple-system, sans-serif"
  font-serif: "Georgia, 'Times New Roman', serif"

  display-hero:
    fontSize: "72px"
    fontWeight: 700
    lineHeight: 0.96
    letterSpacing: "-0.045em"
    mobile-fontSize: "46px"

  display-section:
    fontSize: "58px"
    fontWeight: 700
    lineHeight: 1.02
    letterSpacing: "-0.045em"
    mobile-fontSize: "40px"

  display-card:
    fontSize: "46px"
    fontWeight: 700
    lineHeight: 1.02
    letterSpacing: "-0.04em"
    mobile-fontSize: "34px"

  heading-cta:
    fontSize: "64px"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "-0.045em"
    mobile-fontSize: "42px"

  heading-lg:
    fontSize: "32px"
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-0.04em"

  heading-card:
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-0.04em"

  heading-md:
    fontSize: "24px"
    fontWeight: 700
    letterSpacing: "-0.035em"

  hero-subheading:
    fontSize: "26px"
    fontWeight: 600
    lineHeight: 1.18
    letterSpacing: "-0.03em"
    mobile-fontSize: "22px"

  body-lg:
    fontSize: "18px"
    fontWeight: 400
    lineHeight: "28px"

  body-md:
    fontSize: "17px"
    fontWeight: 400
    lineHeight: "28px"

  body-base:
    fontSize: "16px"
    fontWeight: 400
    lineHeight: "28px"

  body-sm:
    fontSize: "15px"
    fontWeight: 400
    lineHeight: "24px"

  body-xs:
    fontSize: "14px"
    fontWeight: 400
    lineHeight: "24px"

  label:
    fontSize: "15px"
    fontWeight: 600

  label-sm:
    fontSize: "13px"
    fontWeight: 600

  caption:
    fontSize: "12px"
    fontWeight: 600
    letterSpacing: "0.14em"
    textTransform: uppercase

  eyebrow:
    fontSize: "15px"
    fontWeight: 600
    letterSpacing: "0.18em"
    textTransform: uppercase

  wordmark:
    fontSize: "28px"
    fontWeight: 900
    fontFamily: serif
    letterSpacing: "-0.06em"

# ─── Spacing ────────────────────────────────────────────────────────
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "32px"
  2xl: "40px"
  section-y: "80px"
  section-y-md: "112px"
  page-x: "20px"

# ─── Layout ─────────────────────────────────────────────────────────
layout:
  max-width-content: "976px"
  max-width-text: "820px"
  max-width-cta: "760px"
  max-width-hero: "1120px"
  max-width-hero-heading: "1020px"
  header-height: "60px"

# ─── Radii ──────────────────────────────────────────────────────────
rounded:
  sm: "8px"
  md: "10px"
  lg: "50%"
  button: "8px"
  card: "10px"
  icon-box: "9px"
  pill: "9999px"

# ─── Elevation ──────────────────────────────────────────────────────
elevation:
  card: "0 1px 1px rgba(0,0,0,0.12), 0 0 0 1px rgba(61,59,53,0.16), 0 3px 9px rgba(61,59,53,0.08)"
  card-hover: "0 1px 1px rgba(0,0,0,0.12), 0 0 0 1px rgba(61,59,53,0.16), 0 12px 28px rgba(61,59,53,0.16)"
  video-window: "0 1px 1px rgba(0,0,0,0.12), 0 0 0 1px rgba(61,59,53,0.16), 0 3px 9px rgba(61,59,53,0.08), 0 18px 60px rgba(0,0,0,0.15)"
  button-inset: "inset 0 0 0 1px rgba(0,0,0,0.08)"
  faq: "0 1px 1px rgba(0,0,0,0.08), 0 0 0 1px rgba(61,59,53,0.12)"
  pill: "0 1px 1px rgba(0,0,0,0.08)"
  accent-ring: "0 0 0 2px rgb(248,28,229), 0 0 0 4px rgba(248,28,229,0.36)"
  glow: "0 0 18px rgba(248,28,229,0.8)"

# ─── Motion ─────────────────────────────────────────────────────────
motion:
  duration-fast: "150ms"
  duration-default: "200ms"
  easing: "ease"
  hover-lift: "translateY(-4px)"
---

## Overview

Symphonia's homepage is a marketing landing page that communicates one core idea: **specs become shipped, reviewed code**. The visual language draws from editorial design — warm parchment surfaces, tight typographic tracking, and deliberate negative space — to feel confident and unhurried rather than "startup flashy."

The page is light-mode only. It uses a single warm cream background (`#f7f5ef`) with pure-white card surfaces, anchored by a bold black hero section and a matching black CTA band near the bottom. The accent color — a vivid magenta (`#f81ce5`) — is used sparingly for emphasis: highlight rings, decorative dashes, and small badges.

### Design Principles

1. **Calm authority** — Large type, generous whitespace, and muted body text let the product speak.
2. **Evidence over promise** — Video windows replace static screenshots; real product footage is embedded inline.
3. **Editorial rhythm** — Alternating section backgrounds (cream → white → cream → black) create natural reading cadence.
4. **Restrained color** — Blue (`#0070d7`) is only for interactive elements. Magenta is decorative. Everything else is neutral.

---

## Colors

### Brand

| Token | Hex | Usage |
|---|---|---|
| `primary` | `#0070d7` | All interactive elements: buttons, CTA links, icon accent tints. |
| `primary-hover` | `#005fbb` | Hover/active state for primary buttons. |
| `accent` | `#f81ce5` | Decorative highlights: hero dashes, highlight rings, badge backgrounds. Never for text on light backgrounds. |
| `accent-soft` | `rgba(248,28,229,0.10)` | Badge/pill background behind accent text. |
| `accent-text` | `#9f118f` | Text rendered on top of `accent-soft` backgrounds. |

### Surfaces

| Token | Hex | Usage |
|---|---|---|
| `page` | `#f7f5ef` | Default page background. Warm cream. |
| `card` | `#fefefe` | Card and panel backgrounds. Nearly white, not pure white. |
| `card-alt` | `#fbfaf7` | Secondary card zones — media wells, video insets. |
| `warm-bg` | `#fffdf8` | Alternate section backgrounds (e.g. Integrations). |
| `white` | `#ffffff` | Header bar, FAQ panel, footer. |
| `black` | `#000000` | Hero section, Final CTA band. |

### Text Hierarchy

Body text uses a warm-gray spectrum instead of pure gray. This keeps the page feeling organic.

- `#000000` — Headings and wordmark only.
- `#27251f` — Page-level body text (main `<body>` color).
- `#37352f` — Navigation links, secondary headings.
- `#5f5c55` — Supporting paragraph text.
- `#6a6861` — Card body copy, captions, descriptions.
- `#8c8780` — Eyebrow labels, video window titles.
- `#77746c` — Integration subtitles.

### On Dark (Hero / CTA sections)

- Heading text: `#ffffff`
- Sub-headline: `#36342f` (intentionally dark-on-dark for a muted pre-heading).
- Body text: `#aaa7a0` (warm off-white for readability without harshness).
- CTA sub-label: `#6a6861`

---

## Typography

**Primary font**: `Inter` via Google Fonts (`--font-sans`), loaded as a variable font.
**Wordmark font**: System `serif` stack (Georgia), used exclusively for the "symphonia*" logotype.

### Scale

| Name | Size | Weight | Tracking | Context |
|---|---|---|---|---|
| `display-hero` | 72 px (46 mobile) | 700 | -0.045em | Hero `<h1>`. One per page. |
| `display-section` | 58 px (40 mobile) | 700 | -0.045em | Section `<h2>` headings. |
| `display-card` | 46 px (34 mobile) | 700 | -0.04em | Large in-card titles (workflow panel). |
| `heading-cta` | 64 px (42 mobile) | 700 | -0.045em | Final CTA band heading. |
| `heading-lg` | 32 px | 700 | -0.04em | Review section heading. |
| `heading-card` | 28 px | 700 | -0.04em | Feature card titles. |
| `heading-md` | 24 px | 700 | -0.035em | Intelligence cards, audience cards. |
| `body-lg` | 18 px | 400 | — | Logo strip description, CTA body. |
| `body-md` | 17 px | 400 | — | Workflow body, integration titles. |
| `body-sm` | 15 px | 400 | — | Card descriptions, button labels, nav links. |
| `body-xs` | 14 px | 400 | — | Footer body, caption text, icon-row body. |
| `eyebrow` | 15 px | 600 | 0.18em | Section eyebrows. All-caps. |
| `caption` | 12 px | 600 | 0.14em | Video window title bars. All-caps. |
| `wordmark` | 28 px | 900 (black) | -0.06em | "symphonia*" logotype. Serif. |

### Rules

- **`text-balance`** is applied to hero and CTA headings to prevent orphans.
- Tracking is always negative on headings (between -0.025em and -0.06em). Never use positive tracking on display type.
- Line heights on headings are compressed (0.96 – 1.05). Body text uses comfortable 24–28 px line heights.

---

## Spacing & Layout

### Grid

The page uses a single-column, center-aligned layout with a max-width of **976 px** for content containers. Text-heavy zones narrow to **820 px**. The hero is wider at **1120 px**.

Horizontal page padding is a flat **20 px** on all breakpoints.

### Section Rhythm

| Breakpoint | Vertical padding |
|---|---|
| Mobile | `py-20` (80 px) |
| Desktop (md+) | `py-28` (112 px) |

### Card Grids

- **Builder section**: 2-col asymmetric — `1.15fr | 0.85fr` on desktop. Stacks on mobile.
- **Workflow panel**: 2-col — `0.9fr | 1.1fr` (text | video). Stacks on mobile.
- **Intelligence / Audience**: 3-col equal on `lg`, stacks on mobile.
- **Integrations**: 3-col on `lg`, 2-col on `sm`, stacks below.
- **FAQ**: Single column, max 820 px.

---

## Components

### Buttons

| Variant | Background | Text | Radius | Height | Padding |
|---|---|---|---|---|---|
| Primary | `#0070d7` | white | 8 px | 36–44 px | 16–20 px horizontal |
| Primary (hover) | `#005fbb` | white | — | — | — |

Buttons include an `inset 0 0 0 1px rgba(0,0,0,0.08)` inner shadow for subtle depth. Arrow icons (`ArrowRight`, 16×16) sit to the right of text with a 2-gap (8 px).

### Cards

All cards share:
- `border-radius: 10px`
- Background: `#fefefe`
- Shadow: `elevation.card`
- No explicit border — the shadow's `0 0 0 1px` ring acts as the border.

**Highlighted card** (feature spotlight): Gets an accent ring instead of the default shadow — `elevation.accent-ring`.

**Hover cards** (audience section): On hover, translate Y by -4 px and swap to `elevation.card-hover`. Transition duration: 200 ms.

### Icon Boxes

Small square containers that hold Lucide icons:
- Size: 44×44 px (`h-11 w-11`) or 36×36 px (`h-9 w-9`).
- Background: `#f7f5ef` (page color, creating a "cut-out" look).
- Icon color: `#0070d7` (primary).
- Border-radius: 9 px.

### Video Windows

Faux-desktop-window frames around embedded `<video>` elements:
- Title bar: 44 px tall, three gray dots (12×12 px, `#d9d9d9`), centered caption in `caption` style.
- Shadow: `elevation.video-window` (deeper than standard cards).
- Video aspect ratios: `16:9` for standard, `4:3` for compact (in-panel).
- Videos auto-play muted, loop, and use `playsInline`.

### Section Title

A centered 2-line block:
1. **Eyebrow** — `eyebrow` style, color `#8c8780`.
2. **Heading** — `display-section` style, `text-balance`, color `#000000`.

Spacing between eyebrow and heading: `mt-3` (12 px).

### FAQ Accordion

- Container: white card with `elevation.faq`, rounded 10 px, divided by `#e1dbd2` lines.
- Uses native `<details>/<summary>` elements.
- Expand icon: 32×32 circle with page-color background and primary-color `ArrowRight` icon. Rotates 45° on open state.

### Badge / Pill

Used for the workflow section tag ("Issue to pull request"):
- Rounded full (pill).
- Background: `accent-soft`.
- Text: `accent-text`, 13 px, semibold.
- Inline icon before text (16×16).

### Check Items (Review section)

- 24×24 circle, background `#e9f6ef`, icon color `#168b4a`.
- Text: 15 px, font-medium.
- Gap: 12 px between circle and text.

---

## Elevation & Depth

The homepage uses **shadow-based elevation** exclusively — no border-based depth.

| Level | Shadow | Used By |
|---|---|---|
| Flat | `0 1px 1px rgba(0,0,0,0.06)` | Integration tiles |
| Card | See `elevation.card` | Most cards |
| Card hover | See `elevation.card-hover` | Audience cards on hover |
| Video | See `elevation.video-window` | Video window frames |
| FAQ | See `elevation.faq` | FAQ accordion |
| Pill | See `elevation.pill` | Logo strip pills |
| Accent ring | See `elevation.accent-ring` | Highlighted feature card |
| Glow | See `elevation.glow` | Hero decorative dashes |

---

## Hero Decorative Elements

The hero section contains hand-drawn-style decorative elements that float behind the content:

- **Doodles**: Rotated pill-shaped outlines with handwritten text ("Ship!", "yes!", "merge"). Border: 5 px solid `#5a5a5a`, italic, 34 px, opacity 0.70. Hidden on mobile.
- **Accent dashes**: Small rounded rectangles in magenta (`#f81ce5`) or white, rotated at various angles. The primary dash has a magenta glow.
- These elements are `pointer-events: none` and purely decorative.

---

## Responsive Behavior

| Breakpoint | Key changes |
|---|---|
| Default (mobile) | Single column. Doodles hidden. Hero heading 46 px. Section padding 80 px. |
| `sm` (640 px) | Login/signup links appear. 2-col integration grid. |
| `md` (768 px) | Nav links appear. Section padding 112 px. Hero heading 72 px. Builder grid activates. |
| `lg` (1024 px) | 3-col grids activate. Workflow panel goes side-by-side. |

---

## Iconography

All icons come from `lucide-react` and are rendered at consistent sizes:
- Standard: 20×20 px (`h-5 w-5`)
- Small: 16×16 px (`h-4 w-4`)
- Inline (buttons/nav): 16×16 px

Icons are never used without adjacent text labels on the homepage.

---

## Do's and Don'ts

### Do
- Use `text-balance` on all display headings to prevent orphans.
- Maintain the warm-gray text hierarchy — never use pure `#808080` or browser-default grays.
- Keep card backgrounds at `#fefefe`, not pure `#ffffff`.
- Use `autoPlay`, `muted`, `loop`, and `playsInline` on all embedded videos.
- Pair every section with an eyebrow + heading via the `SectionTitle` pattern.
- Use the warm cream page background (`#f7f5ef`) for icon box backgrounds to create a see-through effect.

### Don't
- Never use the accent magenta (`#f81ce5`) for interactive elements — it's decorative only. Use `primary` blue for all clickable surfaces.
- Never add gradients to buttons or cards. The visual style is flat with shadow-based elevation.
- Never use more than one `<h1>` — it lives in the hero section.
- Never apply positive letter-spacing to headings. Headings are always tightly tracked.
- Never use border lines on cards — use the `0 0 0 1px` shadow ring from the elevation tokens.
- Don't show navigation doodles or decorative elements on mobile viewports.

---

## Agent Prompt Guide

When generating or modifying homepage UI for Symphonia:

1. **Reference this file first** — all color values, font sizes, and shadows are defined in the YAML front matter. Use them instead of inventing values.
2. **Follow the section pattern** — every content section uses `SectionTitle` (eyebrow + heading), then a card grid or feature panel below.
3. **Card hierarchy** — large feature cards get video wells; medium cards get icon boxes; small cards get heading + body only.
4. **Video treatment** — always wrap video in a `VideoWindow` frame (title bar with dots + caption).
5. **New sections** should alternate between the default `page` background and `warm-bg` or `black` for rhythm.
6. **Buttons** — primary blue with white text, rounded 8 px, with the inset shadow. Always include an arrow icon for CTA buttons.
7. **Test on mobile** — stack everything single-column, hide decorative elements, and reduce heading sizes per the responsive table.
