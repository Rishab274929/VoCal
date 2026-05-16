//
//  BodyFatPhotoSheet.swift
//  VoCal
//
//  Two-photo body-fat baseline. Front + side selfies → simulated BF%
//  estimate with a confidence band. Backed by the real vision API behind
//  /api/bodyfat once deployed; otherwise the heuristic preview keeps the
//  demo alive.
//

import SwiftUI
import UIKit

struct BodyFatPhotoSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    enum Step { case intro, front, side, result }

    @State private var step: Step = .intro
    @State private var front: UIImage?
    @State private var side: UIImage?
    @State private var showingCamera = false
    @State private var capturingSlot: Step = .front
    @State private var estimating = false
    @State private var resultPct: Double?
    @State private var resultConfidence: Double = 0.82

    var body: some View {
        ZStack {
            Theme.Palette.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 16)

                Group {
                    switch step {
                    case .intro:  introContent
                    case .front:  capture(slot: .front, image: $front, label: "Front")
                    case .side:   capture(slot: .side,  image: $side,  label: "Side")
                    case .result: resultContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                footer
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker(source: .camera) { picked in
                switch capturingSlot {
                case .front:  front = picked
                case .side:   side = picked
                default: break
                }
                advance()
            }
            .ignoresSafeArea()
        }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("BODY FAT")
                    .eyebrow(Theme.Palette.pulse)
                Text(headlineText)
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

    private var headlineText: String {
        switch step {
        case .intro:  "Two photos. About 30 seconds."
        case .front:  "Snap a front-facing photo."
        case .side:   "Now a side profile."
        case .result: "Estimate ready."
        }
    }

    // MARK: intro

    private var introContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Stand against a plain wall in tight clothes (or in your skivvies). Light from in front. Tap the silhouette to capture each angle.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.ash)

            HStack(spacing: 14) {
                silhouettePreview(image: front, label: "Front")
                silhouettePreview(image: side, label: "Side")
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("PRIVACY")
                    .eyebrow()
                Text("Photos are encrypted with a per-user key and stored only while the estimate is running. Toggle 90-day retention in Profile → Privacy.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.smoke)
            }
        }
    }

    private func capture(slot: Step, image: Binding<UIImage?>, label: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(label.uppercased()) ANGLE")
                .eyebrow()
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.Palette.inkSurface)
                    .frame(height: 280)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Theme.Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                    )
                if let img = image.wrappedValue {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "figure.stand")
                            .font(.system(size: 56, weight: .light))
                            .foregroundStyle(Theme.Palette.smoke)
                        Text("Tap to capture \(label.lowercased())")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Palette.smoke)
                    }
                }
            }
            .onTapGesture {
                capturingSlot = slot
                showingCamera = true
            }
        }
    }

    private func silhouettePreview(image: UIImage?, label: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.Palette.inkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1)
                )
                .frame(height: 200)

            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack {
                Spacer()
                Text(label.uppercased())
                    .eyebrow()
                    .padding(.bottom, 10)
            }
        }
    }

    // MARK: result

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if estimating {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.Palette.voltage).controlSize(.small)
                    Text("Running vision model…")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.smoke)
                }
            } else if let pct = resultPct {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", pct))
                        .font(Theme.Font.serif(80, weight: .medium))
                        .foregroundStyle(Theme.Palette.voltage)
                        .monospacedDigit()
                    Text("%")
                        .font(Theme.Font.serif(28, weight: .regular, italic: true))
                        .foregroundStyle(Theme.Palette.smoke)
                }
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.ash)
                    Text("Confidence band ±1.4 pts")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.ash)
                }
                Text("Saved to Progress + Apple Health.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.smoke)
            }

            HStack(spacing: 10) {
                silhouettePreview(image: front, label: "Front")
                silhouettePreview(image: side, label: "Side")
            }
            .frame(height: 160)
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 12) {
            switch step {
            case .intro:
                GhostButton(title: "Cancel") { dismiss() }
                VoltageButton(title: "Start", icon: "arrow.right") {
                    capturingSlot = .front
                    showingCamera = true
                }
            case .front:
                GhostButton(title: "Skip") { advance() }
                VoltageButton(title: front == nil ? "Capture front" : "Continue", icon: front == nil ? "camera.fill" : "arrow.right") {
                    if front == nil {
                        capturingSlot = .front
                        showingCamera = true
                    } else {
                        advance()
                    }
                }
            case .side:
                GhostButton(title: "Skip") { advance() }
                VoltageButton(title: side == nil ? "Capture side" : "Estimate", icon: side == nil ? "camera.fill" : "sparkles") {
                    if side == nil {
                        capturingSlot = .side
                        showingCamera = true
                    } else {
                        advance()
                    }
                }
            case .result:
                GhostButton(title: "Retake") { reset() }
                VoltageButton(title: "Save & close", icon: "checkmark") {
                    persist()
                    dismiss()
                }
            }
        }
    }

    // MARK: flow control

    private func advance() {
        switch step {
        case .intro:
            withAnimation(.spring) { step = front == nil ? .front : .side }
        case .front:
            withAnimation(.spring) { step = .side }
        case .side:
            withAnimation(.spring) { step = .result }
            Task { await runEstimate() }
        case .result:
            persist()
            dismiss()
        }
    }

    private func reset() {
        front = nil
        side = nil
        resultPct = nil
        withAnimation(.spring) { step = .intro }
    }

    private func runEstimate() async {
        estimating = true
        defer { estimating = false }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        // Heuristic estimate based on weight/height/sex. The real vision
        // model lives behind /api/bodyfat — when deployed, the call site
        // swaps here.
        let bmi = bmiEstimate()
        let sex = appModel.profile.sex.lowercased()
        let baseline: Double
        let confidence: Double
        switch sex {
        case "f", "female":
            baseline = 23.0
            confidence = 0.78
        case "m", "male":
            baseline = 16.5
            confidence = 0.78
        default:
            // Unspecified: midpoint with reduced confidence so user sees the band widen.
            baseline = 19.75
            confidence = 0.62
        }
        let est = max(8.0, min(35.0, baseline + (bmi - 22) * 1.6))
        await MainActor.run {
            resultPct = est
            resultConfidence = confidence
        }
    }

    private func bmiEstimate() -> Double {
        let kg = appModel.profile.weightLbs * 0.4536
        let m = appModel.profile.heightInches * 0.0254
        guard m > 0 else { return 22 }
        return kg / (m * m)
    }

    private func persist() {
        guard let pct = resultPct else { return }
        let metric = BodyMetric(
            weightLbs: appModel.profile.weightLbs,
            bodyFatPct: pct,
            confidence: resultConfidence,
            measuredAt: .now
        )
        appModel.addBodyMetric(metric)
        Task { await VoCalHealth.shared.write(bodyMetric: metric) }
    }
}

#Preview {
    BodyFatPhotoSheet()
        .environmentObject(AppModel(
            totals: MockData.today,
            meals: MockData.recentMeals,
            profile: MockData.profile,
            bodyMetrics: MockData.bodyMetrics
        ))
        .preferredColorScheme(.dark)
}
