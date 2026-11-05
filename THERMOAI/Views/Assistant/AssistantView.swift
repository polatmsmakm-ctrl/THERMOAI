//
//  AssistantView.swift
//  THERMOAI — Views/Assistant
//
//  Purpose: Chat UI for the AI nutrition coach with suggestion chips and a
//           typing indicator. Context (targets + today's intake) is sent with
//           every message.
//  Dependencies: SwiftUI, SwiftData, ViewModels/AssistantViewModel.swift
//

import SwiftUI
import SwiftData

struct AssistantView: View {
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<FoodEntry> { !$0.isSoftDeleted }) private var entries: [FoodEntry]
    @Query(filter: #Predicate<WeightEntry> { !$0.isSoftDeleted }) private var weights: [WeightEntry]

    @State private var vm: AssistantViewModel
    @State private var showPaywall = false
    @FocusState private var inputFocused: Bool

    init(env: AppEnvironment) {
        _vm = State(initialValue: AssistantViewModel(ai: env.ai))
    }

    private var context: NutritionContext {
        guard let profile = profiles.first else {
            return NutritionContext(targetCalories: 2000, consumedCalories: 0, proteinTargetG: 0, carbsTargetG: 0, fatTargetG: 0, goal: "maintain")
        }
        return MetricsCalculator.nutritionContext(profile: profile, weights: weights, entries: entries)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.sm) {
                            if vm.messages.isEmpty { emptyState }
                            ForEach(vm.messages) { MessageBubble(message: $0).id($0.id) }
                            if vm.isThinking { TypingIndicator().id("typing") }
                            if let error = vm.errorMessage {
                                ErrorBanner(message: error)
                                if error == APIError.quotaExceeded.errorDescription {
                                    Button("Upgrade to Pro") { showPaywall = true }.buttonStyle(.thermoPrimary)
                                }
                            }
                        }
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: vm.messages.count) { _, _ in
                        withAnimation { proxy.scrollTo(vm.messages.last?.id, anchor: .bottom) }
                    }
                    .onChange(of: vm.isThinking) { _, thinking in
                        if thinking { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
                    }
                }
                suggestionBar
                inputBar
            }
            .thermoScreen()
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !vm.messages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New chat", systemImage: "square.and.pencil") { vm.clear() }
                    }
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            ThermoLogo(size: 60).padding(.top, 60)
            Text("Your metabolic coach").font(Theme.Typography.title2).foregroundStyle(Theme.Colors.textPrimary)
            Text("Ask about your targets, foods, plateaus or the science of energy balance.")
                .multilineTextAlignment(.center).font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var suggestionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(vm.suggestions, id: \.self) { s in
                    Button(s) { Task { await vm.send(s, context: context) } }
                        .font(Theme.Typography.caption)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .background(Capsule().fill(Theme.Colors.surfaceHighlight))
                        .disabled(vm.isThinking)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
        }
    }

    private var inputBar: some View {
        @Bindable var vm = vm
        return HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
            TextField("Ask anything about nutrition…", text: $vm.input, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 22).fill(Theme.Colors.surface))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.Colors.stroke))
                .foregroundStyle(Theme.Colors.textPrimary)
            Button {
                Task { await vm.send(context: context) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(vm.canSend ? AnyShapeStyle(Theme.Gradients.heat) : AnyShapeStyle(Theme.Colors.surfaceHighlight)))
            }
            .disabled(!vm.canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.ultraThinMaterial)
    }
}

private struct MessageBubble: View {
    let message: AssistantViewModel.Message
    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            Text(message.text)
                .font(Theme.Typography.body)
                .foregroundStyle(isUser ? Color.white : Theme.Colors.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background {
                    if isUser {
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.Gradients.heat)
                    } else {
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.Colors.surface)
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.Colors.stroke))
                    }
                }
                .textSelection(.enabled)
            if !isUser { Spacer(minLength: 48) }
        }
        .transition(.move(edge: isUser ? .trailing : .leading).combined(with: .opacity))
    }
}

private struct TypingIndicator: View {
    @State private var phase = 0.0
    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle().fill(Theme.Colors.accent)
                        .frame(width: 7, height: 7)
                        .opacity(0.3 + 0.7 * abs(sin(phase + Double(i) * 0.6)))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.Colors.surface))
            Spacer()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                phase += 0.25
            }
        }
        .accessibilityLabel("Coach is typing")
    }
}
