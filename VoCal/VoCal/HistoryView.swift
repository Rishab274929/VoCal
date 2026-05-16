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
        // Real aggregation over `appModel.meals`. Build a (date, kcal)
        // tuple for each of the last 7 calendar days (oldest left, today
        // right) and normalize against the week's peak so the tallest bar
        // hits the chart ceiling without exploding on a single 4000-kcal
        // day. Empty week renders a hairline + eyebrow placeholder.
        let week = weeklyCalorieTotals()
        let maxKcal = max(1, week.map { $0.calories }.max() ?? 0)
        let hasAnyData = week.contains { $0.calories > 0 }
        let avg = hasAnyData
            ? Int((Double(week.map { $0.calories }.reduce(0, +)) / 7.0).rounded())
            : 0

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CALORIES · 7 DAYS")
                        .eyebrow()
                    if hasAnyData {
                        Text("avg \(avg.formatted()) kcal")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Palette.bone)
                    } else {
                        Text("LOG A FEW DAYS TO SEE YOUR TREND")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(Theme.Palette.smoke)
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Theme.Palette.voltage).frame(width: 6, height: 6)
                    Text("today")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.smoke)
                }
            }

            if hasAnyData {
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(Array(week.enumerated()), id: \.offset) { i, day in
                        let isToday = i == week.count - 1
                        let normalized = CGFloat(day.calories) / CGFloat(maxKcal)
                        let barHeight = max(2, normalized * 120)
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Theme.Palette.hairlineStrong)
                                    .frame(width: 16, height: 120)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isToday ? Theme.Palette.voltage : Theme.Palette.bone.opacity(0.5))
                                    .frame(width: 16, height: barHeight)
                                    .shadow(color: isToday ? Theme.Palette.voltage.opacity(0.5) : .clear, radius: 8)
                            }
                            Text(weekdayLetter(for: day.date, isToday: isToday))
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(1.0)
                                .foregroundStyle(isToday ? Theme.Palette.voltage : Theme.Palette.smoke)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                // Hairline placeholder keeps the card height stable so the
                // surrounding layout doesn't reflow as the user logs their
                // first meals across multiple days.
                Rectangle()
                    .fill(Theme.Palette.hairline)
                    .frame(height: 1)
                    .padding(.vertical, 60)
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
        let hasHistory = weights.count >= 2
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
                // Suppress the delta when there's no history — "+0.0 lb vs
                // 4 weeks ago" is misleading for a brand-new install.
                if hasHistory {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(deltaString(delta, unit: "lb"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(delta < 0 ? Theme.Palette.voltage : Theme.Palette.pulse)
                        Text("vs 4 weeks ago")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Palette.smoke)
                    }
                } else {
                    Text("LOG MORE TO SEE TREND")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.Palette.smoke)
                }
            }
            if hasHistory {
                WeightSparkline(values: Array(weights), tint: Theme.Palette.voltage)
                    .frame(height: 88)
            } else {
                // Hairline placeholder so the card has a consistent shape
                // even before any history exists.
                Rectangle()
                    .fill(Theme.Palette.hairline)
                    .frame(height: 1)
                    .padding(.vertical, 40)
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

    // MARK: body-fat card

    private var bodyFatCard: some View {
        // Empty-state branch: a brand-new user has no bodyFat samples, so
        // showing "17.0%" with a fake delta would lie about their data.
        // Render an empty-state card with the same dimensions instead.
        let bfs = appModel.bodyMetrics.compactMap { $0.bodyFatPct }.reversed()
        if bfs.isEmpty {
            return AnyView(emptyBodyFatCard)
        }
        let current = bfs.last ?? 0
        let first = bfs.first ?? current
        let delta = current - first

        return AnyView(HStack(alignment: .top, spacing: 16) {
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
                    Image(systemName: delta <= 0 ? "arrow.down.right" : "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(delta <= 0 ? Theme.Palette.voltage : Theme.Palette.pulse)
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
                        Text("Retake")
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
        ))
    }

    private var emptyBodyFatCard: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("BODY FAT")
                    .eyebrow()
                Text("Take your first reading.")
                    .font(Theme.Font.serif(22, weight: .medium, italic: true))
                    .foregroundStyle(Theme.Palette.bone)
                Text("Two photos. Confidence band included.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.smoke)
                Spacer(minLength: 4)
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
            ZStack {
                Circle()
                    .stroke(Theme.Palette.hairlineStrong, lineWidth: 8)
                Image(systemName: "figure.arms.open")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.Palette.smoke)
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
        // Real aggregation from `appModel.meals`. Group by start-of-day,
        // sum kcal per day, sort newest first, and cap to the most recent
        // ~14 days that actually have logs. Days with zero meals are
        // skipped so a sparse user doesn't see a wall of "0 / 2200" rows.
        let recentDays = recentDailySummaries(limit: 14)
        let goal = max(1, appModel.totals.calorieGoal)

        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Recent days", eyebrow: "Past two weeks")
            if recentDays.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your daily summaries will appear here once you log meals.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.smoke)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(Theme.Palette.inkSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                        )
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(recentDays.enumerated()), id: \.offset) { _, day in
                        HistoryRow(date: day.date, calories: day.calories, goal: goal)
                    }
                }
            }
        }
    }

    // MARK: aggregation helpers

    /// (date, kcal) tuples for the last 7 calendar days, oldest at index
    /// 0 and today at index 6. Days with no meals contribute 0 — the
    /// chart's normalization step handles those without divide-by-zero.
    private func weeklyCalorieTotals() -> [(date: Date, calories: Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        // Bucket meals into start-of-day keys once instead of filtering
        // the meal list 7 times. O(n) vs O(7n) — matters when a power
        // user has hundreds of logged meals.
        var buckets: [Date: Int] = [:]
        for meal in appModel.meals {
            let day = cal.startOfDay(for: meal.loggedAt)
            buckets[day, default: 0] += meal.calories
        }
        return (0..<7).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, buckets[day] ?? 0)
        }
    }

    /// Newest-first list of (date, kcal) tuples for days where the user
    /// actually logged something. Capped at `limit` so the section never
    /// becomes a scroll trap.
    private func recentDailySummaries(limit: Int) -> [(date: Date, calories: Int)] {
        let cal = Calendar.current
        var buckets: [Date: Int] = [:]
        for meal in appModel.meals {
            let day = cal.startOfDay(for: meal.loggedAt)
            buckets[day, default: 0] += meal.calories
        }
        return buckets
            .map { (date: $0.key, calories: $0.value) }
            .filter { $0.calories > 0 }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }

    /// Single-letter weekday label keyed off the bar's date. Today gets
    /// "T" so the rightmost bar always reads consistently regardless of
    /// what day of the week it is.
    private func weekdayLetter(for date: Date, isToday: Bool) -> String {
        if isToday { return "T" }
        let weekday = Calendar.current.component(.weekday, from: date)
        // Calendar weekday: 1 = Sun, 2 = Mon, ..., 7 = Sat
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        return letters[(weekday - 1) % 7]
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
