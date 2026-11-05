//
//  FoodScannerView.swift
//  THERMOAI — Views/Scanner
//
//  Purpose: AI food recognition. Live camera (AVFoundation) or photo library →
//           on-device Vision pre-check → Gemini analysis → editable review
//           (portion sliders rescale nutrients) → log to diary.
//  Dependencies: SwiftUI, PhotosUI, SwiftData, Services/CameraService.swift,
//                ViewModels/ScannerViewModel.swift, ViewModels/FoodLogViewModel.swift
//

import SwiftUI
import PhotosUI
import SwiftData

struct FoodScannerView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [UserProfile]

    @State private var vm: ScannerViewModel
    @State private var log: FoodLogViewModel
    @State private var camera = CameraService()
    @State private var cameraError: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var showPaywall = false
    @State private var shutterFlash = false

    init(env: AppEnvironment) {
        _vm = State(initialValue: ScannerViewModel(ai: env.ai))
        _log = State(initialValue: FoodLogViewModel(ai: env.ai, health: env.health))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                switch vm.phase {
                case .idle: captureView
                case .checking, .analyzing: analyzingView
                case .review: reviewView
                case .failed(let message): failureView(message)
                }
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if vm.phase != .idle {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { vm.cancel() } }
                }
            }
            .animation(Theme.Motion.spring, value: vm.phase)
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
        .task(id: vm.phase == .idle && scenePhase == .active) {
            if vm.phase == .idle && scenePhase == .active { await startCamera() } else { camera.stop() }
        }
        .onDisappear { camera.stop() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    vm.analyze(image)
                }
                photoItem = nil
            }
        }
    }

    // MARK: Capture

    private var captureView: some View {
        ZStack {
            if let cameraError {
                ContentUnavailableView("Camera unavailable", systemImage: "camera.fill", description: Text(cameraError))
            } else {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea(edges: .horizontal)
                    .overlay(viewfinder)
                    .overlay(Color.white.opacity(shutterFlash ? 0.6 : 0).allowsHitTesting(false))
            }

            VStack {
                TextField("Add a note (e.g. cooked in olive oil)", text: $vm.userNote)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.sm)
                Spacer()
                HStack(alignment: .center) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2).foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Choose from library")
                    Spacer()
                    Button(action: capture) {
                        ZStack {
                            Circle().strokeBorder(.white, lineWidth: 4).frame(width: 82, height: 82)
                            Circle().fill(Theme.Gradients.heat).frame(width: 66, height: 66)
                                .shadow(color: Theme.Colors.accent.opacity(0.6), radius: 16)
                        }
                    }
                    .disabled(cameraError != nil)
                    .accessibilityLabel("Take photo")
                    .sensoryFeedback(.impact(weight: .medium), trigger: shutterFlash)
                    Spacer()
                    Color.clear.frame(width: 56, height: 56)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
    }

    private var viewfinder: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.72
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Theme.Gradients.heat, style: StrokeStyle(lineWidth: 3, dash: [28, 14]))
                .frame(width: side, height: side)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .shadow(color: Theme.Colors.accent.opacity(0.4), radius: 12)
        }
        .allowsHitTesting(false)
    }

    // MARK: Analyzing

    private var analyzingView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            if let image = vm.capturedImage {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 240, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                    .overlay(ScanningSweep())
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            }
            Text(vm.phase == .checking ? "Checking photo…" : "Identifying foods & estimating portions…")
                .font(Theme.Typography.headline).foregroundStyle(Theme.Colors.textPrimary)
            ProgressView().tint(Theme.Colors.accent)
        }
        .padding()
    }

    // MARK: Review

    private var reviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if let image = vm.capturedImage {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(height: 200).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                }
                GlassCard {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Total").font(Theme.Typography.overline).foregroundStyle(Theme.Colors.accentAmber).textCase(.uppercase)
                            Text("\(Int(vm.totalCalories)) kcal").font(Theme.Typography.title).foregroundStyle(Theme.Colors.textPrimary)
                                .contentTransition(.numericText(value: vm.totalCalories))
                        }
                        Spacer()
                        MacroDonutChart(proteinG: vm.totalProtein, carbsG: vm.totalCarbs, fatG: vm.totalFat)
                            .frame(width: 80, height: 80)
                    }
                }

                SectionHeader(title: "Detected items", subtitle: "Adjust portions if they look off")
                ForEach(vm.items) { item in
                    ScannedItemEditor(item: item,
                                      onChange: { grams in vm.updateGrams(for: item, to: grams) },
                                      onRemove: { withAnimation { vm.remove(item) } })
                }
                if !vm.notes.isEmpty {
                    Label(vm.notes, systemImage: "info.circle").font(.caption).foregroundStyle(Theme.Colors.textSecondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(MealType.allCases) { meal in
                            SelectableChip(title: meal.title, systemImage: meal.symbol, isSelected: vm.mealType == meal) {
                                vm.mealType = meal
                            }
                        }
                    }
                }

                Button("Log \(Int(vm.totalCalories)) kcal") {
                    vm.save(using: log, in: context, exportToHealth: profiles.first?.healthKitEnabled ?? false)
                }
                .buttonStyle(.thermoPrimary)
                .disabled(vm.items.isEmpty)
                .sensoryFeedback(.success, trigger: vm.phase == .idle)

                Text("AI estimates can be off by 20% or more. Check portions for accuracy.")
                    .font(.caption2).foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Failure

    private func failureView(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 44)).foregroundStyle(Theme.Colors.warning)
            Text(message).multilineTextAlignment(.center).foregroundStyle(Theme.Colors.textPrimary)
            if message == APIError.quotaExceeded.errorDescription {
                Button("Upgrade to Pro") { showPaywall = true }.buttonStyle(.thermoPrimary)
            }
            Button("Retry") { vm.retry() }.buttonStyle(.thermoSecondary)
            Button("Take another photo") { vm.reset() }.foregroundStyle(Theme.Colors.accent)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: 480)
    }

    // MARK: Actions

    private func startCamera() async {
        do {
            try await camera.start()
            cameraError = nil
        } catch {
            cameraError = error.localizedDescription
        }
    }

    private func capture() {
        withAnimation(.easeOut(duration: 0.08)) { shutterFlash = true }
        Task {
            defer { withAnimation(.easeIn(duration: 0.25)) { shutterFlash = false } }
            do {
                let image = try await camera.capturePhoto()
                camera.stop()
                vm.analyze(image)
            } catch {
                cameraError = error.localizedDescription
            }
        }
    }
}

/// Editable row for one detected item with a portion slider.
private struct ScannedItemEditor: View {
    let item: AnalyzedFoodItem
    let onChange: (Double) -> Void
    let onRemove: () -> Void
    @State private var grams: Double = 0

    var body: some View {
        ThermoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Text(item.name).font(Theme.Typography.headline).foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Button(role: .destructive, action: onRemove) { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .accessibilityLabel("Remove \(item.name)")
                }
                HStack {
                    ConfidenceBadge(confidence: item.confidence)
                    Spacer()
                    Text("\(Int(item.calories)) kcal").font(Theme.Typography.metricSmall).foregroundStyle(Theme.Colors.textPrimary)
                }
                Slider(value: $grams, in: 5...max(item.estimatedGrams * 3, 50), step: 5) { editing in
                    if !editing { onChange(grams) }
                }
                Text("\(Int(grams)) g · \(item.portionDescription)")
                    .font(.caption).foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .onAppear { grams = item.estimatedGrams }
    }
}

/// Animated scan line over the photo while AI runs.
private struct ScanningSweep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, Theme.Colors.accent.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 70)
                .offset(y: offset * geo.size.height)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { offset = 1 }
                }
        }
        .allowsHitTesting(false)
    }
}
