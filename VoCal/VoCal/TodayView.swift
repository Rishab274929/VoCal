//
//  TodayView.swift
//  VoCal
//
//  Editorial daily dashboard. The big serif kcal-remaining is the hero;
//  macros sit underneath as thin precision bars; today's meals stack as
//  hairline cards with vertical accent stripes.
//

import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var showingVoice: Bool
    @Binding var showingPhoto: Bool
    @Binding var showingBarcode: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                topBar
                heroBlock
                ringBlock
                macrosBlock
                mealsBlock
                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
        }
        .background(Color.clear)
        .scrollIndicators(.hidden)
    }

    // MARK: top — wordmark + streak + camera

    private var topBar: some View {
        HStack(spacing: 10) {
            VoCalWordmark()
            Spacer()
            Button { showingBarcode = true } label: {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.bone)
                    .frame(width: 32, height: 32)
                    .background(Circle().strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button { showingPhoto = true } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.bone)
                    .frame(width: 32, height: 32)
                    .background(Circle().strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            StreakBadge(days: appModel.profile.streakDays)
        }
    }

    // MARK: hero — serif "kcal left" headline

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(greetingLine.uppercased())
                .eyebrow()
            Text(serifLine)
                .font(Theme.Font.serif(36, weight: .medium, italic: false))
                .foregroundStyle(Theme.Palette.bone)
                .lineSpacing(2)
        }
        .padding(.top, 4)
    }

    private var greetingLine: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let prefix: String
        switch hour {
        case 5..<12:  prefix = "Morning"
        case 12..<17: prefix = "Afternoon"
        case 17..<22: prefix = "Evening"
        default:      prefix = "Late night"
        }
        return "\(prefix) · \(appModel.profile.displayName)"
    }

    private var serifLine: AttributedString {
        let remaining = appModel.totals.calorieRemaining
        // Group the number with thousands separators so "1880" reads as "1,880"
        // and the headline fits on two lines instead of three on iPhone 17 Pro.
        let formatted = remaining.formatted(.number)
        var s = AttributedString("You have ")
        s.foregroundColor = Theme.Palette.smoke
        var n = AttributedString("\(formatted) kcal")
        n.font = Theme.Font.serif(36, weight: .medium, italic: true)
        n.foregroundColor = Theme.Palette.voltage
        var tail = AttributedString(" left today.")
        tail.foregroundColor = Theme.Palette.ash
        s.append(n)
        s.append(tail)
        return s
    }

    // MARK: ring — editorial centerpiece

    private var ringBlock: some View {
        HStack(alignment: .top, spacing: 20) {
            CalorieRing(eaten: appModel.totals.caloriesEaten, goal: appModel.totals.calorieGoal, size: 168)

            VStack(alignment: .leading, spacing: 14) {
                statColumn(label: "EATEN", value: appModel.totals.caloriesEaten, tint: Theme.Palette.bone)
                Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                statColumn(label: "GOAL", value: appModel.totals.calorieGoal, tint: Theme.Palette.ash)
                Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                statColumn(label: "REMAINING", value: max(0, appModel.totals.calorieGoal - appModel.totals.caloriesEaten), tint: Theme.Palette.voltage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Palette.inkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
        )
    }

    private func statColumn(label: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(2.0)
                .foregroundStyle(Theme.Palette.smoke)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(Theme.Font.serif(24, weight: .medium))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                Text("kcal")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.smoke)
            }
        }
    }

    // MARK: macros

    private var macrosBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Macros", eyebrow: "Today")
            VStack(spacing: 18) {
                MacroBar(label: "Protein", eaten: appModel.totals.proteinEaten, goal: appModel.totals.proteinGoal, tint: Theme.Palette.protein)
                MacroBar(label: "Carbs",   eaten: appModel.totals.carbsEaten,   goal: appModel.totals.carbsGoal,   tint: Theme.Palette.carbs)
                MacroBar(label: "Fat",     eaten: appModel.totals.fatEaten,     goal: appModel.totals.fatGoal,     tint: Theme.Palette.fat)
            }
        }
        .padding(.top, 4)
    }

    // MARK: meals

    private var mealsBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(
                title: "Today's log",
                eyebrow: "\(appModel.meals.count) entries",
                trailing: nil
            )
            if appModel.meals.isEmpty {
                emptyMealsCard
            } else {
                VStack(spacing: 10) {
                    ForEach(appModel.meals) { meal in
                        MealCard(meal: meal)
                    }
                }
            }
        }
    }

    private var emptyMealsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.Palette.voltage)
            Text("Nothing logged yet")
                .font(Theme.Font.serif(20, weight: .medium, italic: true))
                .foregroundStyle(Theme.Palette.bone)
            Text("Tap the mic and just say what you ate.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.smoke)
                .multilineTextAlignment(.center)

            Button {
                showingVoice = true
            } label: {
                Text("Say something")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.Palette.voltage))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Palette.inkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
        )
    }
}

#Preview {
    @Previewable @State var showing = false
    @Previewable @State var photo = false
    @Previewable @State var barcode = false
    return TodayView(showingVoice: $showing, showingPhoto: $photo, showingBarcode: $barcode)
        .environmentObject(AppModel(
            totals: MockData.today,
            meals: MockData.recentMeals,
            profile: MockData.profile,
            bodyMetrics: MockData.bodyMetrics,
            coachMessages: MockData.coachIntro,
            hasCompletedOnboarding: true
        ))
        .preferredColorScheme(.dark)
        .background(Theme.Palette.ink)
}
