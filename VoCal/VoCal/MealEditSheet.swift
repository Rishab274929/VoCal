//
//  MealEditSheet.swift
//  VoCal
//
//  Inline editor for a previously-logged meal. Bound by HistoryView's
//  tap-to-edit and TodayView's tap-to-edit on a MealCard. Saves through
//  AppModel.editMeal so totals recompute, persistence flushes, and
//  HealthKit mirrors the change (delete old, write new).
//
//  Design intent: minimum-chrome stepper-only editor. We deliberately
//  do NOT expose `loggedAt`, `source`, or `id` — those identify the
//  meal and the source-of-truth audit trail.
//

import SwiftUI

struct MealEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    /// The original meal we're editing. We never mutate this in place — we
    /// build a fresh `updated` MealEntry that preserves the same `id` so
    /// HealthKit's external-UUID match keeps working.
    let original: MealEntry

    @State private var name: String
    @State private var detail: String
    @State private var calories: Int
    @State private var protein: Int
    @State private var carbs: Int
    @State private var fat: Int
    @State private var slot: MealEntry.Slot

    // Micronutrient drafts. Nil means "not tracked" — the stepper toggles
    // expose an "add" affordance so a user can graduate from nil → 0 → real
    // value without ever being forced to enter zeros for unknowns.
    @State private var sodium: Int?
    @State private var fiber: Int?
    @State private var sugar: Int?
    @State private var calcium: Int?
    @State private var iron: Double?
    @State private var vitaminC: Double?
    @State private var potassium: Int?

    init(meal: MealEntry) {
        self.original = meal
        _name = State(initialValue: meal.name)
        _detail = State(initialValue: meal.detail)
        _calories = State(initialValue: meal.calories)
        _protein = State(initialValue: meal.protein)
        _carbs = State(initialValue: meal.carbs)
        _fat = State(initialValue: meal.fat)
        _slot = State(initialValue: meal.slot)
        _sodium = State(initialValue: meal.sodium_mg)
        _fiber = State(initialValue: meal.fiber_g)
        _sugar = State(initialValue: meal.sugar_g)
        _calcium = State(initialValue: meal.calcium_mg)
        _iron = State(initialValue: meal.iron_mg)
        _vitaminC = State(initialValue: meal.vitamin_c_mg)
        _potassium = State(initialValue: meal.potassium_mg)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Name", text: $name)
                    TextField("Detail", text: $detail, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Slot", selection: $slot) {
                        ForEach(MealEntry.Slot.allCases, id: \.self) { s in
                            Text(s.rawValue.capitalized).tag(s)
                        }
                    }
                }

                Section("Macros") {
                    Stepper(value: $calories, in: 0...5000, step: 5) {
                        labeledRow("Calories", value: "\(calories) kcal")
                    }
                    Stepper(value: $protein, in: 0...500) {
                        labeledRow("Protein", value: "\(protein) g")
                    }
                    Stepper(value: $carbs, in: 0...700) {
                        labeledRow("Carbs", value: "\(carbs) g")
                    }
                    Stepper(value: $fat, in: 0...300) {
                        labeledRow("Fat", value: "\(fat) g")
                    }
                }

                Section("Micronutrients") {
                    optionalIntRow(
                        label: "Sodium", unit: "mg", step: 10,
                        range: 0...10000, value: $sodium
                    )
                    optionalIntRow(
                        label: "Fiber", unit: "g", step: 1,
                        range: 0...100, value: $fiber
                    )
                    optionalIntRow(
                        label: "Sugar", unit: "g", step: 1,
                        range: 0...300, value: $sugar
                    )
                    optionalIntRow(
                        label: "Calcium", unit: "mg", step: 10,
                        range: 0...3000, value: $calcium
                    )
                    optionalDoubleRow(
                        label: "Iron", unit: "mg", step: 0.5,
                        range: 0...50, value: $iron
                    )
                    optionalDoubleRow(
                        label: "Vitamin C", unit: "mg", step: 5,
                        range: 0...2000, value: $vitaminC
                    )
                    optionalIntRow(
                        label: "Potassium", unit: "mg", step: 10,
                        range: 0...10000, value: $potassium
                    )
                }
            }
            .navigationTitle("Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: rows

    private func labeledRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    /// Stepper row for optional Int. When `value == nil` we surface an "Add"
    /// button rather than forcing the user to pick a zero. Tap the X to
    /// unset back to nil (the value reverts to "not tracked").
    private func optionalIntRow(
        label: String,
        unit: String,
        step: Int,
        range: ClosedRange<Int>,
        value: Binding<Int?>
    ) -> some View {
        Group {
            if let v = value.wrappedValue {
                Stepper(
                    value: Binding(
                        get: { v },
                        set: { value.wrappedValue = $0 }
                    ),
                    in: range,
                    step: step
                ) {
                    HStack {
                        Text(label)
                        Spacer()
                        Text("\(v) \(unit)").monospacedDigit().foregroundStyle(.secondary)
                        Button {
                            value.wrappedValue = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } else {
                Button {
                    value.wrappedValue = 0
                } label: {
                    HStack {
                        Text(label)
                        Spacer()
                        Text("Add \(unit)")
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
    }

    private func optionalDoubleRow(
        label: String,
        unit: String,
        step: Double,
        range: ClosedRange<Double>,
        value: Binding<Double?>
    ) -> some View {
        Group {
            if let v = value.wrappedValue {
                Stepper(
                    value: Binding(
                        get: { v },
                        set: { value.wrappedValue = $0 }
                    ),
                    in: range,
                    step: step
                ) {
                    HStack {
                        Text(label)
                        Spacer()
                        Text(String(format: "%.1f \(unit)", v))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button {
                            value.wrappedValue = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } else {
                Button {
                    value.wrappedValue = 0
                } label: {
                    HStack {
                        Text(label)
                        Spacer()
                        Text("Add \(unit)")
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
    }

    // MARK: save

    private func save() {
        let updated = MealEntry(
            id: original.id,                  // preserve id → HealthKit dedupe
            name: name.trimmingCharacters(in: .whitespaces),
            detail: detail,
            calories: max(0, calories),
            protein: max(0, protein),
            carbs: max(0, carbs),
            fat: max(0, fat),
            loggedAt: original.loggedAt,      // preserve original timestamp
            slot: slot,
            source: original.source,          // preserve provenance
            sodium_mg: sodium,
            fiber_g: fiber,
            sugar_g: sugar,
            calcium_mg: calcium,
            iron_mg: iron,
            vitamin_c_mg: vitaminC,
            potassium_mg: potassium
        )
        appModel.editMeal(original, to: updated)
        dismiss()
    }
}

#Preview {
    MealEditSheet(meal: MockData.recentMeals[0])
        .environmentObject(AppModel(
            totals: MockData.today,
            meals: MockData.recentMeals,
            profile: MockData.profile
        ))
        .preferredColorScheme(.dark)
}
