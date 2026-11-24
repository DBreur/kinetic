---
name: Kinetic
colors:
  surface: '#f8f9ff'
  surface-dim: '#cbdbf5'
  surface-bright: '#f8f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#eff4ff'
  surface-container: '#e5eeff'
  surface-container-high: '#dce9ff'
  surface-container-highest: '#d3e4fe'
  on-surface: '#0b1c30'
  on-surface-variant: '#3d4947'
  inverse-surface: '#213145'
  inverse-on-surface: '#eaf1ff'
  outline: '#6d7a77'
  outline-variant: '#bcc9c6'
  surface-tint: '#006a61'
  primary: '#00685f'
  on-primary: '#ffffff'
  primary-container: '#008378'
  on-primary-container: '#f4fffc'
  inverse-primary: '#6bd8cb'
  secondary: '#006b5f'
  on-secondary: '#ffffff'
  secondary-container: '#6df5e1'
  on-secondary-container: '#006f64'
  tertiary: '#545c72'
  on-tertiary: '#ffffff'
  tertiary-container: '#6c748b'
  on-tertiary-container: '#fefcff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#89f5e7'
  primary-fixed-dim: '#6bd8cb'
  on-primary-fixed: '#00201d'
  on-primary-fixed-variant: '#005049'
  secondary-fixed: '#71f8e4'
  secondary-fixed-dim: '#4fdbc8'
  on-secondary-fixed: '#00201c'
  on-secondary-fixed-variant: '#005048'
  tertiary-fixed: '#dae2fd'
  tertiary-fixed-dim: '#bec6e0'
  on-tertiary-fixed: '#131b2e'
  on-tertiary-fixed-variant: '#3f465c'
  background: '#f8f9ff'
  on-background: '#0b1c30'
  surface-variant: '#d3e4fe'
typography:
  display-timer:
    fontFamily: Inter
    fontSize: 56px
    fontWeight: '700'
    lineHeight: 60px
    letterSpacing: -0.04em
  display-glucose:
    fontFamily: Inter
    fontSize: 44px
    fontWeight: '600'
    lineHeight: 48px
    letterSpacing: -0.03em
  headline-lg:
    fontFamily: Inter
    fontSize: 30px
    fontWeight: '600'
    lineHeight: 36px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Inter
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.015em
  headline-sm:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.05em
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
    letterSpacing: 0.04em
  metric-unit:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.02em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  margin: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

This design system establishes an exacting, clinical-athletic aesthetic tailored for high-intensity martial artists—specifically addressing the intersection of combat conditioning (BJJ, Judo, Sambo, Wrestling, Boxing, MMA) and metabolic health management.

The brand ethos prioritizes absolute calm under physical duress. When an athlete checks their metrics between rounds or during blood sugar excursions, cognitive overhead must approach zero. The interface rejects standard athletic app tropes—hyperbolic neon glows, aggressive skeuomorphism, and gamified clutter—in favor of a precision medical-grade instrument.

### Design Principles
- **Clinical Serenity:** High-key neutral surfaces, deliberate whitespace, and minimal chromatic activation create a tranquil, focused headspace during training sessions.
- **Instant Glanceability:** Glucose reads, active rest countdowns, and round structures are communicated through decisive numeric typography and explicit spatial hierarchies that can be parsed across a gym mat in under a second.
- **Dual-State Accessibility:** Semantic status indicators never rely solely on color. Every clinical condition (in-range, hyper, hypo) binds an accessible icon, typographic label, and color cue.
- **Restraint Over Decoration:** Zero non-functional gradients, decorative drop shadows, or background illustrations. Every hairline border and surface tier serves pure operational structure.

## Colors

The palette leverages a pristine light foundation punctuated by deliberate, targeted teal accents and vital medical signals.

### Color Tokens & Usage
- **Primary (`#0D9488`) & Primary Light (`#14B8A6`):** Reserved for primary interactive triggers, active session states, selected navigation targets, and progress completion rings.
- **Backgrounds & Canvas:**
  - Base Canvas: `#FFFFFF`
  - Subtle Surface / Track Background: `#F8FAFC`
  - Inset Surface / Muted Container: `#F1F5F9`
  - Hairline Borders: `#E2E8F0`
- **Text & Content:**
  - Primary Readout / Headings: `#0F172A` (Deep Slate)
  - Secondary / Supporting Metric: `#64748B` (Muted Slate)
  - Tertiary / Inactive Controls: `#94A3B8`
- **Metabolic Status Indicators (Strict Semantic Pairings):**
  - **In-Range Target:** `#10B981` paired with neutral background tints (`#ECFDF5`).
  - **Elevated / High:** `#F59E0B` paired with cautionary amber tints (`#FFFBEB`).
  - **Critical / Low:** `#EF4444` paired with alert red tints (`#FEF2F2`).

Every semantic state must be accompanied by explicit text labels (e.g., "IN RANGE", "HIGH", "RAPID DROP") to maintain complete clarity under physical exhaustion or visual impairment.

## Typography

