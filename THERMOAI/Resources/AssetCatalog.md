# Asset catalog requirements

File: THERMOAI/Resources/AssetCatalog.md

Create `THERMOAI/Resources/Assets.xcassets` in Xcode with:

- **AppIcon** — single 1024×1024 PNG (no alpha). Design: white flame glyph on an orange→amber
  gradient (#E2471B → #FF7A1A → #FFB020) over charcoal #0D0E11. Provide dark and tinted variants.
- **AccentColor** — #FF7A1A.
- **LaunchBackground** (Color Set) — #0D0E11 (referenced by `UILaunchScreen` in Info.plist).

All other colours are defined in code in `DesignSystem/Theme.swift`.
