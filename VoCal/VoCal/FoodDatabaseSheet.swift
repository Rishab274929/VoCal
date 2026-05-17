//
//  FoodDatabaseSheet.swift
//  VoCal
//
//  Lightweight food-database search. Lets the user type a product name
//  or a UPC/EAN code and pull it through the existing barcode resolver —
//  the path that already chains USDA Branded → Open Food Facts and back
//  to the BarcodeAPI client, no new backend.
//
//  This is a SCAFFOLD: there's no proper free-text food-name search
//  endpoint yet, so the experience is intentionally narrow — code lookup
//  works today; name lookup shows a "coming soon" hint and falls back to
//  prompting the user to scan/snap instead. When a real food search ships,
//  it slots in here at the existing search field without touching the
//  surrounding sheet UI.
//
//  Future-vision shape: the row model has placeholder room for a
//  cuisine / region / cooking-method eyebrow so the regional-recipe
//  intelligence work has a visible home when it's wired up.
//

import SwiftUI

struct FoodDatabaseSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var lookingUp: Bool = false
    @State private var lastResult: MealEntry?
    @State private var lastError: String?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// True when the query is a plausible barcode (8–14 digits after we
    /// strip whitespace). Lets us route the same input box to the
    /// barcode API without forcing the user to pick a mode.
    private var queryIsCode: Bool {
        let digits = trimmedQuery.unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }
            .map { String($0) }
            .joined()
        return digits.count == trimmedQuery.count && (8...14).contains(digits.count)
    }

    var body: some View {
        ZStack {
            Theme.Palette.ink.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                header
                searchField
                if lookingUp {
                    loadingRow
                } else if let result = lastResult {
                    resultCard(result)
                } else if let err = lastError {
                    errorRow(err)
                } else {
                    placeholderHint
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
                Text("FOOD DATABASE")
                    .eyebrow(Theme.Palette.pulse)
                Text("Search by name or barcode.")
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
                prompt: Text("\"Greek yogurt\" or 0049000028058").foregroundStyle(Theme.Palette.smoke)
            )
            .textInputAutocapitalization(.never)
            .foregroundStyle(Theme.Palette.bone)
            .onSubmit { runLookup() }
            Button {
                runLookup()
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.Palette.paper))
            }
            .buttonStyle(.plain)
            .disabled(trimmedQuery.isEmpty)
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

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(Theme.Palette.bone)
            Text("Looking up...")
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

    private func resultCard(_ meal: MealEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RESULT")
                .eyebrow()
            Text(meal.name)
                .font(Theme.Font.serif(22, weight: .medium))
                .foregroundStyle(Theme.Palette.bone)
            HStack(spacing: 10) {
                Text("\(meal.calories) kcal")
                    .font(Theme.Font.mono(13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.bone)
                MacroPill(letter: "P", value: meal.protein, tint: Theme.Palette.protein)
                MacroPill(letter: "C", value: meal.carbs, tint: Theme.Palette.carbs)
                MacroPill(letter: "F", value: meal.fat, tint: Theme.Palette.fat)
            }
            if !meal.detail.isEmpty {
                Text(meal.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.smoke)
            }
            HStack(spacing: 12) {
                GhostButton(title: "Clear", fullWidth: false) {
                    lastResult = nil
                    lastError = nil
                    query = ""
                }
                VoltageButton(title: "Log it", icon: "checkmark", fullWidth: false) {
                    appModel.addMeal(meal)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    dismiss()
                }
            }
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

    private func errorRow(_ err: String) -> some View {
        Text(err)
            .font(.system(size: 13))
            .foregroundStyle(Theme.Palette.pulse)
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

    private var placeholderHint: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Type to search")
                .font(Theme.Font.serif(20, weight: .medium))
                .foregroundStyle(Theme.Palette.bone)
            Text("Paste a UPC/EAN to look it up in the food database. Free-text name search is rolling out — for now, the camera shutter or voice still works for foods without a barcode.")
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

    private func runLookup() {
        let q = trimmedQuery
        guard !q.isEmpty else { return }
        // Only barcode lookups are wired today; the BarcodeAPI client
        // already does the USDA → Open Food Facts chain so we get a real
        // result without writing a parallel resolver here.
        if queryIsCode {
            Task { await lookupCode(q) }
        } else {
            // Free-text name search isn't shipped yet. Be honest about it
            // so the user knows the gap and can fall back to the camera
            // or voice instead.
            lastError = "Free-text name search is coming soon. For now, scan the barcode with the camera or describe it via voice."
            lastResult = nil
        }
    }

    private func lookupCode(_ code: String) async {
        lookingUp = true
        defer { lookingUp = false }
        do {
            let (meal, _) = try await BarcodeAPI.lookup(code: code)
            await MainActor.run {
                lastResult = MealEntry(
                    name: meal.name,
                    detail: meal.detail,
                    calories: meal.kcal,
                    protein: meal.protein_g,
                    carbs: meal.carbs_g,
                    fat: meal.fat_g,
                    loggedAt: .now,
                    slot: MealEntry.Slot(rawValue: meal.slot) ?? .snack,
                    source: .barcode
                )
                lastError = nil
            }
        } catch BarcodeAPI.Error.notFound {
            await MainActor.run {
                lastResult = nil
                lastError = "Couldn't find that code in the food database."
            }
        } catch {
            await MainActor.run {
                lastResult = nil
                lastError = "Lookup failed. \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    FoodDatabaseSheet()
        .environmentObject(AppModel(
            totals: MockData.today,
            meals: [],
            profile: MockData.profile
        ))
        .preferredColorScheme(.dark)
}
