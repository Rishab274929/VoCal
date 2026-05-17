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

    /// Meal currently being edited via `MealEditSheet`. Bound to a sheet
    /// presentation that pops when this becomes non-nil. We never edit the
    /// meal in place — the sheet creates a fresh updated copy that goes
    /// through `AppModel.editMeal`.
    @State private var editingMeal: MealEntry?
    /// Meal queued for delete via the swipe action. Held in state so we can
    /// gate the destructive remove behind a confirmation alert.
    @State private var pendingDelete: MealEntry?
    /// Toggles the collapsible Micros section under the macro bars.
    @State private var showMicros = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                topBar
                heroBlock
                ringBlock
                macrosBlock
                microsBlock
                mealsBlock
                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
        }
        .background(Color.clear)
        .scrollIndicators(.hidden)
        .sheet(item: $editingMeal) { meal in
            MealEditSheet(meal: meal)
        }
        .alert("Delete this meal?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let meal = pendingDelete {
                    appModel.removeMeal(meal)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            if let m = pendingDelete {
                Text("\(m.name) · \(m.calories) kcal")
            }
        }
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
        // Fallback for the brief window where a user lands in ContentView
        // before onboarding ever filled the displayName. Without this the
        // eyebrow renders as "EVENING · " with a trailing dot.
        let name = appModel.profile.displayName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? prefix : "\(prefix) · \(name)"
    }

    private var serifLine: AttributedString {
        let eaten = appModel.totals.caloriesEaten
        let goal = appModel.totals.calorieGoal
        let over = eaten > goal
        let value = over ? (eaten - goal) : max(0, goal - eaten)
        // Group the number with thousands separators so "1880" reads as "1,880"
        // and the headline fits on two lines instead of three on iPhone 17 Pro.
        let formatted = value.formatted(.number)

        // Prefix changes when the user has overshot the goal so the hero
        // copy doesn't just silently report "0 kcal left today" — it
        // becomes "You're 250 kcal over today." with the number in coral.
        var s = AttributedString(over ? "You're " : "You have ")
        s.foregroundColor = Theme.Palette.smoke
        var n = AttributedString("\(formatted) kcal")
        n.font = Theme.Font.serif(36, weight: .medium, italic: true)
        n.foregroundColor = over ? Theme.Palette.pulse : Theme.Palette.voltage
        var tail = AttributedString(over ? " over today." : " left today.")
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
                // `.swipeActions` only works inside `List`. We strip the
                // List chrome (plain style, hidden separators, clear bg)
                // so it blends with the editorial layout while still
                // giving us native swipe-to-delete. Fixed-height so the
                // parent ScrollView owns the scroll.
                List {
                    ForEach(appModel.meals) { meal in
                        MealCard(meal: meal)
                            .contentShape(Rectangle())
                            .onTapGesture { editingMeal = meal }
                            .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    pendingDelete = meal
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .frame(height: CGFloat(appModel.meals.count) * 110)
            }
        }
    }

    // MARK: micros — collapsible totals for the day

    private var microsBlock: some View {
        // Sum across today's meals for each micronutrient. If a meal didn't
        // report a given micro it just doesn't contribute — no "0" pollution.
        let today = Calendar.current.startOfDay(for: .now)
        let todaysMeals = appModel.meals.filter {
            Calendar.current.startOfDay(for: $0.loggedAt) == today
        }
        let sodium = todaysMeals.compactMap { $0.sodium_mg }.reduce(0, +)
        let fiber = todaysMeals.compactMap { $0.fiber_g }.reduce(0, +)
        let sugar = todaysMeals.compactMap { $0.sugar_g }.reduce(0, +)
        let calcium = todaysMeals.compactMap { $0.calcium_mg }.reduce(0, +)
        let iron = todaysMeals.compactMap { $0.iron_mg }.reduce(0, +)
        let vitC = todaysMeals.compactMap { $0.vitamin_c_mg }.reduce(0, +)
        let potassium = todaysMeals.compactMap { $0.potassium_mg }.reduce(0, +)

        // Only show micros that any meal actually reported. Hides the whole
        // block if none of today's meals carry micro data — keeps the day-1
        // user from staring at seven empty rows.
        let entries: [(String, String)] = [
            sodium > 0 ? ("Sodium", "\(sodium) mg") : nil,
            fiber > 0 ? ("Fiber", "\(fiber) g") : nil,
            sugar > 0 ? ("Sugar", "\(sugar) g") : nil,
            calcium > 0 ? ("Calcium", "\(calcium) mg") : nil,
            iron > 0 ? ("Iron", String(format: "%.1f mg", iron)) : nil,
            vitC > 0 ? ("Vitamin C", String(format: "%.0f mg", vitC)) : nil,
            potassium > 0 ? ("Potassium", "\(potassium) mg") : nil
        ].compactMap { $0 }

        return Group {
            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showMicros.toggle() }
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            SectionHeader(title: "Micros", eyebrow: "Today")
                            Spacer()
                            Image(systemName: showMicros ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.Palette.smoke)
                        }
                    }
                    .buttonStyle(.plain)

                    if showMicros {
                        VStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.offset) { i, entry in
                                MicroRow(label: entry.0, value: entry.1)
                                if i < entries.count - 1 {
                                    Rectangle()
                                        .fill(Theme.Palette.hairline)
                                        .frame(height: 1)
                                }
                            }
                        }
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
                .padding(.top, 4)
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

/// Single thin hairline row inside the Micros card. Eyebrow label on the
/// left, mono value on the right — matches the macro-bar / stat-column
/// design language without competing with them visually.
private struct MicroRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(Theme.Palette.smoke)
            Spacer()
            Text(value)
                .font(Theme.Font.mono(12, weight: .medium))
                .foregroundStyle(Theme.Palette.bone)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
