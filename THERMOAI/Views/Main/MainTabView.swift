//
//  MainTabView.swift
//  THERMOAI — Views/Main
//
//  Purpose: Primary navigation. iOS 18 `Tab` API with `.sidebarAdaptable`:
//           a tab bar on iPhone, a collapsible sidebar on iPad.
//  Dependencies: SwiftUI, all feature views
//

import SwiftUI

enum AppTab: Hashable { case today, diary, scan, coach, plans, progress, calculator, settings }

struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: AppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "flame.fill", value: AppTab.today) {
                DashboardView(env: env, selection: $selection)
            }
            Tab("Diary", systemImage: "book.closed.fill", value: AppTab.diary) {
                FoodLogView(env: env)
            }
            Tab("Scan", systemImage: "camera.viewfinder", value: AppTab.scan) {
                FoodScannerView(env: env)
            }
            Tab("Coach", systemImage: "sparkles", value: AppTab.coach) {
                AssistantView(env: env)
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) {
                ProgressDashboardView(env: env)
            }

            // Extra destinations appear in the iPad sidebar; on iPhone they're
            // reachable from the Today screen toolbar.
            if sizeClass == .regular {
                TabSection("Tools") {
                    // These views are navigation-agnostic (also pushed from Today),
                    // so they get their own stack when hosted as tabs.
                    Tab("Meal Plans", systemImage: "fork.knife", value: AppTab.plans) {
                        NavigationStack { MealPlanView(env: env) }
                    }
                    Tab("Calculator", systemImage: "function", value: AppTab.calculator) {
                        NavigationStack { MetabolicCalculatorView() }
                    }
                    Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                        NavigationStack { SettingsView() }
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Theme.Colors.accent)
    }
}
