---
name: Kinetic Sambo Metric
colors:
  surface: '#10141a'
  surface-dim: '#10141a'
  surface-bright: '#353940'
  surface-container-lowest: '#0a0e14'
  surface-container-low: '#181c22'
  surface-container: '#1c2026'
  surface-container-high: '#262a31'
  surface-container-highest: '#31353c'
  on-surface: '#dfe2eb'
  on-surface-variant: '#e3bdbf'
  inverse-surface: '#dfe2eb'
  inverse-on-surface: '#2d3137'
  outline: '#aa888a'
  outline-variant: '#5b4041'
  surface-tint: '#ffb2b7'
  primary: '#ffb2b7'
  on-primary: '#67001b'
  primary-container: '#ff516a'
  on-primary-container: '#5b0017'
  inverse-primary: '#bc0b3b'
  secondary: '#7bd0ff'
  on-secondary: '#00354a'
  secondary-container: '#00a6e0'
  on-secondary-container: '#00374d'
  tertiary: '#b9c8de'
  on-tertiary: '#233143'
  tertiary-container: '#8392a6'
  on-tertiary-container: '#1c2b3c'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#ffdadb'
  primary-fixed-dim: '#ffb2b7'
  on-primary-fixed: '#40000d'
  on-primary-fixed-variant: '#92002a'
  secondary-fixed: '#c4e7ff'
  secondary-fixed-dim: '#7bd0ff'
  on-secondary-fixed: '#001e2c'
  on-secondary-fixed-variant: '#004c69'
  tertiary-fixed: '#d4e4fa'
  tertiary-fixed-dim: '#b9c8de'
  on-tertiary-fixed: '#0d1c2d'
  on-tertiary-fixed-variant: '#39485a'
  background: '#10141a'
  on-background: '#dfe2eb'
  surface-variant: '#31353c'
typography:
  display:
    fontFamily: Space Grotesk
    fontSize: 56px
    fontWeight: '700'
    lineHeight: 64px
    letterSpacing: -0.03em
  headline-lg:
    fontFamily: Space Grotesk
    fontSize: 40px
    fontWeight: '600'
    lineHeight: 48px
    letterSpacing: -0.02em
  headline-lg-mobile:
    fontFamily: Space Grotesk
    fontSize: 30px
    fontWeight: '600'
    lineHeight: 36px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Space Grotesk
    fontSize: 24px
    fontWeight: '500'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Space Grotesk
    fontSize: 18px
    fontWeight: '500'
    lineHeight: 24px
    letterSpacing: '0'
  body-lg:
    fontFamily: Geist
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: '0'
  body-md:
    fontFamily: Geist
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: '0'
  body-sm:
    fontFamily: Geist
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
    letterSpacing: 0.01em
  label-metric:
    fontFamily: Space Grotesk
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.01em
  label-mono:
    fontFamily: Geist
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
    letterSpacing: 0.06em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-tablet: 1.5rem
  gutter-desktop: 2rem
  margin: 1rem
  margin-tablet: 2rem
  margin-desktop: 3rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2.5rem
---

## Brand & Style

This design system establishes an elite combat-science and physiological performance interface. It merges the austere, clinical utility of bio-telemetry instrumentation with the refined composure of modern performance software. Built for high-output combat athletes, sambo practitioners, and sports physiologists, the interface delivers intense telemetry—cardiovascular strain, metabolic flux, and dynamic exertion—without sensory exhaustion.

The aesthetic philosophy is **Tactical Bio-Minimalism**. It operates through strict planar restraint, disciplined negative space, and laser-targeted focal cues. By anchoring data points against deep, non-reflective carbon architecture, the visual environment prioritizes fast tactical orientation, visual calm, and decisive cognitive clarity under physical exertion.

## Colors

The palette balances clinical stillness with hyper-focused physiological feedback across deep low-glare dark surfaces:

- **Primary (`#F43F5E` - Kinetic Coral):** The signal for maximum workload, combat heart-rate zones, anaerobic threshold excursions, and immediate critical actions. Used sparingly to preserve neurological urgency.
- **Secondary (`#38BDF8` - Electric Ice):** The metric for homeostatic stability, metabolic recovery, glucose telemetry, hydration, and parasympathetic baselines.
- **Tertiary (`#94A3B8` - Subdued Slate):** Calibrated for secondary readouts, dimensional axes, metadata values, and structural grid guides.
- **Neutral Base (`#0D1117` - Deep Matte Carbon):** Absorptive zero-reflection backdrop that eliminates optical vibration during intense movement or night recovery.
- **Surface Elevation Layers:**
  - `Surface 1 (#161B22)`: Primary structural cards and metric enclosures.
  - `Surface 2 (#21262D)`: Floating interactive panels, telemetry toggles, and disclosure sheets.
  - `Borders & Rules (#30363D)`: Subdued structural seams separating complex biometric modules.

