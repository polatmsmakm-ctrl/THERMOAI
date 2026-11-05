# THERMO AI — Architecture & Directory Tree

> Code-generation deliverable. Nothing in this package has been compiled, run or tested.
> The implementation agent owns project creation, compilation fixes, testing, signing and IPA export.

## 1. System overview

```
┌──────────────────────── iOS app (Swift 6 · SwiftUI · iOS 18+) ────────────────────────┐
│ Views ──► ViewModels (@Observable, @MainActor) ──► Core (pure Swift: engine, analytics) │
│              │                                                                          │
│              ├──► Services: Auth · Gemini(AI) · Sync · HealthKit · Camera · StoreKit    │
│              │         │                                                                │
│              └──► SwiftData (local source of truth, offline-first)                      │
└────────────────────────│───────────────────────────────────────────────────────────────┘
                         │ HTTPS, JWT (user) + anon key (public)
┌────────────────────────▼───────────────── Supabase ─────────────────────────────────────┐
│ Auth (GoTrue) · PostgREST (Postgres + RLS) · Edge Functions:                             │
│   gemini-proxy ─────► Google Gemini API (key stored ONLY as a function secret)           │
│   delete-account · verify-subscription ─► App Store Server API                           │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

**Key rules**
- The Gemini API key never exists in the app. All AI calls go through `gemini-proxy`, which authenticates the user, enforces a daily quota, constrains Gemini with a JSON schema, validates the output, and returns typed JSON. The client validates again.
- SwiftData is the source of truth; `SyncService` pushes dirty rows and pulls server changes (last-write-wins, soft deletes).
- All scientific maths lives in `Core/` with no UI or persistence imports, and is fully unit-tested.

## 2. Layers

| Layer | Folder | Responsibility | May depend on |
|---|---|---|---|
| App | `App/` | Entry point, composition root, routing | everything |
| Config | `Config/` | Build config, plist, entitlements, privacy manifest | — |
| Core | `Core/` | BMR/TDEE/TEF/macros/body composition; analytics | Models/Enums only |
| Models | `Models/` | Enums, SwiftData models, AI DTOs | Core (MacroTargets) |
| Networking | `Networking/` | HTTP client, Supabase REST/Functions, sync DTOs | Models |
| Services | `Services/` | Auth, AI, sync, HealthKit, camera, images, StoreKit | Networking, Models, Core |
| ViewModels | `ViewModels/` | Screen state & business rules | Services (via protocols), Core, Models |
| DesignSystem | `DesignSystem/` | Tokens and reusable components, charts | Core value types |
| Views | `Views/` | SwiftUI screens | ViewModels, DesignSystem |
| Utilities | `Utilities/` | Keychain | — |

## 3. Complete directory tree

```
ThermoAI/
├── docs/
│   ├── ARCHITECTURE.md                  This file
│   ├── MANIFEST.md                      Completed/remaining files, stage
│   └── HANDOFF.md                       Implementation guide + checklist
├── backend/supabase/
│   ├── config.toml.template             Supabase project config (no secrets)
│   ├── env.example                      Edge Function secrets template
│   ├── migrations/
│   │   └── 20261105000001_initial_schema.sql   Tables, enums, triggers, RLS, quota RPC
│   └── functions/
│       ├── gemini-proxy/
│       │   ├── index.ts                 AI endpoint: auth, quota, Gemini call, errors
│       │   ├── schemas.ts               responseJsonSchema definitions
│       │   ├── prompts.ts               System prompts + safety rules
│       │   ├── validation.ts            Output sanitisation / consistency checks
│       │   └── validation_test.ts       Deno tests
│       ├── delete-account/index.ts      In-app account deletion (Guideline 5.1.1(v))
│       └── verify-subscription/index.ts Confirms subscription with Apple, sets is_pro
├── THERMOAI/
│   ├── App/
│   │   ├── THERMOAIApp.swift            @main, ModelContainer, scene-phase sync
│   │   ├── AppEnvironment.swift         Dependency container
│   │   └── RootView.swift               Routing + Splash + config error
│   ├── Config/
│   │   ├── AppConfig.swift              Typed Info.plist config
│   │   ├── Secrets.xcconfig.template    Public client config template
│   │   ├── Info.plist                   Usage strings, URL scheme, config keys
│   │   ├── THERMOAI.entitlements        HealthKit, Sign in with Apple, keychain
│   │   └── PrivacyInfo.xcprivacy        Privacy manifest
│   ├── Core/
│   │   ├── Calculation/NutritionEngine.swift   All formulas (documented)
│   │   └── Analytics/NutritionAnalytics.swift  Totals, streaks, trend, adaptive TDEE
│   ├── Models/
│   │   ├── Enums.swift                  Sex, activity, goal, formula, meal, source
│   │   ├── PersistentModels.swift       SwiftData: UserProfile, FoodEntry, WeightEntry, SavedMealPlan
│   │   └── AIModels.swift               AI request/response DTOs
│   ├── Networking/
│   │   ├── HTTPClient.swift             Errors, retries, JSON coding, request builders
│   │   ├── SupabaseClient.swift         PostgREST + Edge Functions
│   │   └── SyncDTOs.swift               Table row types + mapping
│   ├── Services/
│   │   ├── AuthService.swift            Email, Apple, refresh, sign-out, delete
│   │   ├── GeminiService.swift          AIServicing implementation (via proxy)
│   │   ├── AIResponseValidator.swift    Client-side output validation
│   │   ├── ImageProcessor.swift         Resize/JPEG + Vision food pre-check
│   │   ├── CameraService.swift          AVFoundation capture
│   │   ├── HealthKitService.swift       Read body metrics, write meals/weight
│   │   ├── SyncService.swift            Offline-first push/pull
│   │   └── SubscriptionService.swift    StoreKit 2
│   ├── ViewModels/
│   │   ├── MetricsCalculator.swift      SwiftData → engine bridge
│   │   ├── AuthViewModel.swift
│   │   ├── OnboardingViewModel.swift
│   │   ├── DashboardViewModel.swift
│   │   ├── FoodLogViewModel.swift
│   │   ├── ScannerViewModel.swift
│   │   ├── AssistantViewModel.swift
│   │   ├── MealPlanViewModel.swift
│   │   └── ProgressViewModel.swift
│   ├── DesignSystem/
│   │   ├── Theme.swift                  Colours, gradients, type, spacing, motion
│   │   └── Components/
│   │       ├── Cards.swift              ThermoCard, GlassCard, background
│   │       ├── ProgressIndicators.swift CalorieRing, MacroRing, MacroBar, logo
│   │       ├── Controls.swift           Buttons, tiles, chips, fields, banners
│   │       └── Charts.swift             Interactive Swift Charts
│   ├── Views/
│   │   ├── Main/MainTabView.swift       Tab bar (iPhone) / sidebar (iPad)
│   │   ├── Auth/AuthView.swift
│   │   ├── Onboarding/OnboardingView.swift
│   │   ├── Dashboard/DashboardView.swift   (+ EnergyStackBar)
│   │   ├── FoodLog/FoodLogView.swift
│   │   ├── FoodLog/AddFoodView.swift       (+ AnalysisResultCard)
│   │   ├── Scanner/FoodScannerView.swift
│   │   ├── Scanner/CameraPreview.swift
│   │   ├── Assistant/AssistantView.swift
│   │   ├── MealPlan/MealPlanView.swift
│   │   ├── Progress/ProgressDashboardView.swift
│   │   ├── Calculator/MetabolicCalculatorView.swift
│   │   ├── Settings/SettingsView.swift
│   │   └── Paywall/PaywallView.swift
│   ├── Utilities/KeychainStore.swift
│   └── Resources/
│       ├── AssetCatalog.md              Assets.xcassets spec (create in Xcode)
│       └── Configuration.storekit.md    StoreKit test config spec (create in Xcode)
└── THERMOAITests/
    ├── NutritionEngineTests.swift
    ├── NutritionAnalyticsTests.swift
    ├── AIAndNetworkingTests.swift
    └── ViewModelTests.swift             (+ MockAIService, MockHealthService)
