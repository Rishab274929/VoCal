//
//  SavedFoodsSheet.swift
//  VoCal
//
//  "Saved foods" destination from the middle-tab "+" picker. Shows the
//  user's most-recently logged unique meals so re-logging a regular
//  breakfast, a daily smoothie, or yesterday's leftover pasta is a single
//  tap.
//
//  Data source: `AppModel.meals`. There's no dedicated "favorites" model
//  yet — we derive uniqueness from the meal name (case-insensitive). When
//  a real saved-foods schema lands, this sheet swaps its data source
//  without changing the call site.
//
//  Future-vision shape: rows include a region/cuisine eyebrow placeholder
//  so when the ethnic-food intelligence work ships the metadata has a
//  visible home. For now the eyebrow stays empty when we don't know.
//

import SwiftUI

struct SavedFoodsSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""

    /// Dedupe meals by lowercased name, preserve recency (most-recent
    /// first), and cap to a reasonable working set. Bigger limit than the
    /// progress screen because this is a "quick re-log" surface, not a
    /// browse / chart screen — users want to land on something they've
    /// eaten in the last few weeks without scrolling for a minute.
    private var uniqueRecentMeals: [MealEntry] {
        var seen = Set<String>()
        var out: [MealEntry] = []
        for meal in appModel.meals {
            let key = meal.name.lowercased().trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(meal)
            if out.count >= 40 { break }
        }
        return out
    }

    private var filtered: [MealEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return uniqueRecentMeals }
        return uniqueRecentMeals.filter {
            $0.name.lowercased().contains(trimmed)
                || $0.detail.lowercased().contains(trimmed)
        }
    }

    var body: some View {
        ZStack {
            Theme.Palette.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                header
                searchField
                if filtered.isEmpty {
                    emptyState
                } else {
                    list
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SAVED FOODS")
                    .eyebrow(Theme.Palette.pulse)
                Text("Your recent regulars.")
                    .font(Theme.Font.serif(28, weight: .medium))
                    .foregroundStyle(Theme.Palette.bone)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ash)
                    .frame(width: 30, height: 30)
                    .background(Circle().strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.smoke)
            TextField(
                "",
                text: $query,
                prompt: Text("Search saved meals").foregroundStyle(Theme.Palette.smoke)
            )
            .textInputAutocapitalization(.never)
            .foregroundStyle(Theme.Palette.bone)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Palette.smoke)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Theme.Palette.inkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1)
                )
        )
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filtered) { meal in
                    Button {
                        // Re-log: clone the meal with a fresh id + timestamp
                        // so the original entry stays intact in history.
                        // Source stays as `.manual` (it was a manual
                        // re-log; we didn't re-derive macros from voice or
                        // a photo). This keeps the daily voice-cap from
                        // mis-counting "I tapped a saved food" as voice.
                        let fresh = MealEntry(
                            name: meal.name,
                            detail: meal.detail,
                            calories: meal.calories,
                            protein: meal.protein,
                            carbs: meal.carbs,
                            fat: meal.fat,
                            loggedAt: .now,
                            slot: meal.slot,
                            source: .manual,
                            sodium_mg: meal.sodium_mg,
                            fiber_g: meal.fiber_g,
                            sugar_g: meal.sugar_g,
                            calcium_mg: meal.calcium_mg,
                            iron_mg: meal.iron_mg,
                            vitamin_c_mg: meal.vitamin_c_mg,
                            potassium_mg: meal.potassium_mg
                        )
                        appModel.addMeal(fresh)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dismiss()
                    } label: {
                        savedRow(meal: meal)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func savedRow(meal: MealEntry) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name)
                    .font(Theme.Font.serif(17, weight: .medium))
                    .foregroundStyle(Theme.Palette.bone)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(meal.calories) kcal")
                        .font(Theme.Font.mono(11))
                        .foregroundStyle(Theme.Palette.smoke)
                    Text("P\(meal.protein) · C\(meal.carbs) · F\(meal.fat)")
                        .font(Theme.Font.mono(11))
                        .foregroundStyle(Theme.Palette.smoke)
                }
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Theme.Palette.paper)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Theme.Palette.inkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nothing here yet.")
                .font(Theme.Font.serif(20, weight: .medium))
                .foregroundStyle(Theme.Palette.bone)
            Text("Log a meal by voice, photo, or barcode and it'll show up here as a one-tap re-log.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.smoke)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    SavedFoodsSheet()
        .environmentObject(AppModel(
            totals: MockData.today,
            meals: MockData.recentMeals,
            profile: MockData.profile
        ))
        .preferredColorScheme(.dark)
}
