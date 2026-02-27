# Paywall Visual Redesign

**Date:** 2026-02-27
**Scope:** Visual-only redesign of PaywallView — no architecture changes

## Summary

Replace the current dark gradient paywall with a native iOS sheet that uses glass material over a full-bleed hero image background. Modernize feature display from vertical checklist to horizontal chips. Update package cards to use material backgrounds.

## Layout & Presentation

- **Presentation:** SwiftUI `.sheet` with `.large` detent (replaces current `fullScreenCover`)
- **Background:** `SubscriptionHero` image fills the presenting view behind the sheet
- **Sheet material:** `.presentationBackground(.ultraThinMaterial)` for glass blur
- **Dismiss:** Native sheet grabber + swipe down (no custom X button)
- **iPad:** Native centered floating card
- **macOS:** Native macOS sheet from top

## Content Structure

```
VStack(spacing: 24) {
    Title: "Pulse Route Pro" (.title2, .rounded, .bold)
    Subtitle: "Unlock all features" (.subheadline, white 0.7)

    Feature chips (HStack, wrapping):
        [shield.fill  Premium Servers]
        [arrow.triangle.branch  Smart Route]
        [map.fill  Lite Trace]

    Trial banner (conditional)

    Package cards (VStack):
        Yearly (with savings badge)
        6-Month
        Monthly

    Continue button (PrimaryCTAButton — unchanged)

    Legal row: Restore | Terms | Privacy
    Disclosure text
}
```

## Visual Components

### Feature Chips
- Horizontal row, SF Symbol + label per chip
- `.caption`, `.medium` weight, white text
- `.ultraThinMaterial` capsule background
- Wraps on narrow screens via `ViewThatFits`

### Package Cards
- Same API as current `PackageCard`
- Selected: accent border + accent fill 8% + filled radio
- Unselected: `.ultraThinMaterial` background, no border
- Savings badge: "Save {X}%" capsule in accent color

### Unchanged Components
- `PrimaryCTAButton` (continue button)
- Legal row styling
- Disclosure text
- All purchase/restore logic

## Files Changed

1. **`PaywallView.swift`** — Full body rewrite. Same state, same actions, new layout.
2. **`PackageCard.swift`** — Background from opaque to material. Minor styling.
3. **`ContentView.swift`** — `.fullScreenCover` → `.sheet` with detents + hero image background.

## Files NOT Changed

- `RevenueCatService.swift`
- `SubscriptionSyncService.swift`
- `SubscriptionView.swift`
- `SubscriptionPackage.swift`
- `ButtonStyles.swift`
- Any purchase/restore/sync logic

## Decisions

- Native `.sheet` over custom ZStack (HIG compliance, less code, multi-platform)
- Horizontal feature chips over vertical checklist (compact, modern)
- 3 plans kept: monthly, 6-month, yearly
- Features: Premium Servers, Smart Route, Lite Trace
