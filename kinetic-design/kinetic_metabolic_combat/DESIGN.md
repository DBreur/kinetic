---
name: Kinetic Metabolic Combat
colors:
  surface: '#101419'
  surface-dim: '#101419'
  surface-bright: '#36393f'
  surface-container-lowest: '#0a0e13'
  surface-container-low: '#181c21'
  surface-container: '#1c2025'
  surface-container-high: '#262a30'
  surface-container-highest: '#31353b'
  on-surface: '#e0e2ea'
  on-surface-variant: '#bbcac6'
  inverse-surface: '#e0e2ea'
  inverse-on-surface: '#2d3136'
  outline: '#859490'
  outline-variant: '#3c4947'
  surface-tint: '#4fdbc8'
  primary: '#4fdbc8'
  on-primary: '#003731'
  primary-container: '#14b8a6'
  on-primary-container: '#00423b'
  inverse-primary: '#006b5f'
  secondary: '#44e2cd'
  on-secondary: '#003731'
  secondary-container: '#03c6b2'
  on-secondary-container: '#004d44'
  tertiary: '#4edea3'
  on-tertiary: '#003824'
  tertiary-container: '#16bb83'
  on-tertiary-container: '#00442c'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#71f8e4'
  primary-fixed-dim: '#4fdbc8'
  on-primary-fixed: '#00201c'
  on-primary-fixed-variant: '#005048'
  secondary-fixed: '#62fae3'
  secondary-fixed-dim: '#3cddc7'
  on-secondary-fixed: '#00201c'
  on-secondary-fixed-variant: '#005047'
  tertiary-fixed: '#6ffbbe'
  tertiary-fixed-dim: '#4edea3'
  on-tertiary-fixed: '#002113'
  on-tertiary-fixed-variant: '#005236'
  background: '#101419'
  on-background: '#e0e2ea'
  surface-variant: '#31353b'
typography:
  display-lg:
    fontFamily: Inter
    fontSize: 40px
    fontWeight: '700'
    lineHeight: 48px
    letterSpacing: -0.02em
  display-lg-mobile:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 36px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Inter
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: '0'
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: '0'
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: '0'
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
    letterSpacing: 0.01em
  label-lg:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.02em
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.03em
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.04em
  metric-numeral:
    fontFamily: Inter
    fontSize: 44px
    fontWeight: '700'
    lineHeight: 48px
    letterSpacing: -0.03em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-desktop: 1.5rem
  margin: 1rem
  margin-tablet: 1.5rem
  margin-desktop: 2rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

This design system serves athletes managing diabetes while training in high-output combat sports. The brand personality balances precision clinical telemetry with stripped-down athletic resilience. The interface projects high readiness, unwavering stability, and calm under physiological strain.

The design movement is Corporate / Modern infused with strict Athletic Functionalism:
- High contrast, dark-adapted utility engineered for glanceability during intensive sessions.
- Zero decorative gradients, drop glows, or non-essential visual noise.
- Every color, stroke, and boundary corresponds to actionable biometric telemetry or structural navigation.
- Grounded, tactical ergonomics designed to eliminate cognitive friction when blood sugar fluctuates or physical exertion peaks.

## Colors

The palette employs a deep, layered dark neutral base paired with a focused teal accent system and strict clinical status signifiers.

### Palette Architecture
- **Canvas Base:** `#0b0f14` (Deep canvas, reduces OLED battery drain and visual strain).
- **Surface Level 1:** `#121820` (Primary container background for modules and training blocks).
- **Surface Level 2:** `#1c2430` (Interactive cards, active states, nested panels).
- **Surface Stroke:** `#283546` (Subtle boundary definition for structural isolation).
- **Primary Accent:** `#14b8a6` (Primary action hooks, standard telemetry markers, focus rings).
- **Secondary Accent:** `#2dd4bf` (Active metric values, highlights, peak performance tracking).

### Typography Contrast
- **Primary Text:** `#f1f5f9` (Maximum contrast readability for rapid glances).
- **Secondary / Meta Text:** `#94a3b8` (Timestamps, units, inactive labels).
- **Disabled / Tertiary Text:** `#475569` (Inactive or de-prioritized information).

### Clinical Telemetry Roles
- **Target In-Range (Normative):** `#10b981` (Glucose stable, recovery threshold met).
- **Elevated / Caution:** `#f59e0b` (Pre-workout spike, trending above target threshold).
- **Critical Alert / Hypo Event:** `#ef4444` (Immediate action required, severe drop threshold).

No color is applied purely for decoration; color strictly signifies state, delta, or navigational focus.

## Typography

Inter is deployed uniformly across headlines, technical data displays, and body copy to enforce mechanical rigor and immediate recognition. 