Typography is built on `Inter`, taking full advantage of tabular lining figures (`font-variant-numeric: tabular-nums`) for numeric stability in live clocks, round counters, and continuous glucose trend readouts.

### Hierarchy & Metric Rules
- **Live Numbers (`display-timer`, `display-glucose`):** Bold, tightly tracked, and set with zero line wiggle when fluctuating. Always position secondary metric units (`mg/dL`, `mmol/L`, `min/sec`) baseline-aligned or immediately stacked beneath the primary glyph.
- **Section Headers:** Clean, medium-to-semibold weights that demarcate interval blocks and biological vitals without overwhelming card boundaries.
- **Semantic Labels:** Small caps/tracked uppercase (`0.04em - 0.05em`) strictly applied to status tags, round phases ("WORK", "REST", "DRILL"), and sensor health flags.

## Layout & Spacing

The layout is constructed for single-column mobile viewports, maintaining a strict density ceiling: **never display more than 3 to 4 modular cards per screen**.

### Structural Grid & Safe Zones
- **Margins & Gutter:** Base canvas margins are locked at `1rem` (16px), scaling to `1.25rem` on larger mobile flagships.
- **Information Architecture:** Stacked vertical list structure. Vertical rhythm between cards is maintained uniformly with `space-md` (16px) or `space-lg` (24px).
- **Physical Touch Targets:** All interactive triggers (stop/start buttons, drill selectors, tag pills) adhere to a minimum boundary of 48×48px to permit accurate input through sweaty fingers or wrapped hands.
- **Paddings:** Card interior spacing uses `space-lg` (24px) on primary metrics and `space-md` (16px) on secondary summary cards.

## Elevation & Depth

This design system avoids ambient drop shadows, blurred glows, and faux-3D skeuomorphic treatments. Depth is achieved via **tonal structural layering** and **refined 1px hairline borders**.

### Layering Rules
- **Canvas Base (Level 0):** Pure `#FFFFFF` or pale slate `#F8FAFC`.
- **Card Containers (Level 1):** Solid `#FFFFFF` enclosed in a 1px border of `#E2E8F0`. 
- **Inset Metric Wells (Level 2):** Subtle indented blocks set to `#F1F5F9` inside parent cards to frame secondary stats (e.g., heart rate reserve, round duration).
- **Active Sheet / Modal:** Solid `#FFFFFF` with an ultralight rim (`#CBD5E1`) and a discrete 10% black scrim. No directional floating shadow.

## Shapes

The design system embraces an approachable yet disciplined curvature index based on level `2` (Rounded).

### Geometry Standards
- **Containers & Primary Cards:** Styled with `rounded-2xl` (`1rem` to `1.5rem` / 16px to 24px) to balance modern hand-feel with content density.
- **Buttons & Interactive Cells:** Styled with `rounded-xl` (`0.75rem` / 12px) for tactical touch responsiveness.
- **Tags, Metric Pills, & Chips:** Fully pill-shaped or constrained to `rounded-lg` (`0.5rem` / 8px) for discrete status indicators.
- **Divider Hairlines:** 1px width, strictly horizontal or vertical, terminating cleanly with container insets.

## Components

### Buttons & Quick Triggers
- **Primary CTA (Session Active / Log Entry):** Solid `#0D9488` fill, crisp `#FFFFFF` text, `rounded-xl`, height 52px. Active press state shifts to `#0F766E` with an imperceptible 0.98 scale transform.
- **Secondary / Rest Action:** Neutral light surface (`#F1F5F9`), `#0F172A` typography, hairline border (`#E2E8F0`).
- **Critical Trigger (Emergency Fast Sugar / Low Stop):** Solid `#EF4444` fill, white typography, minimum height 56px, high contrast.

### Metabolic & Interval Cards
- **Structure:** `rounded-2xl`, background `#FFFFFF`, border 1px `#E2E8F0`, padding `1.5rem`.
- **Numeric Display:** Tabular layout with glucose unit (`mg/dL`) rendered in muted text right of the integer. 
- **Trend Vector:** Simple 2px stroke geometric line arrow indicating glucose velocity (flat, climbing, dropping rapidly).

### Metric Chips & Status Indicators
- **In-Range Pill:** Background `#ECFDF5`, text `#065F46`, paired with a solid dot or clear geometric icon.
- **Caution / Out-of-Range Pills:** Yellow/red backgrounds with high-contrast text (`#92400E` on `#FEF3C7`, `#991B1B` on `#FEE2E2`).
- **Discipline Tag:** Small uppercase pill tag (`BJJ`, `JUDO`, `DRILLS`) in `#F1F5F9` with `#475569` text.

### Inputs & Interval Controls
- **Numeric Fields:** Large format inputs with centered or right-aligned tabular numerals. Underline or subtle boxed state in `#E2E8F0`, transitioning to `#0D9488` upon focus.
- **Segmented Controls:** Enclosed in a single `#F1F5F9` track. Active thumb is pure `#FFFFFF` with a 1px hairline border and `#0F172A` text.