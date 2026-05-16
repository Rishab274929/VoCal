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
    private var remaining: Int { max(0, goal - eaten) }

    var body: some View {
        ZStack {
            // Outer ghost ring
            Circle()
                .stroke(Theme.Palette.hairline, lineWidth: 1)
                .padding(2)

            // Track
            Circle()
                .stroke(Theme.Palette.hairlineStrong, lineWidth: 10)

            // Progress (voltage)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [Theme.Palette.voltage.opacity(0.6), Theme.Palette.voltage, Theme.Palette.voltage],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.7), value: progress)
                .shadow(color: Theme.Palette.voltage.opacity(0.45), radius: 18)

            // Center stack
            VStack(spacing: 0) {
                Text("\(remaining)")
                    .font(Theme.Font.serif(size * 0.32, weight: .medium))
                    .foregroundStyle(Theme.Palette.bone)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(remaining)))
                Text("KCAL LEFT")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(Theme.Palette.smoke)
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
                    Capsule()
                        .fill(tint)
                        .frame(width: max(2, geo.size.width * progress))
                        .shadow(color: tint.opacity(0.4), radius: 6, y: 0)
                        .animation(.easeOut(duration: 0.55), value: progress)
                }
            }
            .frame(height: 4)
        }
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
                    Spacer()
                    Text("\(meal.calories)")
                        .font(Theme.Font.serif(28, weight: .medium))
                        .foregroundStyle(Theme.Palette.bone)
                        .monospacedDigit()
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
        switch meal.slot {
        case .breakfast: Theme.Palette.carbs
        case .lunch:     Theme.Palette.voltage
        case .dinner:    Theme.Palette.fat
        case .snack:     Theme.Palette.protein
        }
    }
}

// MARK: - Mic button — the brand statement

struct MicButton: View {
    var action: () -> Void
    @State private var pulse = false
    @State private var rotation = 0.0

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer pulse
                Circle()
                    .strokeBorder(Theme.Palette.pulse.opacity(0.55), lineWidth: 1.5)
                    .scaleEffect(pulse ? 1.85 : 1)
                    .opacity(pulse ? 0 : 1)
                Circle()
                    .strokeBorder(Theme.Palette.pulse.opacity(0.35), lineWidth: 1)
                    .scaleEffect(pulse ? 1.55 : 1)
                    .opacity(pulse ? 0 : 1)

                // Core orb
                Circle()
                    .fill(Theme.Palette.ink)
                    .overlay(
                        Circle().strokeBorder(Theme.Palette.pulse, lineWidth: 2)
                    )
                    .shadow(color: Theme.Palette.pulse.opacity(0.5), radius: 24)

                // Rotating tick marks (audio meter feel)
                ZStack {
                    ForEach(0..<24, id: \.self) { i in
                        Rectangle()
                            .fill(Theme.Palette.pulse.opacity(i % 3 == 0 ? 0.9 : 0.25))
                            .frame(width: 1, height: i % 3 == 0 ? 6 : 3)
                            .offset(y: -32)
                            .rotationEffect(.degrees(Double(i) / 24 * 360))
                    }
                }
                .rotationEffect(.degrees(rotation))

                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.Palette.bone)
            }
            .frame(width: 78, height: 78)
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
    }
}

// MARK: - Voice waveform orb — used inside the capture sheet

struct WaveformOrb: View {
    var isActive: Bool = true
    var tint: Color = Theme.Palette.pulse
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
            .background(
                Capsule()
                    .fill(Theme.Palette.voltage)
                    .shadow(color: Theme.Palette.voltage.opacity(0.35), radius: 22, y: 6)
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
            // Mic slot (the actual button overlays this gap so the row stays evenly spaced)
            Color.clear.frame(width: 86)
            tabButton(.coach)
            tabButton(.profile)
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background(
            Theme.Palette.ink.opacity(0.96)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            MicButton(action: onMic)
                .offset(y: -30)
        }
    }

    private func tabButton(_ tab: Tab) -> some View {
        let active = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 18, weight: active ? .bold : .regular))
                Text(tab.label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
            }
            .foregroundStyle(active ? Theme.Palette.voltage : Theme.Palette.smoke)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Streak badge

struct StreakBadge: View {
    let days: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Palette.pulse)
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
            Text("Vo")
                .font(Theme.Font.serif(20, weight: .semibold, italic: true))
                .foregroundStyle(Theme.Palette.bone)
            Text("Cal")
                .font(Theme.Font.serif(20, weight: .semibold, italic: true))
                .foregroundStyle(Theme.Palette.voltage)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.trailing, 4)
    }
}

// MARK: - Follow-up question card

struct FollowUpQuestionCard: View {
    let question: String
    @Binding var answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ONE QUICK CHECK")
                .eyebrow(Theme.Palette.pulse)
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
                        .strokeBorder(Theme.Palette.pulse.opacity(0.4), lineWidth: 1)
                )
        )
    }
}

// MARK: - Weight chart (lightweight Charts replacement)

struct WeightSparkline: View {
    let values: [Double]
    var tint: Color = Theme.Palette.voltage

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
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(role == .user ? Theme.Palette.voltage : Theme.Palette.inkSurface)
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

// MARK: - Background ambient (subtle voltage glow at top)

struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Theme.Palette.ink
            // Soft glow blob
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.Palette.voltage.opacity(0.10), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 240
                    )
                )
                .frame(width: 460, height: 460)
                .offset(x: -140, y: -360)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.Palette.pulse.opacity(0.06), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 220
                    )
                )
                .frame(width: 380, height: 380)
                .offset(x: 160, y: -200)
        }
        .ignoresSafeArea()
    }
}