## Typography

The typographic hierarchy juxtaposes the engineered precision of `Space Grotesk` with the hyper-legible neutrality of `Geist`.

- **Space Grotesk** commands display titles, primary quantitative values, and bio-mechanical telemetry indexes. Its geometric incisions echo precision technical schematics.
- **Geist** manages narrative descriptions, anatomical diagnostics, contextual alerts, and system metadata. Its tall x-height guarantees instant legibility in high-vibration physical settings.
- Numerical values and critical biometric indicators leverage tabular figures (`tnum`) across all instances to prevent layout shifting during real-time data streaming.

## Layout & Spacing

The layout is built upon an 8-point harmonic rhythm framed within a responsive column system:
- **Mobile (<768px):** 4-column layout, 16px margins, 16px gutters. Single-column stacked telemetry modules prioritizing current output and recovery debt.
- **Tablet (768px - 1024px):** 8-column layout, 32px margins, 24px gutters. Dual-pane comparison dividing acute exertion logs from longitudinal trends.
- **Desktop (>1024px):** 12-column layout, 48px margins, 32px gutters. Modular analytical cockpit displaying multiple live sensor inputs simultaneously.

Vertical spacing follows progressive disclosure principles: top-level dashboard overviews maintain comfortable spacing (`space-lg`), while localized biometric readouts compress to tighter cadences (`space-sm` to `space-md`) to form clear perceptual groupings.

## Elevation & Depth

Depth is established via matte planar stratification and micro-luminescent focus states, bypassing ambient shadows entirely:

- **Flat Stratification:** Surfaces achieve verticality through chromatic shifting (`#0D1117` base canvas -> `#161B22` structural module -> `#21262D` elevated interaction layer).
- **Hairline Bounding:** Surfaces are bound by crisp 1px borders colored in `#30363D` (40% to 100% opacity based on focal importance).
- **HUD Glow Effects:** Critical alert cards and peak-exertion widgets use soft targeted ambient glows (`rgba(244, 63, 94, 0.12)` for combat intensity, `rgba(56, 189, 248, 0.12)` for metabolic balance) with a 24px blur radius and zero vertical offset.
- **Overlays & Modals:** Floating inspection drawers adopt an ultra-dark 80% opacity backing with an 8px hardware blur, preventing environmental distraction while anchoring active diagnostics.

## Shapes

The design system maintains a taut, disciplined contour geometry based on a base scale (`roundedness: 1`):

- **Micro Controls & Tags:** `0.25rem` (4px) corner radius for data pills, tags, telemetry flags, and input fields.
- **Standard Controls & Cards:** `0.5rem` (8px) corner radius across standard buttons, list modules, and parameter groups.
- **Complex Containers:** `0.75rem` (12px) corner radius across major biometric containers and primary analytics cards.
- **Interaction Feedback:** Form controls maintain crisp, straight geometries under active states, reinforcing an exact, instrument-grade combat console rather than an organic lifestyle product.

## Components

### Buttons & Interactive Controls
- **Primary Kinetic Action:** Solid `#F43F5E` fill with `#0D1117` Space Grotesk text. Focused on starting bouts, locking metrics, or logging critical strain.
- **Secondary Steady-State Action:** `#161B22` background with `#38BDF8` border (1px) and text. Focused on recovery scans, glucose calibrations, and baseline adjustments.
- **Ghost/Tertiary:** Pure transparent fill, `#94A3B8` text, transitioning to `#21262D` fill on hover.

### Biometric Cards & Containers
- Built on `#161B22` surfaces with `#30363D` 1px borders.
- Header zones contain an uppercase `label-mono` descriptor on the left and a live colored sensor pip (`#38BDF8` steady, `#F43F5E` peak) on the right.
- Content zones reserve generous inner padding (`space-lg`), separating core metric numbers from trend graphs to prevent cognitive overload.

### Telemetry Chips & Metric Badges
- Compact markers configured with `space-xs` vertical and `space-sm` horizontal padding.
- Neutral states use `#21262D` with `#94A3B8` typography; active athletic zones shift to subtle tints of `#F43F5E` with high-contrast text.

### Telemetry Stream Inputs & Fields
- Dark structural wells rendered in `#0D1117` framed with a 1px `#30363D` border.
- Active states transition the border directly to `#38BDF8` or `#F43F5E` without thick outlines.
- Clear numeric step indicators with monospace alignment.

### Specialized Biological Data Indicators
- **Zone Spectrum Gauges:** Segmented bar indicators showing heart-rate intensity levels (Zones 1–5), transitioning progressively from `#38BDF8` through slate to pure `#F43F5E`.
- **Differential Glucose Sparklines:** Feathered vector curves drawn over `#161B22` backdrops with electric ice fills (`rgba(56, 189, 248, 0.08)`) illustrating post-grappling metabolic recovery.