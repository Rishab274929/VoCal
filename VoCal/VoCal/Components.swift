//
//  Components.swift
//  VoCal
//
//  Editorial component library. Big serif numerals, thin hairlines,
//  tactile accent fills. Everything reuses Theme tokens — never raw colors.
//

import SwiftUI

// MARK: - Display number — the editorial hero stat

/// Massive serif numeral with a tiny tracked label underneath. The signature
/// typographic move of the app — used for kcal-remaining, BF%, etc.
struct DisplayNumber: View {
    let value: Int
    let label: String
    var unit: String = "kcal"
    var tint: Color = Theme.Palette.bone
    var size: CGFloat = 92

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(value)")
                    .font(Theme.Font.serif(size, weight: .medium))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(value)))
                Text(unit)
                    .font(Theme.Font.serif(size * 0.28, weight: .regular, italic: true))
                    .foregroundStyle(Theme.Palette.smoke)
                    .baselineOffset(size * 0.10)
            }
            Text(label)
                .eyebrow()
        }
    }
}

// MARK: - Calorie ring — concentric thin rings, voltage stroke

struct CalorieRing: View {
    let eaten: Int
    let goal: Int
    var size: CGFloat = 248

    private var progress: Double { min(1.0, Double(eaten) / Double(max(1, goal))) }
    private var overshoot: Int { max(0, eaten - goal) }
    private var isOver: Bool { eaten > goal }
    private var remaining: Int { max(0, goal - eaten) }

    /// Monochrome pivot: stroke is `paper` (pure white) when on-track and
    /// flips to `bone` (warm off-white) when over-goal. The chromatic
    /// shift is gone — we lean on the center label + a softer stroke to
    /// signal "past budget" without the old coral alarm.
    private var strokeTint: Color { isOver ? Theme.Palette.bone : Theme.Palette.paper }

    var body: some View {
        ZStack {
            // Outer ghost ring
            Circle()
                .stroke(Theme.Palette.hairline, lineWidth: 1)
                .padding(2)

            // Track
            Circle()
                .stroke(Theme.Palette.hairlineStrong, lineWidth: 10)

            // Progress — solid white when on-track, desaturated bone when over.
            // No angular gradient: monochrome wants a flat, deliberate stroke.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(strokeTint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.7), value: progress)
                .animation(.easeOut(duration: 0.3), value: isOver)
                // A tiny halo keeps the ring from feeling stenciled-flat
                // against pure black — but at 8pt radius, not the old 18pt
                // chromatic bloom.
                .shadow(color: Theme.Palette.paper.opacity(0.18), radius: 8)

            // Center stack
            VStack(spacing: 0) {
                Text("\(isOver ? overshoot : remaining)")
                    .font(Theme.Font.serif(size * 0.32, weight: .medium))
                    .foregroundStyle(Theme.Palette.paper)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(isOver ? overshoot : remaining)))
                Text(isOver ? "KCAL OVER" : "KCAL LEFT")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(isOver ? Theme.Palette.bone : Theme.Palette.smoke)
                    .padding(.top, 6)
                HStack(spacing: 6) {
                    Text("\(eaten)")
                        .font(Theme.Font.mono(11, weight: .medium))
                        .foregroundStyle(Theme.Palette.ash)
                    Text("of")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.smoke)
                    Text("\(goal)")
                        .font(Theme.Font.mono(11, weight: .medium))
                        .foregroundStyle(Theme.Palette.ash)
                }
                .padding(.top, 8)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOver
            ? "Calorie ring — over goal by \(overshoot) kcal. \(eaten) eaten of \(goal) goal."
            : "Calorie ring — \(remaining) kcal remaining. \(eaten) eaten of \(goal) goal.")
    }
}

// MARK: - Macro bar — vertical chunky bar with eyebrow label

struct MacroBar: View {
    let label: String
    let eaten: Int
    let goal: Int
    let tint: Color