```

## 4. Main data flows

**Photo → log:** `FoodScannerView` → `CameraService.capturePhoto()` → `ScannerViewModel.analyze` → `ImageProcessor.foodLikelihood` (on-device Vision/Core ML) → `ImageProcessor.preparedJPEG` → `GeminiService.analyzeFood` → `SupabaseClient.invoke("gemini-proxy")` → server quota + Gemini + validation → `AIResponseValidator` → user adjusts portions (`AnalyzedFoodItem.scaled`) → `FoodLogViewModel.insert` → SwiftData (`needsSync = true`) → optional HealthKit export → `SyncService` upserts to `food_entries`.

**Targets:** `UserProfile` + latest `WeightEntry` → `MetricsCalculator.metabolicProfile` → `NutritionEngine.profile` → BMR (chosen formula) → TDEE → goal calories (safety floor) → macros.

**Auth:** `AuthService` (Keychain session) → `AppEnvironment.handleAuthChange` creates `SyncService`, wires `SubscriptionService.serverClient` → `RootView` routes to onboarding or main tabs.

## 5. Concurrency model (Swift 6)
- View models, `AuthService`, `SyncService`, `SubscriptionService`, `AppEnvironment`: `@MainActor @Observable`.
- `HTTPClient`, `SupabaseClient`, `GeminiService`: immutable `Sendable` structs.
- `CameraService`: `@unchecked Sendable`, state confined to a serial queue.
- `HealthKitService`: `@unchecked Sendable` wrapper over thread-safe `HKHealthStore`.
- SwiftData models are only touched on the main actor (`container.mainContext`).