### Type Directives
- **Metric Numerals:** Large-format figures (e.g., real-time CGM glucose numbers, round clocks) utilize `metric-numeral` set with tabular numerals (`tnum`) to eliminate layout jitter when real-time biometric figures change rapidly.
- **Labels & Units:** Units (mg/dL, mmol/L, BPM) use `label-sm` or `label-md` with slight tracking expansions (`0.03em` to `0.04em`) to maintain legibility when paired against heavy tabular figures.
- **Headlines:** Display titles are kept tight, crisp, and left-aligned. Avoid center alignment for athletic dashboard reading paths.

## Layout & Spacing

The system runs on a 4px modular grid, built around high-density data requirements and quick-tap targets essential when wearing wraps or boxing gloves.

### Layout System
- **Mobile (< 768px):** 4-column fluid layout with `1rem` margins and `1rem` gutters. Metric readouts stack vertically with persistent status pinned to top-level viewing zones.
- **Tablet (768px - 1024px):** 8-column layout with `1.5rem` margins and `1rem` gutters. Accommodates two-up metric cards and split drill schedules.
- **Desktop (>= 1024px):** 12-column layout with `2rem` margins, `1.5rem` gutters, and a maximum content width capped at `1280px` to maintain strict peripheral focus.

### Spacing Principles
- Compact vertical rhythms preserve dashboard density: use `space-sm` between label and value, `space-md` inside cards, and `space-lg` to separate discrete analytical blocks.
- Interactive elements must maintain an absolute minimum touch zone of `48px x 48px`, regardless of internal label size.

## Elevation & Depth

This design system avoids all diffuse, atmospheric drop shadows and decorative blurs. Visual separation is achieved strictly through tonal surfaces and structural low-contrast borders.

### Elevation Hierarchy
- **Canvas (`#0b0f14`):** Base underlying viewport; neutral void.
- **Base Surface (`#121820`):** First-tier containers (dashboard cards, data graphs, training lists). Bound with a 1px solid stroke of `#283546`.
- **Raised Interactive Layer (`#1c2430`):** Selectable rows, segmented toggle pills, active metrics, and modal dialogs.
- **Overlay & Alert Containers:** Layered over `#0b0f14` at 90% opacity (no blur) with a 1px border colored according to alert status (e.g., `#ef4444` for acute low alarms).

Depth is engineered to look milled and planar—like the display panel of a dedicated sports telemetry instrument.

## Shapes

The design system standardizes on `roundedness: 2`, delivering a reliable, engineered curvature that softens the structural grid without sacrificing density.

### Radius Scale
- **Base Components (`0.5rem` / `8px`):** Standard buttons, text input fields, segmented bar items, biometric chips.
- **Container Elements (`1rem` / `16px`):** Primary training cards, CGM graph containers, round summary cards.
- **Sheet & Dialog Boundaries (`1.5rem` / `24px`):** Drill completion modals, full telemetry sheets.
- **Full Radius (Pill):** Dedicated status indicators and live timers only.

## Components

### Buttons
- **Primary:** Solid `#14b8a6` background with `#0b0f14` bold typography. Hover/active shifts to `#2dd4bf`. Minimal 48px height.
- **Secondary:** Surface `#1c2430` background, 1px `#283546` border, `#f1f5f9` text. On interaction, border shifts to `#14b8a6`.
- **Danger (Urgent Action):** `#ef4444` background, `#f1f5f9` text, used exclusively for session stops or hypoglycemia protocol confirmations.

### Cards & Panels
- Background: `#121820`.
- Border: 1px uniform solid `#283546`.
- Padding: `space-md` (16px) or `space-lg` (24px) for primary drill telemetry.
- Header: Left-aligned `headline-sm` with right-aligned status chip.
- Content: Direct integration of tabular data; zero nested gradient backgrounds.

### Chips & Telemetry Pills
- Background: `#1c2430`.
- Border: 1px solid `#283546`.
- Height: 28px standard, 36px in training mode.
- Status Indicator: 6px solid dot prefixed before label (`#10b981` stable, `#f59e0b` shifting, `#ef4444` critical).

### Input Fields
- Container: `#0b0f14` inset background with `#283546` border and 8px corner radius.
- Text: `#f1f5f9` (`body-md`), with `#475569` placeholder text.
- Focus: 1px crisp outline in `#14b8a6`. No halo glow.

### Checkboxes & Segmented Controls
- Unchecked/Inactive: `#1c2430` surface with `#283546` border.
- Checked/Active: `#14b8a6` fill with `#0b0f14` iconography.
- Segmented switches fit flush inside a `#0b0f14` gutter container with 8px radius.

### Specialized Component: Glucose & Heart-Rate Telemetry Card
- Top Section: Current numerical reading (`metric-numeral`) accompanied by trend vector icon (straight, diagonal, vertical) in the status color.
- Middle Section: Linear 24-point step line graph using 2px stroke width, plotting current blood glucose against pre-set safe athletic zones (80-180 mg/dL).
- Bottom Section: Session timestamp, current round, and rapid insulin-on-board (IOB) metric.