    private var progress: Double { min(1.0, Double(eaten) / Double(max(1, goal))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(Theme.Palette.smoke)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(eaten)")
                        .font(Theme.Font.mono(15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.bone)
                    Text("/")
                        .font(Theme.Font.mono(12, weight: .regular))
                        .foregroundStyle(Theme.Palette.smoke)
                    Text("\(goal)g")
                        .font(Theme.Font.mono(12, weight: .regular))
                        .foregroundStyle(Theme.Palette.smoke)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.hairlineStrong)
                    // When eaten == 0, render 0pt fill — not the 2pt sliver
                    // that would otherwise look like a stray dot next to the
                    // hairline track. Below ~3pt the capsule renders fuzzy
                    // anyway, so we floor at 3pt for any non-zero progress.
                    if eaten > 0 {
                        Capsule()
                            .fill(tint)
                            .frame(width: max(3, geo.size.width * progress))
                            // Monochrome pivot: drop the colored bloom; a 1pt
                            // hairline alignment + the macro hue itself is
                            // signal enough.
                            .animation(.easeOut(duration: 0.55), value: progress)
                    }
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(eaten) of \(goal) grams")
    }
}

// MARK: - Macro pill — compact inline macro display

struct MacroPill: View {
    let letter: String
    let value: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6)
            (
                Text(letter)
                    .foregroundStyle(Theme.Palette.smoke)
                + Text(" \(value)")
                    .foregroundStyle(Theme.Palette.bone)
                + Text("g")
                    .foregroundStyle(Theme.Palette.smoke)
            )
            .font(Theme.Font.mono(12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Meal card — editorial row with vertical accent stripe

struct MealCard: View {
    let meal: MealEntry

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(slotColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(meal.slot.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(2.0)
                        .foregroundStyle(slotColor)
                    Text("·")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.Palette.smoke)
                    Text(meal.loggedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Palette.smoke)
                    if meal.source == .voice {
                        Image(systemName: "waveform")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.Palette.smoke)
                    } else if meal.source == .photo {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Palette.smoke)
                    }
                    Spacer(minLength: 8)
                    // 4-digit single-meal kcal (e.g. 1,250 cheat burrito) can
                    // squeeze the eyebrow/time row. lineLimit(1) + scale
                    // protects without dropping the serif weight.
                    Text("\(meal.calories)")
                        .font(Theme.Font.serif(28, weight: .medium))
                        .foregroundStyle(Theme.Palette.bone)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Text(meal.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.bone)
                    .lineLimit(1)

                if !meal.detail.isEmpty {
                    Text(meal.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.ash)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    MacroPill(letter: "P", value: meal.protein, tint: Theme.Palette.protein)
                    MacroPill(letter: "C", value: meal.carbs, tint: Theme.Palette.carbs)
                    MacroPill(letter: "F", value: meal.fat, tint: Theme.Palette.fat)
                }
                .padding(.top, 2)
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Palette.inkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    private var slotColor: Color {
        // Monochrome pivot: lunch was the lime accent; now it's pure paper
        // so the meal-card column reads as part of the type, not branding.
        // Other slots keep their macro hues because they map to time of day
        // in muscle memory (warm amber morning, cool blue evening).
        switch meal.slot {
        case .breakfast: Theme.Palette.carbs
        case .lunch:     Theme.Palette.paper
        case .dinner:    Theme.Palette.fat
        case .snack:     Theme.Palette.protein
        }
    }
}

// MARK: - Mic button — the brand statement

struct MicButton: View {
    var action: () -> Void
    var size: CGFloat = 64
    @State private var pulse = false
    @State private var rotation = 0.0

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer pulse — white glow expanding (no coral)
                Circle()
                    .strokeBorder(Theme.Palette.paper.opacity(0.45), lineWidth: 1.5)
                    .scaleEffect(pulse ? 1.7 : 1)
                    .opacity(pulse ? 0 : 1)
                Circle()
                    .strokeBorder(Theme.Palette.paper.opacity(0.28), lineWidth: 1)
                    .scaleEffect(pulse ? 1.45 : 1)
                    .opacity(pulse ? 0 : 1)

                // Core orb — paper-white ring on ink (the brand statement
                // in monochrome: the mic is the single bright artifact on
                // the page, the way the starfield logo concentrates light)
                Circle()
                    .fill(Theme.Palette.ink)
                    .overlay(
                        Circle().strokeBorder(Theme.Palette.paper, lineWidth: 2)
                    )
                    .shadow(color: Theme.Palette.paper.opacity(0.35), radius: 14)

                // Rotating tick marks (audio meter feel)
                ZStack {
                    ForEach(0..<24, id: \.self) { i in
                        Rectangle()
                            .fill(Theme.Palette.paper.opacity(i % 3 == 0 ? 0.85 : 0.22))
                            .frame(width: 1, height: i % 3 == 0 ? 5 : 2.5)
                            .offset(y: -(size * 0.42))
                            .rotationEffect(.degrees(Double(i) / 24 * 360))
                    }
                }
                .rotationEffect(.degrees(rotation))

                Image(systemName: "mic.fill")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(Theme.Palette.paper)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                pulse = true
            }
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
        .accessibilityLabel("Log a meal with your voice")
        .accessibilityHint("Opens the voice capture sheet")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Voice waveform orb — used inside the capture sheet

struct WaveformOrb: View {
    var isActive: Bool = true
    // Monochrome pivot: default to pure paper. Callers that explicitly pass
    // a tint (legacy lime/coral references in screens) still win — that's
    // intentional so the visual treatment is one place to audit.
    var tint: Color = Theme.Palette.paper
    @State private var animate = false

    var body: some View {
        ZStack {
            // Bloom layers
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .strokeBorder(tint.opacity(0.35 - Double(i) * 0.07), lineWidth: 1)
                    .scaleEffect(animate ? 1 + 0.18 * Double(i + 1) : 0.6)
                    .opacity(animate ? 0 : 0.7)
                    .animation(
                        .easeOut(duration: 2.2)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.42),
                        value: animate
                    )
            }

            // Core glowing orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint, tint.opacity(0.0)],
                        center: .center,
                        startRadius: 4,
                        endRadius: 120
                    )
                )
                .frame(width: 220, height: 220)

