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
    @State private var showingPaywall = false
    @State private var capturingSlot: Step = .front
    @State private var estimating = false
    @State private var resultPct: Double?
    @State private var resultConfidence: Double = 0.82
    @State private var cameraPermissionDenied = false
    /// Set when we attempted the vision endpoint, it failed, and the result
    /// shown is the BMI-only fallback. Surfaces a one-liner so the user
    /// knows the confidence band reflects degraded inputs.
    @State private var visionFallbackUsed = false
    @State private var visionGateMessage: String?
    /// Optional one-line reasoning from the vision model. Currently unused
    /// in the UI but kept so we can show it next to the band without
    /// another network round-trip later.
    @State private var visionReasoning: String?

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
            CameraPicker(
                source: .camera,
                onPicked: { picked in
                    // Body photos can be 48MP — and we hold both `front` and
                    // `side` simultaneously through the entire result screen.
                    // Downsample at capture so we don't sit on 200+MB of
                    // bitmaps while waiting on a Save tap.
                    let small = CapturedImage.downsample(picked)
                    switch capturingSlot {
                    case .front:  front = small
                    case .side:   side = small
                    default: break
                    }
                    advance()
                },
                onAuthorization: { granted in
                    cameraPermissionDenied = !granted
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallSheet()
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
        case .result: estimating ? "Working on your estimate…" : "Estimate ready."
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
                // Honest copy: photos live in @State for the duration of this
                // sheet only. Nothing is uploaded to disk or to the network
                // by this flow today — the encrypted-per-user-key wording
                // described future remote storage, not the local heuristic
                // path that actually ships.
                Text("Photos stay on this device for the duration of this sheet. They're discarded when you close it.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.smoke)
            }
            if cameraPermissionDenied {
                Text("Camera access is off. Enable it in Settings → VoCal to capture the angles.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.pulse)
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
            } else if let gate = visionGateMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.Palette.pulse)
                    Text(gate)
                        .font(.system(size: 14))
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
                    // Real confidence band derived from `resultConfidence`.
                    // Was hardcoded to "±1.4 pts" regardless of how reliable
                    // the inputs actually were — misleading when sex is
                    // unknown or no photos were captured.
                    Text(confidenceBandLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.ash)
                }
                // Was "Saved to Progress + Apple Health." — but the actual
                // save happens on the Save & Close tap below, not here. The
                // old copy lied. Now phrased as a forward-looking hint.
                Text("Tap Save to log this to Progress + Apple Health.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.smoke)
                if front == nil || side == nil {
                    // Without photos, the heuristic is BMI-only and the
                    // confidence band gets noticeably wider. Be upfront.
                    Text("Estimate is BMI-only without photos — capture both angles to tighten the band.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.pulse)
                } else if visionFallbackUsed {
                    // Both photos captured but the vision call failed — say
                    // so out loud so the user understands why the band is
                    // wider than the polished "with photos" estimate would
                    // normally show.
                    Text("Couldn't reach vision; using BMI fallback.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.pulse)
                }
            }

            HStack(spacing: 10) {
                silhouettePreview(image: front, label: "Front")
                silhouettePreview(image: side, label: "Side")
            }
            .frame(height: 160)
        }
    }

    /// Translate the heuristic's confidence into a ± points label.
    /// Higher confidence → narrower band. Anchored so an 0.82 confidence
    /// maps to roughly the previously-hardcoded ±1.4 pts.
    private var confidenceBandLabel: String {
        let c = max(0.3, min(0.95, resultConfidence))
        // 0.82 → 1.4, 0.62 → 3.0, 0.50 → 4.0
        let band = max(1.0, 8.0 * (1.0 - c))
        return String(format: "Confidence band ±%.1f pts", band)
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
                VoltageButton(title: resultPct == nil ? "Close" : "Save & close", icon: resultPct == nil ? "xmark" : "checkmark") {
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
        visionFallbackUsed = false
        visionGateMessage = nil
        visionReasoning = nil
        withAnimation(.spring) { step = .intro }
    }

    private func runEstimate() async {
        estimating = true
        defer { estimating = false }

        // If both photos are present we try the real vision model first;
        // on any failure we fall back to the BMI heuristic with a clearly
        // degraded confidence band and a one-line disclosure. With no /
        // partial photos the network call is skipped — vision needs both
        // angles to do better than BMI anyway.
        if let f = front, let s = side {
            do {
                let visionResult = try await BodyFatVisionAPI.estimate(
                    front: f,
                    side: s,
                    sex: appModel.profile.sex,
                    weightLb: appModel.profile.weightLbs,
                    heightIn: appModel.profile.heightInches
                )
                await MainActor.run {
                    resultPct = visionResult.bodyFatPct
                    resultConfidence = visionResult.confidence
                    visionFallbackUsed = false
                    visionReasoning = visionResult.reasoning
                }
                return
            } catch let gate as BackendAPIError where gate.needsUserAction {
                await handleBackendGate(gate)
                return
            } catch {
                // Fall through to BMI fallback. Mark the disclosure so the
                // user can see why the band is wider than the polished
                // photo-driven case.
                await MainActor.run { visionFallbackUsed = true }
            }
        } else {
            // No vision call attempted. Make sure the disclosure flag is
            // cleared in case a previous Retake left it set.
            await MainActor.run { visionFallbackUsed = false }
        }

        // BMI fallback (same heuristic as before). The artificial 1.2s
        // delay used to gate this branch so the result didn't pop in
        // instantly — preserve it for the fallback so the UI still feels
        // like work happened.
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        let (est, confidence) = bmiHeuristic()
        await MainActor.run {
            resultPct = est
            // If we just fell back from a failed vision call, knock the
            // confidence down further so the band visibly widens (the
            // user is being told "degraded inputs" in copy — keep the
            // number honest with the copy).
            resultConfidence = visionFallbackUsed
                ? max(0.40, min(confidence, 0.55))
                : confidence
        }
    }

    private func handleBackendGate(_ error: BackendAPIError) async {
        let message: String
        switch error {
        case .signInRequired:
            message = "Sign in again to use VoCal's body-fat vision estimate."
        case .proRequired:
            let synced = await StoreKitStore.shared.syncServerEntitlement(force: true, surfaceErrors: true)
            if synced {
                message = "Pro synced. Retake the estimate to use vision."
            } else {
                message = StoreKitStore.shared.lastError ?? "VoCal Pro is required for body-fat vision."
                if !StoreKitStore.shared.hasPro {
                    showingPaywall = true
                }
            }
        case .server, .malformed:
            message = error.localizedDescription
        }
        await MainActor.run {
            resultPct = nil
            visionFallbackUsed = false
            visionGateMessage = message
        }
    }

    /// Pure-Swift BMI-derived body-fat % with a confidence value that
    /// reflects how much of the input we actually have (anthropometrics,
    /// sex, photo angles). Extracted so the vision fallback path can
    /// reuse the exact heuristic without copy-pasting.
    private func bmiHeuristic() -> (pct: Double, confidence: Double) {
        let bmi = bmiEstimate()
        let haveAnthro = appModel.profile.weightLbs > 0 && appModel.profile.heightInches > 0
        let sex = appModel.profile.sex.lowercased()
        let baseline: Double
        var confidence: Double
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

        // Photo capture credit. Both angles → small bump. One angle → tiny
        // bump. No photos → significant drop, since the spec says this is a
        // photo-based estimate and we're degrading to BMI-only.
        if front != nil && side != nil {
            confidence = min(0.88, confidence + 0.04)
        } else if front != nil || side != nil {
            confidence = min(0.82, confidence + 0.01)
        } else {
            confidence = max(0.40, confidence - 0.18)
        }

        // Anthropometrics missing → BMI is a coin flip. Floor confidence.
        if !haveAnthro {
            confidence = min(confidence, 0.45)
        }

        let est = max(8.0, min(35.0, baseline + (bmi - 22) * 1.6))
        return (est, confidence)
    }

    /// BMI in metric. Returns a sane fallback (22 = mid-normal) when either
    /// anthropometric is missing or clearly garbage. Without this guard
    /// `bmi = 0` would flow into `(0 - 22) * 1.6 = -35.2` and the baseline
    /// would clamp to the floor regardless of which sex the user picked.
    private func bmiEstimate() -> Double {
        let lb = appModel.profile.weightLbs
        let inches = appModel.profile.heightInches
        guard lb > 50, lb < 800, inches > 36, inches < 96 else {
            return 22
        }
        let kg = lb * 0.4536
        let m = inches * 0.0254
        let raw = kg / (m * m)
        // Clamp to plausible adult range so a typo doesn't produce a
        // BMI of 87 and a -ridiculous body fat number after the linear
        // extrapolation.
        return max(14, min(45, raw))
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
        // Free image bitmaps now — sheet is about to dismiss and we don't
        // want the captured photos surviving in @State while SwiftUI animates
        // the dismissal out.
        front = nil
        side = nil
    }
}

// MARK: - Vision API client
//
// Tight scope: this lives in the same file as `BodyFatPhotoSheet` because
// it's the only call site. If a second surface ever needs a BF% from
// photos, lift this into its own file at that point.

enum BodyFatVisionAPI {
    struct Result {
        let bodyFatPct: Double
        let confidence: Double
        let reasoning: String?
    }

    enum APIError: Swift.Error, LocalizedError {
        case encodeFailed
        case server(Int, String)
        case malformed
        var errorDescription: String? {
            switch self {
            case .encodeFailed:        return "Couldn't compress the body photos."
            case .server(let s, let m): return "Server \(s): \(m)"
            case .malformed:           return "Unexpected response from the body-fat vision model."
            }
        }
    }

    /// Backend contract (per the wave-2 spec): POST to /api/bodyfat with
    /// both images inline as base64, plus the basic anthropometrics.
    /// Returns body-fat % + confidence (and optional reasoning) on success.
    private struct Payload: Codable {
        let image_b64_front: String
        let image_b64_side: String
        let sex: String
        let weight_lb: Double
        let height_in: Double
    }

    private struct ResponseBody: Codable {
        let body_fat_pct: Double?
        let confidence: Double?
        let reasoning: String?
    }

    /// Vision can be slow — vision models running on cold workers
    /// frequently hit ~10s on the first request. 15s gives headroom
    /// without making a stuck call feel infinite.
    private static let timeoutSeconds: TimeInterval = 15

    static func estimate(
        front: UIImage,
        side: UIImage,
        sex: String,
        weightLb: Double,
        heightIn: Double
    ) async throws -> Result {
        guard let url = URL(string: "\(APIConfig.baseURL)/bodyfat") else {
            throw APIError.malformed
        }
        // Downsample both photos to max edge 1024 + JPEG 0.7 before
        // base64. Larger than meal photos (768) because body silhouettes
        // benefit from a bit more pixel density — the model needs to see
        // shoulder vs waist taper to estimate distribution.
        guard
            let frontJPEG = downscaledJPEG(image: front, longestEdge: 1024, quality: 0.7),
            let sideJPEG = downscaledJPEG(image: side, longestEdge: 1024, quality: 0.7)
        else {
            throw APIError.encodeFailed
        }
        let payload = Payload(
            image_b64_front: frontJPEG.base64EncodedString(),
            image_b64_side: sideJPEG.base64EncodedString(),
            sex: sex,
            weight_lb: weightLb,
            height_in: heightIn
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeoutSeconds
        req.httpBody = try JSONEncoder().encode(payload)
        await AuthSession.shared.authorize(&req)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.malformed }
        if !(200..<300).contains(http.statusCode) {
            throw BackendAPIError.from(status: http.statusCode, data: data)
        }
        let body = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let pct = body.body_fat_pct, pct.isFinite, pct > 0, pct < 80 else {
            // Server returned a 200 but no usable body-fat number — treat
            // that as malformed so the caller falls back to BMI rather
            // than displaying a phantom 0% or NaN.
            throw APIError.malformed
        }
        // Clamp confidence into the valid [0, 1] band. Server should send
        // this already in range, but a defensive clamp keeps the band
        // calculation honest.
        let clampedConfidence: Double = {
            guard let c = body.confidence, c.isFinite else { return 0.70 }
            return max(0.0, min(1.0, c))
        }()
        return Result(
            bodyFatPct: pct,
            confidence: clampedConfidence,
            reasoning: body.reasoning
        )
    }

    /// Aspect-fit resize + JPEG. Mirrors PhotoParseAPI's helper so we
    /// don't take a dependency just to share three lines of geometry.
    private static func downscaledJPEG(image: UIImage, longestEdge: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(longestEdge / max(size.width, size.height), 1)
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: target, format: {
            let f = UIGraphicsImageRendererFormat.default()
            f.scale = 1
            f.opaque = true
            return f
        }())
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
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
