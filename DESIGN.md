---
name: BNPB
description: Offline-first personal relationship companion and local-first CRM
colors:
  primary: "#0D7A4F"
  primary-dark: "#22A36D"
  primary-container: "#EAF6EF"
  primary-container-dark: "#12301F"
  secondary: "#127A6B"
  secondary-dark: "#9AA79F"
  surface: "#FFFFFF"
  surface-dark: "#151A17"
  surface-tint: "#F1F5F2"
  surface-tint-dark: "#1F2621"
  card-border: "#E6EBE7"
  card-border-dark: "#2B332D"
  hairline: "#EEF2EF"
  hairline-dark: "#242C26"
  text-primary: "#0F1512"
  text-primary-dark: "#E9EFEB"
  text-secondary: "#57635C"
  text-secondary-dark: "#9AA79F"
  text-muted: "#8A988F"
  danger: "#C25A3F"
  danger-dark: "#E07A5F"
  danger-tint: "#FBEEE9"
  danger-tint-dark: "#331813"
  danger-border: "#F0D9D0"
  danger-border-dark: "#4A2B21"
  ai-card-bg: "#0F1512"
  ai-card-bg-dark: "#0C1712"
  switch-off: "#D5DBD7"
  switch-off-dark: "#37413B"
typography:
  display:
    fontFamily: "Plus Jakarta Sans, Inter, -apple-system, sans-serif"
    fontSize: "24px"
    fontWeight: 800
    lineHeight: 1.2
    letterSpacing: "-0.48px"
  title:
    fontFamily: "Plus Jakarta Sans, Inter, -apple-system, sans-serif"
    fontSize: "18px"
    fontWeight: 800
    lineHeight: 1.3
    letterSpacing: "-0.2px"
  headline:
    fontFamily: "Plus Jakarta Sans, Inter, -apple-system, sans-serif"
    fontSize: "16px"
    fontWeight: 700
    lineHeight: 1.35
    letterSpacing: "-0.2px"
  body:
    fontFamily: "Plus Jakarta Sans, Inter, -apple-system, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: "normal"
  label:
    fontFamily: "Plus Jakarta Sans, Inter, -apple-system, sans-serif"
    fontSize: "11.5px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "0.2px"
rounded:
  sm: "6px"
  md: "11px"
  input: "13px"
  card: "16px"
  modal: "20px"
  full: "9999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  base: "16px"
  lg: "20px"
  xl: "24px"
  xxl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "#FFFFFF"
    rounded: "{rounded.input}"
    padding: "10px 18px"
  button-primary-hover:
    backgroundColor: "{colors.secondary}"
  card-default:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.card}"
    padding: "16px 16px"
  input-field:
    backgroundColor: "{colors.hairline}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.input}"
    padding: "13px 15px"
---

# Design System: BNPB

## Overview

**Creative North Star: "The Cloistered Ledger"**

BNPB's visual world embodies a tranquil, dignified, and tactile utility crafted for intentional relationships and quiet prayer reflection. Free from notification clamor, commercial CRM bloat, and gamified pressure, the interface treats relational context and prayer requests as confidential and sacred records. Every surface balances serene clarity with precise physical craft.

The aesthetic marries botanical emerald greens and warm sage linen tints with crisp structural dividers and high-contrast dark accent cards. Typography is disciplined and human, set in Plus Jakarta Sans with a calibrated 13px base measure and snug letter-spacing. Surfaces remain completely flat at rest, establishing structure through 1px hairline borders rather than artificial drop shadows.

**Key Characteristics:**
- **Calm Botanical Contrast**: Deep Forest Emerald (`#0D7A4F` / `#22A36D`) accents set against crisp chalk (`#FFFFFF`), sage linen (`#F1F5F2`), or dark slate (`#151A17`) surfaces.
- **Tactile Precision**: Mechanical-feeling toggle switches (`CrispSwitch`), pill-shaped chips, and 13–16px rounded containers that feel permanent and deliberate.
- **High-Contrast Focal Surfaces**: Fixed dark cards (`#0F1512` / `#0C1712`) reserved exclusively for AI recommendations, on-device semantic search, and key metrics.
- **Hairline Containment**: Pure flat tonal layering where 1px borders (`#E6EBE7` / `#2B332D`) organize dense information without visual noise.

## Colors

The palette is anchored by deep botanical greens, soft natural paper tints, terracotta alerts, and specialized dark accent containers.

### Primary
- **Forest Emerald** (`#0D7A4F` light / `#22A36D` dark): The signature accent, used for primary action buttons, active navigation indicators, active switch states, and selected filter states.
- **Emerald Mist Container** (`#EAF6EF` light / `#12301F` dark): Subtle tinted background for active badges, selected navigation tiles, and highlighted cards.

### Secondary
- **Cypress Teal** (`#127A6B` light / `#9AA79F` dark): Supporting accent for interactive hovers, secondary iconography, and data visualizations.