            Circle()
                .fill(Theme.Palette.ink)
                .frame(width: 158, height: 158)
                .overlay(
                    Circle().strokeBorder(tint, lineWidth: 2)
                )

            // Animated waveform bars
            HStack(alignment: .center, spacing: 7) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(tint)
                        .frame(width: 5, height: animate ? CGFloat(28 + (i * 13) % 38) : 18)
                        .animation(
                            .easeInOut(duration: 0.42 + Double(i) * 0.07)
                                .repeatForever(autoreverses: true),
                            value: animate
                        )
                }
            }
        }
        .onAppear { animate = isActive }
        .onChange(of: isActive) { _, newValue in
            animate = newValue
        }
    }
}

// MARK: - Section header — editorial eyebrow + serif title

struct SectionHeader: View {
    let title: String
    var eyebrow: String? = nil
    var trailing: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.0)
                    .foregroundStyle(Theme.Palette.smoke)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.Font.serif(22, weight: .semibold))
                    .foregroundStyle(Theme.Palette.bone)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.smoke)
                }
            }
        }
    }
}

// MARK: - Primary CTA button (voltage filled)

struct VoltageButton: View {
    let title: String
    var icon: String? = nil
    var fullWidth: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Theme.Palette.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            // Monochrome pivot: pure paper-on-ink. Reads like a pressed
            // chiclet key — high-contrast, no chroma, no glow.
            .background(
                Capsule()
                    .fill(Theme.Palette.paper)
                    .shadow(color: Color.black.opacity(0.45), radius: 18, y: 6)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ghost button — outlined hairline

struct GhostButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = Theme.Palette.bone
    var fullWidth: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                Capsule()
                    .strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab bar — custom editorial replacement for stock TabView

struct EditorialTabBar: View {
    enum Tab: Hashable, CaseIterable {
        case today, progress, coach, profile

        var symbol: String {
            switch self {
            case .today:    "circle.dotted"
            case .progress: "chart.bar.xaxis"
            case .coach:    "bubble.left.and.text.bubble.right"
            case .profile:  "person"
            }
        }
        var label: String {
            switch self {
            case .today:    "Today"
            case .progress: "Progress"
            case .coach:    "Coach"
            case .profile:  "You"
            }
        }
    }

    @Binding var selection: Tab
    var onMic: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.today)
            tabButton(.progress)
            // Mic sits INLINE in the center slot rather than floating with
            // an offset. The old floating overlay was extending the
            // perceived bar height by ~30pt + the FAB's shadow radius, and
            // overhanging into content above. Inlined, it's just a button.
            //
            // Note: MicButton's rotating tick marks render at -(size*0.42)
            // from the orb center. With size=52 that's ~22pt above the orb,
            // so the slot needs vertical room — DON'T pull it up with a
            // negative top padding (the old `-2` clipped the topmost tick
            // against the bar's hairline border).
            MicButton(action: onMic, size: 52)
                .frame(width: 86)
            tabButton(.coach)
            tabButton(.profile)
        }
        .padding(.top, 8)
        .padding(.bottom, 0)
        .background(
            Theme.Palette.ink
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(_ tab: Tab) -> some View {
        let active = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 17, weight: active ? .bold : .regular))
                Text(tab.label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
            }
            // Monochrome pivot: active tab is `paper`, inactive `smoke`.
            // No more lime line — the contrast is white vs mid-gray.
            .foregroundStyle(active ? Theme.Palette.paper : Theme.Palette.smoke)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : [.isButton])
    }
}

// MARK: - Streak badge

struct StreakBadge: View {
    let days: Int

