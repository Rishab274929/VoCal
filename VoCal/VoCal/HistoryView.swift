//
//  HistoryView.swift  (renamed conceptually to "Progress")
//  VoCal
//
//  Progress: kcal trend, weight trend, body-fat trend, recent days log.
//  Replaces the old History tab with a richer multi-metric editorial view.
//

import SwiftUI

struct ProgressScreen: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showingBFCapture = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                    .padding(.top, 4)
                weeklyKcalChart
                weightCard
                bodyFatCard
                pastDaysList
                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showingBFCapture) {
            BodyFatPhotoSheet()
                .presentationDetents([.large])
                .presentationBackground(Theme.Palette.ink)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PROGRESS")
                .eyebrow(Theme.Palette.pulse)
            Text("Two weeks at a glance.")
                .font(Theme.Font.serif(28, weight: .medium))
                .foregroundStyle(Theme.Palette.bone)
        }
    }

    // MARK: weekly kcal bar chart

    private var weeklyKcalChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CALORIES · 7 DAYS")
                        .eyebrow()
                    Text("avg 1,940 kcal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.bone)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Theme.Palette.voltage).frame(width: 6, height: 6)
                    Text("today")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.smoke)
                }
            }

            HStack(alignment: .bottom, spacing: 12) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.Palette.hairlineStrong)
                                .frame(width: 16, height: 120)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(i == 6 ? Theme.Palette.voltage : Theme.Palette.bone.opacity(0.5))
                                .frame(width: 16, height: barHeights[i])
                                .shadow(color: i == 6 ? Theme.Palette.voltage.opacity(0.5) : .clear, radius: 8)
                        }
                        Text(weekday(i))
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(i == 6 ? Theme.Palette.voltage : Theme.Palette.smoke)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Palette.inkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
        )
    }

    // MARK: weight card

    private var weightCard: some View {
        let weights = appModel.bodyMetrics.map { $0.weightLbs }.reversed()
        let current = weights.last ?? appModel.profile.weightLbs
        let first = weights.first ?? current
        let delta = current - first

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WEIGHT")
                        .eyebrow()
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f", current))
                            .font(Theme.Font.serif(32, weight: .medium))
                            .foregroundStyle(Theme.Palette.bone)
                            .monospacedDigit()
                        Text("lb")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Palette.smoke)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(deltaString(delta, unit: "lb"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(delta < 0 ? Theme.Palette.voltage : Theme.Palette.pulse)
                    Text("vs 4 weeks ago")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.smoke)
                }
            }
            WeightSparkline(values: Array(weights), tint: Theme.Palette.voltage)
                .frame(height: 88)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Palette.inkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
        )
    }

    // MARK: body-fat card

    private var bodyFatCard: some View {
        let bfs = appModel.bodyMetrics.compactMap { $0.bodyFatPct }.reversed()
        let current = bfs.last ?? 17.0
        let first = bfs.first ?? current
        let delta = current - first

        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Text("BODY FAT")
                    .eyebrow()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", current))
                        .font(Theme.Font.serif(48, weight: .medium))
                        .foregroundStyle(Theme.Palette.bone)
                        .monospacedDigit()
                    Text("%")
                        .font(Theme.Font.serif(18, weight: .regular, italic: true))
                        .foregroundStyle(Theme.Palette.smoke)
                }
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Palette.voltage)
                    Text(String(format: "%.1f pts in 30d", abs(delta)))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.ash)
                }
                Spacer()
                Button {
                    showingBFCapture = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Take baseline")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.Palette.voltage)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().strokeBorder(Theme.Palette.voltage, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            // Big bold ring visualization
            ZStack {
                Circle()
                    .stroke(Theme.Palette.hairlineStrong, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(0.5, current / 40.0))
                    .stroke(
                        AngularGradient(
                            colors: [Theme.Palette.pulse, Theme.Palette.voltage, Theme.Palette.voltage],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Image(systemName: "figure.arms.open")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.Palette.bone)
            }
            .frame(width: 88, height: 88)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Palette.inkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
        )
    }

    // MARK: past days

    private var pastDaysList: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Recent days", eyebrow: "Past two weeks")
            VStack(spacing: 8) {
                ForEach(Array(MockData.historySummaries.enumerated()), id: \.offset) { _, day in
                    HistoryRow(date: day.date, calories: day.calories, goal: day.goal)
                }
            }
        }
    }

    // MARK: helpers

    private let barHeights: [CGFloat] = [70, 86, 64, 96, 110, 78, 96]

    private func weekday(_ i: Int) -> String {
        ["M", "T", "W", "T", "F", "S", "S"][i]
    }

    private func deltaString(_ value: Double, unit: String) -> String {
        let sign = value < 0 ? "−" : "+"
        return "\(sign)\(String(format: "%.1f", abs(value))) \(unit)"
    }
}

private struct HistoryRow: View {
    let date: Date
    let calories: Int
    let goal: Int

    private var progress: Double { min(1.2, Double(calories) / Double(max(1, goal))) }
    private var overGoal: Bool { calories > goal }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Palette.bone)
                    .textCase(.uppercase)
                Text(date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.smoke)
            }
            .frame(width: 50, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.hairlineStrong)
                    Capsule()
                        .fill(overGoal ? Theme.Palette.pulse : Theme.Palette.voltage)
                        .frame(width: max(2, geo.size.width * min(1, progress)))
                }
            }
            .frame(height: 4)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(calories)")
                    .font(Theme.Font.mono(13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.bone)
                Text("/ \(goal)")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Palette.smoke)
            }
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Theme.Palette.inkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
        )
    }
}

#Preview {
    ProgressScreen()
        .environmentObject(AppModel(
            totals: MockData.today,
            meals: MockData.recentMeals,
            profile: MockData.profile,
            bodyMetrics: MockData.bodyMetrics
        ))
        .preferredColorScheme(.dark)
        .background(Theme.Palette.ink)
}