### Tertiary & Alert
- **Terracotta Ember** (`#C25A3F` light / `#E07A5F` dark): Dignified warning and destructive action role (prayer urgency, overdue indicators, danger actions).
- **Terracotta Tint** (`#FBEEE9` light / `#331813` dark): Subtle alert wash for overdue banners and destructive modal confirmations.
- **Terracotta Hairline** (`#F0D9D0` light / `#4A2B21` dark): Crisp 1px border framing danger and alert cards.

### Neutral
- **Chalk & Basalt Surface** (`#FFFFFF` light / `#151A17` dark): Primary canvas background and elevated content cards.
- **Sage Linen Tint** (`#F1F5F2` light / `#1F2621` dark): Page canvas background on desktop and subtle grouping background.
- **Card Border** (`#E6EBE7` light / `#2B332D` dark): Canonical 1px perimeter border for cards, dialogs, and panels.
- **Hairline Divider** (`#EEF2EF` light / `#242C26` dark): Faint separator between list rows, table items, and search inputs.
- **Deep Ink Text** (`#0F1512` light / `#E9EFEB` dark): High-contrast primary reading text.
- **Secondary Slate Text** (`#57635C` light / `#9AA79F` dark): Secondary labels, timestamps, and metadata.
- **Muted Sage Outline** (`#8A988F` light / `#8B988F` dark): Unselected navigation icons and placeholder strokes.
- **AI Card Background** (`#0F1512` light / `#0C1712` dark): Theme-static near-black container used for on-device AI search, ask input, and top analytics highlights.

### Named Rules
**The Rarity of Emerald Rule.** Primary emerald is an intentional beacon. It is reserved for active states, key interactive commitments, and focused confirmation buttons. Less than 8% of any screen surface is emerald.

**The Sanctuary Card Rule.** The fixed dark container (`#0F1512` / `#0C1712`) is strictly reserved for AI synthesis, semantic search ("Ask"), and top-level insight banners. It must never be repurposed as a general card background.

## Typography

**Display & Headline Font:** Plus Jakarta Sans (fallback: Inter, -apple-system, BlinkMacSystemFont, sans-serif)  
**Body Font:** Plus Jakarta Sans  
**Label/Caption Font:** Plus Jakarta Sans  

**Character:** Modern geometric yet warm, legible at tight desktop data densities while retaining welcoming humanity in long-form prayer notes.

### Hierarchy
- **Display** (800 weight, 24px, line-height 1.2, letter-spacing -0.48px): Screen headers and top-level page titles.
- **Title** (800 weight, 18px, line-height 1.3, letter-spacing -0.2px): Section headers, sidebar brand identity, and modal titles.
- **Headline** (700 weight, 16px, line-height 1.35, letter-spacing -0.2px): Contact names, card titles, and group headings.
- **Body** (400/500 weight, 13px base, line-height 1.5, normal tracking): Contact notes, prayer journal entries, and interaction details.
- **Label** (600/700 weight, 11.5px, line-height 1.2, letter-spacing 0.2px): Navigation labels, status tags, table column headers, and date badges.

### Named Rules
**The Scalable Measure Rule.** All interface type scales proportionally with the user's chosen `fontSizeNotifier` preference (defaulting to 13px base). Line lengths for prayer diary and interaction notes are capped at 72ch to maintain comfortable reading cadence.

## Layout

BNPB adapts gracefully between an expansive multi-column desktop workstation and a streamlined single-column mobile companion.

### Desktop Layout Model (macOS / Desktop)
- **Window Frame**: Minimum window dimensions 1180px × 760px with transparent native title bar and functional traffic lights offset by 52px.
- **Persistent Sidebar**: Fixed 242px width on the left, containing brand header, primary navigation links (Contacts, Analytics, Prayer, Ask, Add Contact, Settings), pinned follow-up AI cards, and theme switcher.
- **Content Area**: Fluid multi-pane master-detail workflows:
  - *Prayer Diary*: 2-column split (chronological prayer logs on the left; active prayer list and urgent requests on the right).
  - *Contacts*: Instant search and filter bar at the top, scrollable master list, and side-by-side or modal detail inspector.
  - *Settings*: 236px secondary category sub-navigation paired with structured card panels.

### Mobile Layout Model (Android / iOS)
- **Navigation Bar**: Standard bottom navigation bar with 4 primary destinations (Contacts, Analytics, Add Contact, Settings), tinted active indicators, and 0dp elevation.
- **Sheet Architecture**: Modal bottom sheets with 26px top corner radius for interaction logging and contact creation.

### Spacing Scale
- `xs` (4px): Micro gaps between icons and labels.
- `sm` (8px): Padding inside chips, badges, and compact list items.
- `md` (12px): Standard inner gutter between related form elements.
- `base` (16px): Card internal padding and standard screen margins.
- `lg` (20px): Outer layout padding and sectional dividers.
- `xl` (24px): Gap between distinct visual groups or desktop columns.
- `xxl` (32px): Major page section breaks.

## Elevation & Depth

