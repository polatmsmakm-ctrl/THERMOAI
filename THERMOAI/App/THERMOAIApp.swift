//
//  THERMOAIApp.swift
//  THERMOAI — App
//
//  Purpose: Application entry point. Creates the SwiftData container and the
//           AppEnvironment, applies the global dark theme, and syncs when the
//           app returns to the foreground.
//  Dependencies: SwiftUI, SwiftData, App/AppEnvironment.swift, App/RootView.swift
//

import SwiftUI
import SwiftData

@main
struct THERMOAIApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer
    @State private var environment: AppEnvironment

    init() {
        let container: ModelContainer
        do {
            container = try ThermoSchema.makeContainer()
        } catch {
            // Corrupt or incompatible store: fall back to memory so the app still launches.
            container = try! ThermoSchema.makeContainer(inMemory: true)
        }
        self.container = container
        _environment = State(initialValue: AppEnvironment(container: container))
        Theme.applyUIKitAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .preferredColorScheme(.dark)
                .tint(Theme.Colors.accent)
                .task { await environment.bootstrap() }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await environment.sync?.syncNow() } }
        }
    }
}
