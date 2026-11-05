# THERMO AI — Implementation Handoff Guide

**Audience:** the AI coding agent that will assemble, compile, test, sign and export the app.
**Status of this package:** source only. Nothing here has been compiled, executed or tested.

---

## 1. Architecture in one page

THERMO AI is an offline-first SwiftUI app (iOS 18+, Swift 6 language mode) backed by Supabase.

- **Core** (`Core/`) is pure Swift: `NutritionEngine` (Mifflin-St Jeor, revised Harris-Benedict, Katch-McArdle, TDEE, TEF, macros, deficits/surpluses, BMI, lean mass) and `NutritionAnalytics` (daily totals, streaks, EMA weight trend, regression weekly rate, adaptive TDEE).
- **Models** are SwiftData `@Model` classes (local truth) plus Codable DTOs.
- **Services** wrap every external system behind small types; AI and Health are protocols (`AIServicing`, `HealthServicing`) so view models are testable.
- **ViewModels** are `@MainActor @Observable`; views are thin.
- **AppEnvironment** is the composition root injected with `.environment(_:)`.
- **Backend**: Supabase Auth + Postgres with RLS + three Edge Functions. Gemini is reachable only through `gemini-proxy`.

Full tree and data flows: `docs/ARCHITECTURE.md`.

## 2. How modules connect (file dependency map)

```
THERMOAIApp ─► ThermoSchema (PersistentModels) ─► AppEnvironment
AppEnvironment ─► AppConfig, HTTPClient, AuthService, SupabaseClient, GeminiService,
                  HealthKitService, SubscriptionService, SyncService
RootView ─► AuthView | OnboardingView | MainTabView
MainTabView ─► DashboardView, FoodLogView, FoodScannerView, AssistantView,
               ProgressDashboardView, MealPlanView, MetabolicCalculatorView, SettingsView
Each View ─► its ViewModel ─► MetricsCalculator ─► NutritionEngine / NutritionAnalytics
GeminiService ─► SupabaseClient.invoke("gemini-proxy") ─► AIResponseValidator
SyncService ─► SupabaseClient (PostgREST) ─► SyncDTOs ─► PersistentModels
SubscriptionService ─► StoreKit 2 ─► SupabaseClient.invoke("verify-subscription")
AuthService ─► HTTPClient ─► Supabase Auth REST; KeychainStore
```

Shared types worth knowing: `MacroTargets` (NutritionEngine.swift) is used by AI requests; `EnergyStackBar` lives in DashboardView.swift and is reused by the calculator; `AnalysisResultCard` lives in AddFoodView.swift.

## 3. Required credentials

| Credential | Where it goes | Secret? |
|---|---|---|
| Supabase project URL | `Config/Secrets.xcconfig` → `SUPABASE_URL` | No |
| Supabase anon key | `Config/Secrets.xcconfig` → `SUPABASE_ANON_KEY` | No (RLS protects data) |
| Gemini API key (Google AI Studio) | `supabase secrets set GEMINI_API_KEY=…` | **Yes — server only** |
| App Store Connect In-App Purchase key (.p8, key id, issuer id) | Edge Function secrets `APPSTORE_*` | **Yes — server only** |
| Apple Team ID | `DEVELOPMENT_TEAM` in xcconfig | No |

Never commit `Secrets.xcconfig` or `backend/supabase/secrets.env`. Add both to `.gitignore`.

## 4. Backend configuration (Supabase)

1. Create a Supabase project. Install the Supabase CLI.
2. `supabase init` in `backend/`, then merge `config.toml.template` into the generated `config.toml`.
3. `supabase link --project-ref <ref>` and `supabase db push` (applies the migration).
4. Copy `env.example` → `secrets.env`, fill values, `supabase secrets set --env-file backend/supabase/secrets.env`.
5. Deploy functions:
   `supabase functions deploy gemini-proxy`
   `supabase functions deploy delete-account`
   `supabase functions deploy verify-subscription`
