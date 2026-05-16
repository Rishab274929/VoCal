//
//  OnboardingFlow.swift
//  VoCal
//
//  Editorial onboarding. Five steps: pitch → name → body basics → goal → paywall.
//  Each step is a serif headline + one input. Progress is hairline dashes.
//

import SwiftUI
import AuthenticationServices

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
                    .padding(.horizontal, 28)

                // ScrollView so steps with tall content (body baseline's
                // three picker wheels, pitch's example pills + Google
                // sign-in button) don't get crushed on shorter phones
                // (iPhone SE / mini). Flex layout would otherwise squash
                // the wheels below 96pt and steal taps.
                ScrollView {
                    Group {
                        switch step {
                        case .pitch: pitchView
                        case .name:  nameView
                        case .body:  bodyView
                        case .goal:  goalView
                        case .ready: readyView
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)

                footer
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                    .padding(.top, 8)
            }
        }
        // NOTE — "Maybe later" is intentionally GONE from the onboarding
        // paywall. Per the product spec (and recent commit f49d351), the
        // post-onboarding paywall is now a HARD paywall: users must subscribe
        // (or restore an existing subscription) to reach the home screen.
        //
        // Mechanics: passing `nil` for `onSkip` causes PaywallSheet to:
        //   1. hide the X close button
        //   2. disable swipe-down dismissal via `.interactiveDismissDisabled`
        //   3. omit the "Maybe later" link in the footer
        // So removing the callback closes the bypass cleanly — no additional
        // changes needed in PaywallSheet itself.
        //
        // The free-tier user still has an escape hatch: ContentView gates
        // EVERY render behind the same hard paywall when entitlement is
        // .free, so even if the user somehow swiped past this sheet (e.g.
        // via a future iOS dismiss-gesture change), the next paint would
        // re-present the paywall.
        .sheet(isPresented: $showingPaywall) {
            PaywallSheet(onSubscribe: {
                appModel.upgradeToPro()
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

            appleSignInRow
                .padding(.top, 12)

            googleSignInRow
                .padding(.top, 4)
        }
    }

    /// Sign-in row state. Shared between the Apple + Google flows so we can
    /// disable both buttons while one is in flight (prevents a user from
    /// kicking off Google sign-in mid-Apple sheet and ending up with two
    /// half-completed sessions racing each other into the Keychain).
    ///
    /// The raw nonce for SiwA replay defense isn't held here — it lives in
    /// `AppleSignIn.shared` between `prepareNonce()` and
    /// `completeAuthorization(...)` so it survives across the system
    /// authorization sheet without leaking through SwiftUI @State.
    @State private var signingIn = false
    @State private var signInError: String?

    /// Sign in with Apple. Hard requirement for App Store submission per
    /// Apple Review Guideline 4.8: an app that offers Google sign-in MUST
    /// also offer SiwA. Uses `SignInWithAppleButton` for Apple's official
    /// visual treatment, then routes the credential through
    /// `AuthSession.completeSignInWithApple` for nonce-bound exchange with
    /// our backend.
    @ViewBuilder
    private var appleSignInRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            SignInWithAppleButton(.signIn) { request in
                // Stash a CSPRNG-derived nonce on the request. The raw value
                // stays in AppleSignIn.shared until completion so the backend
                // can verify the identity_token's `nonce` claim matches.
                let (_, hashed) = AppleSignIn.shared.prepareNonce()
                request.requestedScopes = [.fullName, .email]
                request.nonce = hashed
            } onCompletion: { result in
                Task { await handleAppleSignInResult(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 44)
            .disabled(signingIn)
            .opacity(signingIn ? 0.5 : 1)
        }
    }

    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Swift.Error>) async {
        signingIn = true
        defer { signingIn = false }
        switch result {
        case .success(let authorization):
            guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential else {
                signInError = "Apple sign-in didn't return a credential."
                return
            }
            do {
                try await AuthSession.shared.completeSignInWithApple(credential: cred)
                signInError = nil
                // Pre-fill the name field if SiwA gave us one on first sign-in.
                // After the first sign-in Apple returns nil for fullName even
                // on the same Apple ID, so this only fires once per account.
                if let pn = cred.fullName {
                    let first = pn.givenName?.trimmingCharacters(in: .whitespaces)
                    if let f = first, !f.isEmpty, name.isEmpty {
                        name = f
                    }
                }
            } catch {
                signInError = error.localizedDescription
            }
        case .failure(let error):
            // User cancellation is the dominant case — silently swallow it.
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                return
            }
            signInError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var googleSignInRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await signInWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    if signingIn {
                        ProgressView().controlSize(.small).tint(Theme.Palette.ink)
                    } else {
                        Image(systemName: "g.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.Palette.ink)
                    }
                    Text(signingIn ? "Opening Google…" : "Sign in with Google")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(Theme.Palette.bone))
            }
            .buttonStyle(.plain)
            .disabled(signingIn)

            if let err = signInError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.pulse)
            }
            Text("Optional. Skip and we'll keep your data device-only.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.smoke)
        }
    }

    private func signInWithGoogle() async {
        signingIn = true
        defer { signingIn = false }
        do {
            try await AuthSession.shared.signInWithGoogle()
            signInError = nil
            // Pre-fill the name field if Google gave us one — saves a step.
            if let displayName = AuthSession.shared.displayName, name.isEmpty {
                name = displayName.split(separator: " ").first.map(String.init) ?? displayName
            }
        } catch GoogleSignIn.Error.userCancelled {
            // No-op — user dismissed the sheet.
        } catch {
            signInError = error.localizedDescription
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
            .autocorrectionDisabled(true)
            .submitLabel(.next)
            .onSubmit { if canAdvance { advance() } }
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
                // "Prefer not" emits "" to match UserProfile.sex's documented
                // unspecified value (see Item.swift). The BodyFat heuristic
                // already routes empty/unknown to a wider-confidence midpoint.
                segmentPicker(label: "Sex", selection: $sex, options: [
                    ("m", "Male"), ("f", "Female"), ("", "Prefer not")
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
                // Thousands separator so a 4-digit goal reads "2,200"
                // instead of the cramped "2200" — matches the formatting
                // used everywhere else (TodayView hero, etc.)
                Text(goalKcal.formatted(.number))
                    .font(Theme.Font.serif(88, weight: .medium))
                    .foregroundStyle(Theme.Palette.voltage)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(goalKcal)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("kcal")
                    .font(Theme.Font.serif(24, weight: .regular, italic: true))
                    .foregroundStyle(Theme.Palette.smoke)
            }

            Slider(value: Binding(
                get: { Double(goalKcal) },
                set: { goalKcal = (Int($0) / 50) * 50 }
            ), in: 1200...4000, step: 50)
            .tint(Theme.Palette.voltage)
            .accessibilityLabel("Daily calorie target")
            .accessibilityValue("\(goalKcal.formatted(.number)) kilocalories")

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

        // Mark the post-onboarding paywall as already shown — we just showed
        // it as the last step of onboarding (`.ready` CTA → PaywallSheet).
        // Without this guard, ContentView.maybeShowOnboardingPaywall() would
        // re-present the same paywall the moment RootView swaps in the
        // ContentView, hitting the user with the same screen twice in 800ms.
        UserDefaults.standard.set(true, forKey: "vocal.didShowFirstPaywall")

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
