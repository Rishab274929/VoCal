//
//  WeightEntrySheet.swift
//  VoCal
//
//  Small input sheet for logging a body-weight measurement directly from
//  the Progress tab. Weight has historically been written either by the
//  body-fat photo flow (which also captures BF%) or via HealthKit's
//  passive sync — both of those skip the case where a user just steps on
//  a scale and wants to record the number with zero camera ceremony.
//
//  Persists a `BodyMetric` with `bodyFatPct` nil so the weight chart and
//  the BF% chart stay distinct. The body-fat card on the Progress tab
//  filters by `compactMap { $0.bodyFatPct }` so a weight-only entry won't
//  pollute the BF series.
//
//  Server sync TODO: there's no plain-weight endpoint on /api today
//  (/api/bodyfat takes photos + returns BF%, not bare weight). Once a
//  `/api/body/weight` endpoint exists, swap the local-only persistence
//  block at the bottom of `save()` for a POST. The AppGroup-persisted
//  copy stays as the source of truth for the chart either way.
//

import SwiftUI
import UIKit

struct WeightEntrySheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    /// `kg` ↔ `lb` toggle. The model always stores `weightLbs`; this is a
    /// UI-only preference that converts on save. Default reflects the
    /// most recent prior entry's apparent magnitude (anything < 100 we
    /// assume the user is thinking in kg).
    enum Units: String, CaseIterable {
        case lb, kg
        var label: String { self == .lb ? "lb" : "kg" }
    }

    @State private var raw: String
    @State private var units: Units
    @FocusState private var inputFocused: Bool
    /// Surfaced when the user types something we can't parse as a number.
    @State private var validationError: String?

    init() {
        // Pre-populate with the user's most recent weight so the typical
        // flow is "small adjustment" rather than "type from scratch".
        // Fall back to the profile weight if no history exists.
        // (We can't read AppModel from init because it's an @EnvironmentObject —
        // the @State default uses an empty string and `.onAppear` populates.)
        self._raw = State(initialValue: "")
        self._units = State(initialValue: .lb)
    }

    var body: some View {
        ZStack {
            Theme.Palette.ink.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                header
                inputBlock
                Spacer(minLength: 0)
                saveRow
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .onAppear {
            // Pre-populate from the most recent body metric (or the
            // profile's static weight) so the user's typical scrub is
            // small. We avoid pre-filling on every appear (only when
            // empty) so swapping units mid-flight doesn't wipe the
            // user's pending input.
            if raw.isEmpty {
                let lb = appModel.bodyMetrics.first?.weightLbs ?? appModel.profile.weightLbs
                if lb > 0 {
                    raw = String(format: "%.1f", lb)
                    units = .lb
                }
            }
            inputFocused = true
        }
        .onChange(of: units) { old, new in
            // Convert the existing buffer when the user flips units so the
            // displayed magnitude stays accurate. If parsing fails we just
            // leave the raw text alone — the user's mid-edit.
            guard old != new, let v = Double(raw) else { return }
            switch (old, new) {
            case (.lb, .kg): raw = String(format: "%.1f", v * 0.45359237)
            case (.kg, .lb): raw = String(format: "%.1f", v / 0.45359237)
            default: break
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LOG WEIGHT")
                    .eyebrow(Theme.Palette.pulse)
                Text("What does the scale say?")
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

    private var inputBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TextField(
                    "",
                    text: $raw,
                    prompt: Text("0.0").foregroundStyle(Theme.Palette.smoke)
                )
                .keyboardType(.decimalPad)
                .focused($inputFocused)
                .font(Theme.Font.serif(56, weight: .medium))
                .foregroundStyle(Theme.Palette.bone)
                .monospacedDigit()
                Text(units.label)
                    .font(Theme.Font.serif(24, weight: .regular, italic: true))
                    .foregroundStyle(Theme.Palette.smoke)
            }
            // Unit toggle. Picker style is `.segmented` so it reads like an
            // iOS-native control without inventing a new component for a
            // two-state choice.
            Picker("Units", selection: $units) {
                ForEach(Units.allCases, id: \.self) { u in
                    Text(u.label.uppercased()).tag(u)
                }
            }
            .pickerStyle(.segmented)
            if let err = validationError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.pulse)
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

    private var saveRow: some View {
        HStack(spacing: 12) {
            GhostButton(title: "Cancel") { dismiss() }
            VoltageButton(title: "Save", icon: "checkmark") { save() }
        }
    }

    private func save() {
        let trimmed = raw
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(trimmed) else {
            validationError = "Enter a number."
            return
        }
        // Convert to lb (the on-device storage unit) before persistence.
        // Clamp to a plausible adult range so a typo doesn't anchor a
        // 4.4 lb / 800 kg entry on the weight chart forever.
        let lb: Double = {
            switch units {
            case .lb: return value
            case .kg: return value / 0.45359237
            }
        }()
        guard lb > 40, lb < 800 else {
            validationError = "Out of range. Double-check the number."
            return
        }
        let metric = BodyMetric(
            weightLbs: lb,
            bodyFatPct: nil,
            confidence: nil,
            measuredAt: .now
        )
        appModel.addBodyMetric(metric)
        // Keep the profile's static weight aligned with the most-recent
        // measurement so the calorie-goal recomputation (when it next
        // runs in onboarding edit or coach refit) reflects today's
        // number — otherwise the goal stays anchored to a stale weight.
        appModel.updateProfile { p in p.weightLbs = lb }
        // Mirror to HealthKit so the Health app stays in sync. Fire-
        // and-forget; no-op if HK auth isn't granted.
        Task { await VoCalHealth.shared.write(bodyMetric: metric) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // TODO(server-sync): once /api/body/weight ships, POST `metric`
        // here so multi-device users see the entry on every install. The
        // local copy is authoritative for the chart in the meantime.
        dismiss()
    }
}

#Preview {
    WeightEntrySheet()
        .environmentObject(AppModel(
            totals: MockData.today,
            meals: [],
            profile: MockData.profile,
            bodyMetrics: MockData.bodyMetrics
        ))
        .preferredColorScheme(.dark)
}
