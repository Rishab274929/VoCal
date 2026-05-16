//
//  OnboardingFlow.swift
//  VoCal
//
//  Editorial onboarding. Five steps: pitch → name → body basics → goal → paywall.
//  Each step is a serif headline + one input. Progress is hairline dashes.
//

import SwiftUI

struct OnboardingFlow: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var step: Step = .pitch
    @State private var name: String = ""
    @State private var sex: String = "m"
    @State private var heightFeet: Int = 5
    @State private var heightInches: Int = 10
    @State private var weight: Int = 168
    @State private var goalKcal: Int = 2200
    @State private var showingPaywall = false

    enum Step: Int, CaseIterable { case pitch, name, body, goal, ready }

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(alignment: .leading, spacing: 0) {
                progressDots
                    .padding(.top, 24)
                    .padding(.horizontal, 24)

                Spacer(minLength: 24)

                Group {
                    switch step {
                    case .pitch: pitchView
                    case .name:  nameView
                    case .body:  bodyView
                    case .goal:  goalView
                    case .ready: readyView
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallSheet(onSubscribe: {
                appModel.upgradeToPro()
                showingPaywall = false
                finish()
            }, onSkip: {
                showingPaywall = false
                finish()
            })
            .presentationDetents([.large])
            .presentationBackground(Theme.Palette.ink)
        }
    }

    // MARK: progress

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Theme.Palette.voltage : Theme.Palette.hairlineStrong)
                    .frame(width: s == step ? 28 : 14, height: 3)
                    .animation(.easeOut(duration: 0.4), value: step)
            }
            Spacer()
            VoCalWordmark()
        }
    }

    // MARK: pitch

    private var pitchView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("INTRODUCING")
                .eyebrow(Theme.Palette.pulse)
            (
                Text("The first calorie tracker that ")
                    .foregroundStyle(Theme.Palette.bone)
                + Text("actually listens.")
                    .foregroundStyle(Theme.Palette.voltage)
                    .font(Theme.Font.serif(48, weight: .medium, italic: true))
            )
            .font(Theme.Font.serif(48, weight: .medium))
            .lineSpacing(2)

            Text("Cal AI needs a photo. MyFitnessPal needs you to type. VoCal just needs you to talk.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.ash)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 14) {
                examplePill("medium fry from McDonald's")
                examplePill("grande iced oat latte from Starbucks")
                examplePill("Chipotle bowl, double chicken, guac")
            }
            .padding(.top, 22)
        }
    }

    private func examplePill(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.voltage)
            Text("\u{201C}\(text)\u{201D}")
                .font(Theme.Font.serif(15, weight: .regular, italic: true))
                .foregroundStyle(Theme.Palette.bone)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1)
        )
    }

    // MARK: name

    private var nameView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("01 · WHO YOU ARE")
                .eyebrow()
            Text("What should I call you?")
                .font(Theme.Font.serif(38, weight: .medium))
                .foregroundStyle(Theme.Palette.bone)

            TextField(
                "",
                text: $name,
                prompt: Text("Your first name").foregroundStyle(Theme.Palette.smoke)
            )
            .font(Theme.Font.serif(24, weight: .regular))
            .foregroundStyle(Theme.Palette.bone)
            .textInputAutocapitalization(.words)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.Palette.voltage).frame(height: 1.5)
            }
            .padding(.top, 12)
        }
    }

    // MARK: body

    private var bodyView: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("02 · BODY BASELINE")
                .eyebrow()
            Text("A few numbers, then we're done.")
                .font(Theme.Font.serif(32, weight: .medium))
                .foregroundStyle(Theme.Palette.bone)

            VStack(alignment: .leading, spacing: 18) {
                segmentPicker(label: "Sex", selection: $sex, options: [
                    ("m", "Male"), ("f", "Female"), ("x", "Prefer not")
                ])

                wheelGroup(label: "Height") {
                    HStack {
                        Picker("ft", selection: $heightFeet) {
                            ForEach(4...7, id: \.self) { Text("\($0)′").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 96)
                        .colorMultiply(Theme.Palette.bone)

                        Picker("in", selection: $heightInches) {
                            ForEach(0...11, id: \.self) { Text("\($0)″").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 96)
                        .colorMultiply(Theme.Palette.bone)
                    }
                }

                wheelGroup(label: "Weight") {
                    Picker("lb", selection: $weight) {
                        ForEach(90...320, id: \.self) { Text("\($0) lb").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 96)
                    .colorMultiply(Theme.Palette.bone)
                }
            }
        }
    }

    private func wheelGroup<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .eyebrow()
            content()
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1)
                )
        }
    }

    private func segmentPicker(
        label: String,
        selection: Binding<String>,
        options: [(String, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .eyebrow()
            HStack(spacing: 8) {
                ForEach(options, id: \.0) { value, title in
                    let active = selection.wrappedValue == value
                    Button { selection.wrappedValue = value } label: {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(active ? Theme.Palette.ink : Theme.Palette.bone)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule().fill(active ? Theme.Palette.voltage : Color.clear)
                                    .overlay(Capsule().strokeBorder(Theme.Palette.hairlineStrong, lineWidth: active ? 0 : 1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: goal

    private var goalView: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("03 · YOUR TARGET")
                .eyebrow()
            Text("What's your daily target?")
                .font(Theme.Font.serif(32, weight: .medium))
                .foregroundStyle(Theme.Palette.bone)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(goalKcal)")
                    .font(Theme.Font.serif(88, weight: .medium))
                    .foregroundStyle(Theme.Palette.voltage)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(goalKcal)))
                Text("kcal")
                    .font(Theme.Font.serif(24, weight: .regular, italic: true))
                    .foregroundStyle(Theme.Palette.smoke)
            }

            Slider(value: Binding(
                get: { Double(goalKcal) },
                set: { goalKcal = (Int($0) / 50) * 50 }
            ), in: 1200...4000, step: 50)
            .tint(Theme.Palette.voltage)

            HStack {
                Text("1,200")
                Spacer()
                Text("4,000")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.Palette.smoke)

            Text("You can change this any time. We'll nudge it up on high-strain days when you connect your Watch or WHOOP.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.ash)
                .padding(.top, 10)
        }
    }

    // MARK: ready

    private var readyView: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("04 · READY")
                .eyebrow(Theme.Palette.voltage)
            Text("Try it out.")
                .font(Theme.Font.serif(48, weight: .medium))
                .foregroundStyle(Theme.Palette.bone)
            Text("Tap the mic and say what you ate. We'll log it for you — restaurant macros included.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.ash)

            WaveformOrb(isActive: true, tint: Theme.Palette.voltage)
                .frame(width: 240, height: 240)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .pitch {
                GhostButton(title: "Back") {
                    withAnimation(.spring) {
                        step = Step(rawValue: step.rawValue - 1) ?? .pitch
                    }
                }
            }
            VoltageButton(title: ctaLabel, icon: step == .ready ? "checkmark" : "arrow.right") {
                advance()
            }
            .opacity(canAdvance ? 1 : 0.4)
            .allowsHitTesting(canAdvance)
        }
    }

    private var ctaLabel: String {
        switch step {
        case .pitch: "Get started"
        case .name:  "Continue"
        case .body:  "Continue"
        case .goal:  "Looks good"
        case .ready: "Start tracking"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .name: return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return true
        }
    }

    private func advance() {
        if step == .ready {
            showingPaywall = true
            return
        }
        withAnimation(.spring) {
            step = Step(rawValue: step.rawValue + 1) ?? .ready
        }
    }

    private func finish() {
        // Build the profile from collected onboarding data, fall back to any
        // pre-existing values for fields the user didn't fill in.
        var newProfile = appModel.profile
        newProfile.displayName = name.isEmpty ? appModel.profile.displayName : name
        newProfile.sex = sex
        newProfile.heightInches = Double(heightFeet * 12 + heightInches)
        newProfile.weightLbs = Double(weight)

        withAnimation(.easeOut(duration: 0.4)) {
            // completeOnboarding bundles profile + goal + flag + persist into one
            // atomic update so we never end up with a half-onboarded user on disk.
            appModel.completeOnboarding(profile: newProfile, calorieGoal: goalKcal)
        }
    }
}

#Preview {
    OnboardingFlow()
        .environmentObject(AppModel(
            totals: MockData.today,
            meals: [],
            profile: MockData.profile,
            hasCompletedOnboarding: false
        ))
        .preferredColorScheme(.dark)
}
