//
//  ProfileView.swift
//  VoCal
//
//  Editorial profile: monogram, goal stats, settings list, subscription
//  upgrade row. Black-on-bone settings rows with hairline separators.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var showingPaywall: Bool

    /// Which profile field the user tapped on. Drives the editor sheet;
    /// nil means no sheet is currently showing.
    @State private var editingField: ProfileField?

    /// Identifies the four editable profile attributes shown in the
    /// stats / profile rows. Each maps to a small sheet variant.
    enum ProfileField: Identifiable {
        case dailyKcal
        case weight
        case height
        case sex
        case birthYear

        var id: Int {
            switch self {
            case .dailyKcal: 0
            case .weight:    1
            case .height:    2
            case .sex:       3
            case .birthYear: 4
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                subscriptionCard
                statsRow
                personalCard
                settingsCard
                aboutFooter
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $editingField) { field in
            ProfileFieldEditor(field: field)
                .presentationDetents([.fraction(0.4), .medium])
                .presentationBackground(Theme.Palette.ink)
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("YOU")
                    .eyebrow(Theme.Palette.pulse)
                Spacer()
                StreakBadge(days: appModel.profile.streakDays)
            }
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(Theme.Palette.voltage, lineWidth: 2)
                        .frame(width: 64, height: 64)
                    Text(initials(displayedName))
                        .font(Theme.Font.serif(22, weight: .semibold, italic: true))
                        .foregroundStyle(Theme.Palette.bone)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayedName)
                        .font(Theme.Font.serif(28, weight: .medium))
                        .foregroundStyle(Theme.Palette.bone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Member · \(appModel.profile.entitlement.rawValue.uppercased())")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(Theme.Palette.smoke)
                }
                Spacer()
            }
        }
    }

    private var subscriptionCard: some View {
        Group {
            if appModel.profile.entitlement == .pro {
                proCard
            } else {
                upgradeCTA
            }
        }
    }

    private var upgradeCTA: some View {
        Button {
            showingPaywall = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(Theme.Palette.voltage)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Upgrade to Pro")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.bone)
                    Text("Unlimited voice logs · 7-day trial")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.smoke)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.voltage)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Palette.inkSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .strokeBorder(Theme.Palette.voltage.opacity(0.5), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var proCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.Palette.voltage)
            VStack(alignment: .leading, spacing: 2) {
                Text("VoCal Pro · active")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.bone)
                Text("Renews on Dec 12, 2026")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.smoke)
            }
            Spacer()
            Button("Manage") { /* RC manage */ }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Palette.voltage)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Palette.inkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
        )
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statTile(label: "Daily kcal", value: "\(appModel.profile.dailyCalorieGoal)") {
                editingField = .dailyKcal
            }
            statTile(label: "Weight", value: "\(Int(appModel.profile.weightLbs)) lb") {
                editingField = .weight
            }
            statTile(label: "Height", value: heightString) {
                editingField = .height
            }
        }
    }

    /// Tap on any tile pops the field editor for that attribute. We don't
    /// inline-edit because steppers / pickers crammed into 3 small tiles
    /// would shred the visual rhythm of the profile screen.
    private func statTile(label: String, value: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label.uppercased())
                    .eyebrow()
                Text(value)
                    .font(Theme.Font.serif(20, weight: .medium))
                    .foregroundStyle(Theme.Palette.bone)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(Theme.Palette.inkSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// Sex + birth year — two rows that don't quite fit the three-up stat
    /// tile grid but still need to be tappable to edit. Hairline separator
    /// between them matches the settings card pattern.
    private var personalCard: some View {
        VStack(spacing: 0) {
            personalRow(label: "Sex", value: sexLabel) { editingField = .sex }
            Rectangle()
                .fill(Theme.Palette.hairline)
                .frame(height: 1)
                .padding(.leading, 18)
            personalRow(label: "Birth year", value: "\(appModel.profile.birthYear)") {
                editingField = .birthYear
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Palette.inkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
        )
    }

    private func personalRow(label: String, value: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Palette.bone)
                Spacer()
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.smoke)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.smoke)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private var sexLabel: String {
        switch appModel.profile.sex {
        case "m": "Male"
        case "f": "Female"
        default:  "Unspecified"
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            settingRow(icon: "heart.text.square.fill", title: "Apple Health", detail: "Connect", tint: Theme.Palette.pulse)
            divider
            settingRow(icon: "applewatch", title: "Apple Watch", detail: "Connect", tint: Theme.Palette.fat)
            divider
            settingRow(icon: "bell.fill", title: "Reminders", detail: "3× daily", tint: Theme.Palette.carbs)
            divider
            settingRow(icon: "waveform", title: "Voice & language", detail: "English (US)", tint: Theme.Palette.voltage)
            divider
            settingRow(icon: "lock.fill", title: "Privacy", detail: "On-device by default", tint: Theme.Palette.bone)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Palette.inkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
        )
    }

    private var divider: some View {
        Rectangle().fill(Theme.Palette.hairline).frame(height: 1).padding(.leading, 56)
    }

    private func settingRow(icon: String, title: String, detail: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.14))
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 30, height: 30)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Palette.bone)
            Spacer()
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.smoke)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.smoke)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var aboutFooter: some View {
        VStack(spacing: 4) {
            VoCalWordmark()
            Text("v1.0 (1) · the first calorie tracker that listens.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Palette.smoke)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var heightString: String {
        let total = Int(appModel.profile.heightInches)
        let ft = total / 12
        let inch = total % 12
        return "\(ft)′\(inch)″"
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let result = parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
        // Don't render an empty initials circle — a placeholder beats blank.
        return result.isEmpty ? "VC" : result
    }

    /// Fallback so an unset displayName doesn't render as an empty hero or
    /// initials circle (rare race: rehydrated state predates onboarding).
    private var displayedName: String {
        let n = appModel.profile.displayName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "VoCal user" : n
    }
}

// MARK: - Field editor sheet
//
// One sheet, five field variants. Each variant calls `updateProfile` on
// the AppModel, which persists + writes the DailyMacrosSnapshot so
// widgets/intents pick up the new goal immediately. The sheet auto-
// dismisses on Save.

private struct ProfileFieldEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    let field: ProfileView.ProfileField

    // Field drafts. Initialized lazily in `task` from current profile so
    // re-opening the sheet always reflects the latest persisted value.
    @State private var dailyKcal: Int = 2000
    @State private var weightLbs: Double = 170
    @State private var heightIn: Int = 70
    @State private var sex: String = ""
    @State private var birthYear: Int = 1995

    var body: some View {
        NavigationStack {
            Form {
                switch field {
                case .dailyKcal:
                    Section("Daily calorie target") {
                        Stepper(value: $dailyKcal, in: 1000...5000, step: 25) {
                            HStack {
                                Text("Goal")
                                Spacer()
                                Text("\(dailyKcal) kcal")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                case .weight:
                    Section("Weight (lb)") {
                        Stepper(value: $weightLbs, in: 60...600, step: 0.5) {
                            HStack {
                                Text("Weight")
                                Spacer()
                                Text(String(format: "%.1f lb", weightLbs))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                case .height:
                    Section("Height (in)") {
                        Stepper(value: $heightIn, in: 36...96) {
                            HStack {
                                Text("Height")
                                Spacer()
                                Text("\(heightIn / 12)′\(heightIn % 12)″ · \(heightIn) in")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                case .sex:
                    Section("Sex") {
                        Picker("Sex", selection: $sex) {
                            Text("Male").tag("m")
                            Text("Female").tag("f")
                            Text("Unspecified").tag("")
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                case .birthYear:
                    Section("Birth year") {
                        Picker("Year", selection: $birthYear) {
                            // Reasonable range — 100yo down to 13yo. Open
                            // upper bound matches App Store age gates.
                            let currentYear = Calendar.current.component(.year, from: .now)
                            ForEach((currentYear - 100)...(currentYear - 13), id: \.self) { y in
                                Text(String(y)).tag(y)
                            }
                        }
                        .pickerStyle(.wheel)
                        .labelsHidden()
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .task {
            // Hydrate from current profile each time the sheet opens.
            dailyKcal = appModel.profile.dailyCalorieGoal
            weightLbs = appModel.profile.weightLbs
            heightIn = Int(appModel.profile.heightInches.rounded())
            sex = appModel.profile.sex
            birthYear = appModel.profile.birthYear
        }
    }

    private var navTitle: String {
        switch field {
        case .dailyKcal: "Daily kcal"
        case .weight:    "Weight"
        case .height:    "Height"
        case .sex:       "Sex"
        case .birthYear: "Birth year"
        }
    }

    private func save() {
        appModel.updateProfile { p in
            switch field {
            case .dailyKcal: p.dailyCalorieGoal = dailyKcal
            case .weight:    p.weightLbs = weightLbs
            case .height:    p.heightInches = Double(heightIn)
            case .sex:       p.sex = sex
            case .birthYear: p.birthYear = birthYear
            }
        }
        dismiss()
    }
}

#Preview {
    @Previewable @State var paywall = false
    return ProfileView(showingPaywall: $paywall)
        .environmentObject(AppModel(
            totals: MockData.today,
            meals: MockData.recentMeals,
            profile: MockData.profile,
            bodyMetrics: MockData.bodyMetrics
        ))
        .preferredColorScheme(.dark)
        .background(Theme.Palette.ink)
}