BNPB adheres to a **Tonal Layering & Structural Hairlines** depth model. Surfaces are flat at rest (0dp elevation across cards, navigation bars, app bars, and dialogs). Depth and hierarchy are achieved entirely through background contrast, subtle surface tints, and 1px hairline borders.

### Shadow Vocabulary
- **Window Frame** (`0 20px 50px rgba(0,0,0,0.15), 0 0 0 1px rgba(0,0,0,0.1)`): Applied exclusively to the outer macOS application window to separate the app from desktop wallpaper.
- **Resting Elements**: Flat (zero shadow).
- **Floating Action Button**: Flat (0 elevation, 0 hover elevation).

### Named Rules
**The Hairline Containment Rule.** Never add drop shadows to cards, chips, or search inputs. Structural separation must rely on `cardBorder` (`#E6EBE7` / `#2B332D`) or `hairline` (`#EEF2EF` / `#242C26`) borders against the `surface` or `surfaceTint` background.

## Shapes

The form language is disciplined and cohesive, with radii mapped strictly to component scales:
- **`sm` (6px)**: Small status indicators, counter badges, and pill tags.
- **`md` (11px)**: Desktop sidebar navigation item touch targets.
- **`input` (13px)**: Text fields, search bars, and toggle switches.
- **`card` (16px)**: Content cards, statistics containers, and list groupings.
- **`modal` (20px)**: Desktop modals (`MacOSModal`), dialogs, and floating toasts (`CrispToast`).
- **`bottom-sheet` (26px top)**: Mobile bottom action sheets.
- **`full` (9999px)**: Filter chips, circular contact avatars, and action pills.

## Components

### Buttons
- **Shape:** Rounded rectangle, 13px radius (`rounded.input`).
- **Primary:** Forest Emerald background (`#0D7A4F` light / `#22A36D` dark), pure white text, 10px vertical × 18px horizontal padding, bold 13px typography.
- **Secondary / Outlined:** Transparent background, 1px `cardBorder` stroke, `textPrimary` text.
- **Ghost:** Transparent background, no border, `primary` or `textSecondary` text, subtle green tint on hover.

### Switches (`CrispSwitch`)
- **Dimensions:** 44px width × 26px height with 13px corner radius.
- **Track Active:** Forest Emerald (`#0D7A4F` light / `#22A36D` dark).
- **Track Inactive:** Neutral muted grey (`#D5DBD7` light / `#37413B` dark).
- **Knob:** 22px diameter solid white (`#FFFFFF` light / `#F2F5F3` dark), smooth 180ms ease-out spring animation.

### Cards / Containers
- **Corner Style:** 16px radius (`rounded.card`).
- **Background:** White (`#FFFFFF`) in light mode; Dark Slate (`#151A17`) in dark mode.
- **Border:** 1px solid `surfaceContainerHighest` (`#E6EBE7` light / `#2B332D` dark).
- **Shadow:** None (0dp elevation).
- **Internal Padding:** 16px uniform padding.

### Inputs / Search Bars
- **Style:** Filled with 13px corner radius, background `cardBorder` at 30% opacity or hairline tint.
- **Border:** None at rest; 1.5px solid Forest Emerald on focus; 1px solid Terracotta on error.
- **Internal Padding:** 13px vertical × 15px horizontal.
- **Hint Text:** Muted placeholder (`#A9B3AD` light / `#5D6A62` dark).

### Desktop Modal (`MacOSModal`)
- **Dimensions:** Scaled popup dialog with 20px radius, 1px border.
- **Scrim:** Dark blurred scrim (20px backdrop-filter blur).
- **Motion:** 200ms scale-in (0.95 → 1.0) and fade-in curve.

### Floating Toast (`CrispToast`)
- **Style:** Compact floating dark pill (20px radius) replacing default Flutter SnackBar.
- **Background:** Solid `#0F1512` with white text and green confirmation icon.

### Contact Avatar (`ContactAvatar`)
- **Shape:** Full circular (9999px radius), 40px default diameter.
- **Palette:** Soft green pastel tint background with deep Forest Emerald uppercase initials.

## Do's and Don'ts

### Do:
- **Do** reference semantic `Theme.of(context).colorScheme` roles (`primary`, `surface`, `cardBorder`, `hairline`) rather than hardcoding hex codes.
- **Do** keep cards and dialogs flat (0 elevation) with 1px border containment.
- **Do** preserve the fixed dark container (`aiCardBg`) for AI recommendations and search prompts across both light and dark themes.
- **Do** use `CrispSwitch` for all settings toggles and `CrispToast` for snack/status notifications.
- **Do** maintain responsive layout parity between mobile bottom sheets and desktop side-by-side split views.

### Don't:
- **Don't** use standard material drop shadows or elevated floating cards on desktop or mobile.
- **Don't** use generic Flutter SnackBar notifications (use `CrispToast.show`).
- **Don't** hardcode raw hex values outside the centralized theme definition in `lib/main.dart`.
- **Don't** stretch mobile full-width lists across widescreen desktop monitors; use structured multi-column split views or centered constrained cards.
- **Don't** clutter screens with gamification badges, streaks, or aggressive push prompts.