6. Auth settings (dashboard): enable Email (with confirmations) and Apple provider. For native Sign in with Apple, add the app's bundle ID as an authorised client ID.
7. Verify the Gemini model ID in `GEMINI_MODEL` against https://ai.google.dev/gemini-api/docs/models (the code defaults to `gemini-3.5-flash`; Gemini 2.5 models were scheduled for shutdown on 16 Oct 2026). The proxy uses `generationConfig.responseJsonSchema`; confirm against https://ai.google.dev/gemini-api/docs/json-mode.
8. Run `deno test backend/supabase/functions/gemini-proxy`.

**API endpoints**

| Endpoint | Method | Auth | Body | Returns |
|---|---|---|---|---|
| `/functions/v1/gemini-proxy` | POST | user JWT | `{task:"analyzeFoodImage", imageBase64, mimeType, note?}` | `FoodAnalysisResult` |
| | | | `{task:"analyzeFoodText", description}` | `FoodAnalysisResult` |
| | | | `{task:"chat", messages[], context}` | `ChatReply` |
| | | | `{task:"mealPlan", targets, preferences, days}` | `MealPlanResponse` |
| `/functions/v1/delete-account` | POST | user JWT | — | `{deleted:true}` |
| `/functions/v1/verify-subscription` | POST | user JWT | `{originalTransactionId}` | `{isPro}` |
| `/rest/v1/{profiles,food_entries,weight_entries,meal_plans}` | GET/POST/PATCH | user JWT + anon key | PostgREST | rows |

Error envelope from functions: `{ "error": { "code": "...", "message": "..." } }`; HTTP 429 = quota exceeded (mapped to `APIError.quotaExceeded`).

## 5. Xcode project setup & build configuration

1. New Xcode project: iOS App, **Product Name `THERMOAI`** (the module name must be `THERMOAI` for `@testable import THERMOAI`), Interface SwiftUI, Storage None, include Tests using **Swift Testing**.
2. Delete template `ContentView.swift`/app file; add the `THERMOAI/` folder contents to the app target and `THERMOAITests/` to the test target. Do **not** add the `.md` files in `Resources/` to the target.
3. Deployment target **iOS 18.0** (uses `Tab`/`TabSection`, `.sidebarAdaptable`, Vision `ClassifyImageRequest`). Devices: iPhone + iPad.
4. Build settings: `SWIFT_VERSION = 6`, Strict Concurrency = Complete, `INFOPLIST_FILE = THERMOAI/Config/Info.plist` (or merge keys if using a generated plist), `CODE_SIGN_ENTITLEMENTS = THERMOAI/Config/THERMOAI.entitlements`.
5. Copy `Secrets.xcconfig.template` → `Secrets.xcconfig`; set it as the base configuration for Debug and Release of the app target.
6. Add `PrivacyInfo.xcprivacy` to the app target.
7. Create `Assets.xcassets` per `Resources/AssetCatalog.md` (AppIcon, AccentColor, LaunchBackground).
8. Create `Configuration.storekit` per `Resources/Configuration.storekit.md` and select it in the Run scheme.

## 6. Apple permissions & entitlements

| Capability | Entitlement / key | Used by |
|---|---|---|
| Camera | `NSCameraUsageDescription` | CameraService |
| Photo library (read via PhotosPicker) | `NSPhotoLibraryUsageDescription` | FoodScannerView |
| HealthKit | `com.apple.developer.healthkit`, `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription` | HealthKitService |
| Sign in with Apple | `com.apple.developer.applesignin` | AuthView |
| Keychain sharing (optional) | `keychain-access-groups` | KeychainStore |
| In-App Purchase | capability only (no key) | SubscriptionService |
| URL scheme | `thermoai://` | Auth email redirect |

Enable HealthKit, Sign in with Apple and In-App Purchase on the App ID in the Developer portal.

## 7. Subscriptions
- Create an auto-renewable subscription group "THERMO AI Pro" with the two product IDs from `Secrets.xcconfig`.
- Purchases pass `appAccountToken = Supabase user id`. `verify-subscription` checks this token, so Pro can't be transferred between accounts.
- Optionally add App Store Server Notifications V2 → an extra Edge Function to update `is_pro` on expiry/refund without waiting for app launch.