    var body: some View {
        HStack(spacing: 6) {
            // Monochrome pivot: flame to a paper-tinted icon. Keeps the
            // flame metaphor for streaks, drops the alarm chroma.
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Palette.paper)
            Text("\(days)")
                .font(Theme.Font.mono(13, weight: .semibold))
                .foregroundStyle(Theme.Palette.bone)
            Text("DAY")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Theme.Palette.smoke)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule().strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1)
        )
    }
}

// MARK: - Wordmark

struct VoCalWordmark: View {
    var body: some View {
        HStack(spacing: 0) {
            // Monochrome pivot: matches the starfield-on-black brand mark.
            // "Vo" in bone (warm off-white), "Cal" in pure paper so the
            // wordmark still has a typographic inflection without color.
            Text("Vo")
                .font(Theme.Font.serif(20, weight: .semibold, italic: true))
                .foregroundStyle(Theme.Palette.bone)
            Text("Cal")
                .font(Theme.Font.serif(20, weight: .semibold, italic: true))
                .foregroundStyle(Theme.Palette.paper)
        }
        .fixedSize(horizontal: true, vertical: false)
        // Italic glyphs overshoot their typographic frame on both sides;
        // adding hairline padding keeps the wordmark off the screen edge
        // on rounded-corner devices (iPhone 17 Pro etc.).
        .padding(.horizontal, 4)
    }
}

// MARK: - Follow-up question card

struct FollowUpQuestionCard: View {
    let question: String
    @Binding var answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Monochrome pivot: eyebrow + card outline both shift from
            // coral to paper. The card stands out by sheer luminance
            // contrast against the inkRaised surface.
            Text("ONE QUICK CHECK")
                .eyebrow(Theme.Palette.paper)
            Text(question)
                .font(Theme.Font.serif(24, weight: .medium))
                .foregroundStyle(Theme.Palette.bone)
                .fixedSize(horizontal: false, vertical: true)
            TextField("", text: $answer, prompt: Text("Your answer").foregroundStyle(Theme.Palette.smoke))
                .textInputAutocapitalization(.sentences)
                .foregroundStyle(Theme.Palette.bone)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1)
                )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Palette.inkRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Palette.paper.opacity(0.35), lineWidth: 1)
                )
        )
    }
}

// MARK: - Weight chart (lightweight Charts replacement)

struct WeightSparkline: View {
    let values: [Double]
    // Monochrome pivot: default tint is paper. Callers passing an explicit
    // tint (e.g. directional weight change) still win.
    var tint: Color = Theme.Palette.paper

    private var range: (min: Double, max: Double) {
        let mn = values.min() ?? 0
        let mx = values.max() ?? 1
        let pad = (mx - mn) * 0.15
        return (mn - pad, mx + pad)
    }

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                // Hairline grid
                ForEach(0..<3, id: \.self) { i in
                    Path { p in
                        let y = geo.size.height * CGFloat(i + 1) / 4
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Theme.Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }

                // Fill
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    p.addLine(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.35), tint.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Line
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // Last dot
                if let last = pts.last {
                    Circle().fill(tint).frame(width: 8, height: 8).position(last)
                    Circle().strokeBorder(Theme.Palette.ink, lineWidth: 2).frame(width: 8, height: 8).position(last)
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let (mn, mx) = range
        let span = max(0.0001, mx - mn)
        return values.enumerated().map { idx, v in
            let x = size.width * CGFloat(idx) / CGFloat(values.count - 1)
            let y = size.height * (1 - CGFloat((v - mn) / span))
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Coach bubble

struct CoachBubble: View {
    let role: CoachMessage.Role
    let content: String

    var body: some View {
        HStack {
            if role == .user { Spacer(minLength: 40) }
            Text(content)
                .font(.system(size: 15))
                .foregroundStyle(role == .user ? Theme.Palette.ink : Theme.Palette.bone)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                // Monochrome pivot: user bubble flips from lime to paper.
                // Reads like an iMessage in the editorial palette — high
                // contrast, no chroma.
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(role == .user ? Theme.Palette.paper : Theme.Palette.inkSurface)
                )
                .overlay(
                    role == .assistant
                    ? RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                    : nil
                )
            if role == .assistant { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Background ambient (monochrome — ink with a soft top fade)

struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Theme.Palette.ink
            // Monochrome pivot: dropped the lime + coral radial blobs.
            // A single very-subtle linear lift at the top keeps the screen
            // from feeling like a flat black PDF without painting in any
            // hue. Reads as ambient room light, not branding.
            LinearGradient(
                colors: [
                    Theme.Palette.paper.opacity(0.04),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}