## 8. Signing & IPA export
1. Signing & Capabilities → Automatically manage signing, select the team. Bundle ID must equal `PRODUCT_BUNDLE_IDENTIFIER` and the Supabase Apple client ID.
2. Product › Archive (scheme Release, destination "Any iOS Device (arm64)").
3. Organizer › Distribute App → **App Store Connect** (TestFlight/App Store) or **Release Testing / Ad Hoc** (requires registered device UDIDs) or **Development**.
4. CLI alternative:
   ```
   xcodebuild -project THERMOAI.xcodeproj -scheme THERMOAI -configuration Release \
     -destination 'generic/platform=iOS' -archivePath build/THERMOAI.xcarchive archive
   xcodebuild -exportArchive -archivePath build/THERMOAI.xcarchive \
     -exportPath build/ipa -exportOptionsPlist ExportOptions.plist
   ```
   `ExportOptions.plist` keys: `method` (`app-store-connect` | `release-testing` | `debugging`), `teamID`, `signingStyle` (`automatic`).

## 9. Implementation & verification checklist

**Backend**
- [ ] Migration applied; RLS enabled on all 5 tables; anon role cannot read any row
- [ ] Authenticated user cannot update `profiles.is_pro` (column grant)
- [ ] `consume_ai_quota` returns false after the free limit
- [ ] All 3 Edge Functions deployed with secrets; `deno test` passes
- [ ] Gemini model ID verified as current and stable
- [ ] Email + Apple auth providers configured

**App build**
- [ ] Module named `THERMOAI`; iOS 18 deployment target; Swift 6 mode compiles with zero errors
- [ ] `Secrets.xcconfig` wired; app shows no "Configuration needed" screen
- [ ] Assets catalog, StoreKit config, privacy manifest added
- [ ] All `THERMOAITests` pass (engine values are hand-verified in the test comments)

**Functional**
- [ ] Sign up (email confirmation path), sign in, Sign in with Apple, sign out, delete account
- [ ] Onboarding computes preview; under-18 blocked; profile + first weigh-in saved and synced
- [ ] Dashboard ring/macros/energy/week chart update after logging
- [ ] Diary: manual entry, AI text entry, day navigation, swipe delete, duplicate to today
- [ ] Scanner: camera permission flow, capture, library pick, non-food pre-check, analysis, portion edit, log
- [ ] Coach: send, suggestions, error banner, quota → paywall
- [ ] Meal plan: 1-day free, multi-day Pro-gated, save, reload, log meal
- [ ] Progress: ranges, weight trend scrubbing, calorie chart scrubbing, weigh-in add/delete, observed TDEE after 14 days
- [ ] Calculator: three formulas, safety floor message, methodology section
- [ ] Settings: profile edits mark sync; HealthKit toggle prompts; restore purchases
- [ ] Offline: log food in airplane mode → reconnect → rows appear in Supabase
- [ ] Two devices: edits converge (last-write-wins)
- [ ] HealthKit: meals appear as Food correlations; weight saved
- [ ] StoreKit sandbox purchase → `is_pro = true` server-side
- [ ] iPad: sidebar shows Tools section; layouts centred with max widths; rotation works
- [ ] Accessibility: VoiceOver labels on rings/charts, Dynamic Type up to XXL, Reduce Motion respected

**Release**
- [ ] App icon, launch colour, Terms/Privacy URLs replaced (PaywallView uses example.com)
- [ ] App Privacy answers in App Store Connect match `PrivacyInfo.xcprivacy`
- [ ] Health disclaimer present (Auth, Settings, Calculator)
- [ ] Archive, sign, export IPA

## 10. Known risk areas for compilation (check first)
1. **Swift 6 strict concurrency** — `CameraService` delegate callbacks, `Task` captures in `AuthService.refresh()`, and `try? … as Response` in `SubscriptionService.reportToServer`.
2. **Vision Swift API** — `ClassifyImageRequest.perform(on:orientation:)` signature (iOS 18).
3. **HealthKit async descriptors** — `HKStatisticsQueryDescriptor.result(for:)` return type.
4. **TabContentBuilder** — `if sizeClass == .regular { TabSection … }` inside `TabView`.
5. **Local `@Bindable var vm = vm`** declarations inside `@ViewBuilder` helper functions — if rejected, convert those helpers into small child views taking `@Bindable var vm`.
6. **SwiftData `#Predicate`** with `!$0.isSoftDeleted` in `@Query`.
Fix with minimal changes; do not redesign completed modules.
