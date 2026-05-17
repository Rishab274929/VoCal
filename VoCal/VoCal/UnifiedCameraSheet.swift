//
//  UnifiedCameraSheet.swift
//  VoCal
//
//  Single camera surface that does TWO things at once:
//   1. Continuously scans for product barcodes (UPC-A/E, EAN-8/13, Code 128,
//      Code 39, QR). When a fresh code resolves, a small product card fades
//      in over the preview — tap "Log it" to drop the meal into AppModel,
//      or keep aiming for another product.
//   2. A shutter button captures a still frame from the same
//      AVCaptureSession and ships it to /api/photo/parse for AI meal
//      parsing — which then routes into the existing MealPhotoSheet review
//      flow.
//
//  Merges the previously-separate `BarcodeScannerSheet` and `MealPhotoSheet`
//  into one place because, from the user's perspective, "log what's in
//  front of me" is the same intent regardless of whether the camera sees a
//  product label or a plate.
//
//  Debounce policy on barcode lookups (important — this view runs the
//  metadata pipeline at video frame rate):
//   - Skip frames while a previous lookup is in flight.
//   - Hold every successfully-resolved code in a 30-second cache so the
//     user pointing at the same Coke can for 5 seconds doesn't keep firing
//     network requests.
//   - Cap to ~1 attempted lookup per second across ALL codes (rate gate).
//   - Light haptic on each unique detection so the user gets feedback even
//     before the card animates in.
//
//  Body-fat photo capture is intentionally NOT routed through here — it
//  stays in `BodyFatPhotoSheet` because the two-photo flow + heuristic +
//  vision fallback are body-composition specific and not a "snap and parse"
//  intent.
//

import SwiftUI
import AVFoundation
import UIKit
import Combine

// MARK: - Sheet

struct UnifiedCameraSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var controller = UnifiedCameraController()

    /// Captured still being reviewed via the existing photo-parse flow.
    /// Presenting a `MealPhotoSheet` once we have a frame lets us reuse the
    /// confirm + follow-up + save UX without duplicating any of it.
    @State private var capturedImage: UIImage?
    @State private var showingMealPhotoSheet = false
    /// Bottom card state for the most recent resolved barcode.
    @State private var resolvedMeal: MealEntry?
    @State private var resolvedSourceTag: String = ""
    /// Last lookup error (network, not-found). Surfaced as a tiny inline
    /// label so the user knows we tried and missed without burying it.
    @State private var lastLookupError: String?
    /// Showing the manual-code entry fallback when no camera is available
    /// (simulator, denied permission). Keeps the demo path open.
    @State private var showingManualEntry = false
    @State private var manualCode: String = ""

    var body: some View {
        ZStack {
            // Pure black so the preview takes over the visual field — the
            // editorial-ink surfaces compete with a live camera feed.
            Color.black.ignoresSafeArea()

            // Camera preview / fallback fills the full sheet.
            UnifiedCameraPreview(controller: controller)
                .ignoresSafeArea()

            // Foreground UI — top close button, viewfinder reticle, shutter,
            // and the resolved-product card.
            VStack(spacing: 0) {
                topBar
                Spacer()
                reticle
                Spacer()
                if let meal = resolvedMeal {
                    productCard(meal: meal)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                } else if showingManualEntry {
                    manualEntryCard
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                }
                shutterRow
                    .padding(.bottom, 28)
            }
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        .onChange(of: controller.lastDetectedCode) { _, code in
            // Distinct payload arrived (controller already dedupes by value).
            guard let code, !code.isEmpty else { return }
            Task { await resolveCode(code) }
        }
        .onChange(of: controller.cameraUnavailable) { _, unavailable in
            // No camera (simulator / denied / no hardware). Fall back to a
            // manual-entry surface so the flow still demos.
            if unavailable { showingManualEntry = true }
        }
        .sheet(isPresented: $showingMealPhotoSheet, onDismiss: {
            // Re-arm the session once the meal-review sheet closes so
            // subsequent barcode detections continue to fire.
            controller.resumeAfterCapture()
            capturedImage = nil
        }) {
            if let img = capturedImage {
                MealPhotoSheet(prefilledImage: img)
                    .presentationDetents([.large])
                    .presentationBackground(Theme.Palette.ink)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                    Text("Close")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.55))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)

            Spacer()

            // Eyebrow telling the user the dual mode is live.
            HStack(spacing: 8) {
                Circle()
                    .fill(controller.cameraUnavailable ? Color.white.opacity(0.3) : Color.green)
                    .frame(width: 6, height: 6)
                Text(controller.cameraUnavailable
                     ? "MANUAL ENTRY"
                     : (resolvedMeal == nil ? "AIM · TAP TO SNAP" : "PRODUCT FOUND"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            )
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    /// Soft viewfinder reticle — visible whether we're scanning a barcode or
    /// framing a meal photo. Doesn't constrain detection (metadata output
    /// runs over the full frame), but gives the user something to aim with.
    private var reticle: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
            .frame(width: 260, height: 220)
            .shadow(color: .black.opacity(0.6), radius: 18)
            .overlay(alignment: .bottom) {
                if let err = lastLookupError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .offset(y: 22)
                }
            }
    }

    private func productCard(meal: MealEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("BARCODE")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Palette.smoke)
                Spacer()
                Button {
                    withAnimation(.spring()) {
                        resolvedMeal = nil
                        lastLookupError = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
            Text(meal.name)
                .font(Theme.Font.serif(20, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
            HStack(spacing: 10) {
                Text("\(meal.calories) kcal")
                    .font(Theme.Font.mono(13, weight: .semibold))
                    .foregroundStyle(.white)
                MacroPill(letter: "P", value: meal.protein, tint: Theme.Palette.protein)
                MacroPill(letter: "C", value: meal.carbs, tint: Theme.Palette.carbs)
                MacroPill(letter: "F", value: meal.fat, tint: Theme.Palette.fat)
            }
            HStack(spacing: 10) {
                GhostButton(title: "Dismiss", fullWidth: false) {
                    withAnimation(.spring()) {
                        resolvedMeal = nil
                        lastLookupError = nil
                    }
                }
                VoltageButton(title: "Log it", icon: "checkmark", fullWidth: false) {
                    appModel.addMeal(meal)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring()) {
                        resolvedMeal = nil
                    }
                    dismiss()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.Palette.inkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1)
                )
        )
    }

    private var manualEntryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TYPE A BARCODE")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Theme.Palette.smoke)
            HStack(spacing: 10) {
                TextField("", text: $manualCode, prompt: Text("0049000028058").foregroundStyle(Theme.Palette.smoke))
                    .keyboardType(.numberPad)
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.5))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    )
                Button {
                    let code = manualCode.trimmingCharacters(in: .whitespaces)
                    guard !code.isEmpty else { return }
                    Task { await resolveCode(code) }
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Theme.Palette.paper))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.Palette.inkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1)
                )
        )
    }

    private var shutterRow: some View {
        HStack {
            Spacer()
            Button(action: capture) {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 3)
                        .frame(width: 78, height: 78)
                    Circle()
                        .fill(.white)
                        .frame(width: 64, height: 64)
                }
                .shadow(color: .black.opacity(0.5), radius: 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Capture meal photo")
            .accessibilityHint("Snaps a photo of the plate for AI parsing")
            .disabled(controller.cameraUnavailable || controller.isCapturing)
            .opacity(controller.cameraUnavailable ? 0.3 : 1.0)
            Spacer()
        }
    }

    // MARK: - Actions

    private func capture() {
        guard !controller.cameraUnavailable else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        controller.captureStill { image in
            guard let image else { return }
            capturedImage = image
            showingMealPhotoSheet = true
        }
    }

    /// Resolve a barcode through the existing BarcodeAPI client, then drop
    /// the parsed meal into the bottom card. Cooperates with the controller
    /// to update the in-flight lookup gate so frame-rate detections don't
    /// pile up.
    private func resolveCode(_ code: String) async {
        controller.beginLookup(code: code)
        defer { controller.endLookup(code: code) }

        do {
            let (meal, source) = try await BarcodeAPI.lookup(code: code)
            await MainActor.run {
                lastLookupError = nil
                resolvedSourceTag = source
                withAnimation(.spring()) {
                    resolvedMeal = MealEntry(
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
                }
                manualCode = ""
            }
        } catch BarcodeAPI.Error.notFound {
            // Surface the miss inline but keep the preview live — user can
            // re-aim or try a different code. Don't poison the cache so a
            // momentarily-misread scan can be retried later.
            await MainActor.run {
                lastLookupError = "Not in database. Try the shutter to parse the plate."
                controller.invalidateCache(for: code)
            }
        } catch {
            await MainActor.run {
                lastLookupError = "Lookup failed."
                controller.invalidateCache(for: code)
            }
        }
    }
}

// MARK: - AVFoundation controller
//
// Pulled out of the view so we can manage lifecycle precisely:
//   - Session start/stop runs on a serial background queue (Apple's API
//     guidance — `startRunning` blocks the calling thread for ~100ms on
//     real hardware).
//   - `lastDetectedCode` is published so the view's `.onChange` fires the
//     network lookup. The controller itself doesn't know what the lookup
//     does — only that it should debounce and rate-limit detections.
//   - `captureStill(_:)` triggers an AVCapturePhotoOutput delegate run and
//     hands the resulting `UIImage` back through a single callback.

final class UnifiedCameraController: NSObject, ObservableObject {
    /// Most-recent debounce-passed barcode payload. The view observes this
    /// and fires the network lookup. Cleared after a few seconds so the
    /// same code can re-fire if the user lingers (the cache then prevents
    /// the actual lookup from running).
    @Published var lastDetectedCode: String?
    /// True when the camera couldn't be configured — simulator, denied, no
    /// hardware. The view uses this to show the manual-entry fallback.
    @Published var cameraUnavailable: Bool = false
    /// Reflects an in-flight still capture so the view can disable the
    /// shutter while we're waiting on the photo-output delegate.
    @Published var isCapturing: Bool = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "vocal.unifiedcam.session", qos: .userInitiated)
    private let metadataOutput = AVCaptureMetadataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var didConfigure = false

    // MARK: Debounce + rate gating
    //
    // The metadata pipeline can fire multiple objects per frame; at video
    // frame rate that's many candidates per second. We don't want N
    // network requests per second hammering the resolver.

    /// 30-second cache of codes we already looked up. Re-detections of the
    /// same value within this window are silently dropped. The view can
    /// invalidate an entry by calling `invalidateCache(for:)` if the
    /// lookup came back with a definite "not found" — that lets the user
    /// retry the same can without dismissing and re-opening the sheet.
    private var recentlyLookedUp: [String: Date] = [:]
    private static let dedupeWindow: TimeInterval = 30
    /// Rough rate gate — never fire more than one detection-driven lookup
    /// per second across all codes (in addition to per-code debounce).
    private var lastDetectionDispatchAt: Date = .distantPast
    private static let minDetectionInterval: TimeInterval = 1.0
    /// True while a lookup is in flight for any code. Prevents stacking
    /// concurrent network calls even when the per-code dedupe lets two
    /// different codes through back-to-back.
    private var lookupInFlight: Bool = false

    private let captureDelegate = PhotoCaptureDelegate()

    // MARK: Lifecycle

    func start() {
        // Configure once. Async to keep the main thread free for the SwiftUI
        // animation in.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.didConfigure {
                self.configure()
            }
            if self.didConfigure, !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    /// Re-arm the session after a meal-photo-review sheet was presented and
    /// dismissed on top of us. AVCaptureSession halts video output while a
    /// modal photo capture runs; we explicitly resume it here.
    func resumeAfterCapture() {
        sessionQueue.async { [weak self] in
            guard let self, self.didConfigure, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    private func configure() {
        // Runs on `sessionQueue` (not main). Anything touching @Published
        // state hops to main via `setUnavailable`.
        guard let device = AVCaptureDevice.default(for: .video) else {
            setUnavailable(true); return
        }
        // Permission ladder — same shape as BarcodeScannerSheet's, but we
        // block this background queue on the user's grant so we don't wire
        // up a session against a denied device.
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            break
        case .notDetermined:
            let sem = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .video) { result in
                granted = result
                sem.signal()
            }
            sem.wait()
            if !granted {
                setUnavailable(true); return
            }
        case .denied, .restricted:
            setUnavailable(true); return
        @unknown default:
            setUnavailable(true); return
        }

        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            setUnavailable(true); return
        }
        session.beginConfiguration()
        // High preset so the still capture has enough resolution for the
        // vision model to identify food on the plate without being so high
        // that we waste battery on metadata throughput.
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }
        session.addInput(input)

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            // Delegate is delivered on the main queue so the bridging
            // hop into the MainActor methods is trivial.
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            // Same type set as the original BarcodeScannerSheet — covers
            // grocery (UPC/EAN), warehouse (Code 128/39), and the
            // occasional QR-coded product label.
            metadataOutput.metadataObjectTypes = [
                .ean8, .ean13, .upce, .code128, .code39, .code93, .qr, .pdf417, .interleaved2of5
            ].filter { metadataOutput.availableMetadataObjectTypes.contains($0) }
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()
        didConfigure = true
    }

    private func setUnavailable(_ value: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.cameraUnavailable = value
        }
    }

    // MARK: Debounce / rate-gate API
    //
    // Dedupe state lives behind a serial dispatch queue so the metadata
    // delegate (main) and the view-side lookup wrappers (main) can both
    // read/write it without explicit locks. In practice every call here
    // arrives on main already, but routing through `stateQueue` keeps the
    // contract honest if we ever move detection delivery off-main.

    private let stateQueue = DispatchQueue(label: "vocal.unifiedcam.state")

    func beginLookup(code: String) {
        stateQueue.sync {
            lookupInFlight = true
            recentlyLookedUp[code] = .now
        }
    }

    func endLookup(code: String) {
        stateQueue.sync {
            lookupInFlight = false
            // Refresh the cache timestamp on completion so we count from "we
            // finished talking to the network", not "we kicked off". Keeps a
            // slow lookup from being re-tried while it's still running.
            recentlyLookedUp[code] = .now
        }
    }

    /// Clear a single code from the cache so the user can retry it without
    /// the 30-second wait. Called when the lookup came back with a hard
    /// not-found / network error.
    func invalidateCache(for code: String) {
        stateQueue.sync {
            recentlyLookedUp.removeValue(forKey: code)
        }
    }

    // MARK: Photo capture

    func captureStill(completion: @escaping (UIImage?) -> Void) {
        guard didConfigure else {
            completion(nil); return
        }
        // `isCapturing` is published; mutate on main so SwiftUI picks it up.
        DispatchQueue.main.async { [weak self] in
            guard let self else { completion(nil); return }
            if self.isCapturing { completion(nil); return }
            self.isCapturing = true
            self.captureDelegate.completion = { [weak self] image in
                DispatchQueue.main.async {
                    self?.isCapturing = false
                    completion(image)
                }
            }
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .auto
            self.sessionQueue.async { [weak self] in
                guard let self else { return }
                self.photoOutput.capturePhoto(with: settings, delegate: self.captureDelegate)
            }
        }
    }
}

extension UnifiedCameraController: AVCaptureMetadataOutputObjectsDelegate {
    /// Called on the main queue (we set `setMetadataObjectsDelegate(_:queue:)`
    /// with `.main`). Synchronously checks the debounce/rate gates and
    /// publishes a new detection if the code passes.
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = obj.stringValue else { return }
        // Strip to digits and validate (same shape as the legacy scanner).
        let digits = stringValue.unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }
            .map { String($0) }
            .joined()
        guard (8...14).contains(digits.count) else { return }

        let now = Date.now
        let shouldDispatch: Bool = stateQueue.sync {
            if lookupInFlight { return false }
            if now.timeIntervalSince(lastDetectionDispatchAt) < Self.minDetectionInterval {
                return false
            }
            if let last = recentlyLookedUp[digits],
               now.timeIntervalSince(last) < Self.dedupeWindow {
                return false
            }
            lastDetectionDispatchAt = now
            return true
        }
        guard shouldDispatch else { return }

        // Light haptic so the user knows we saw the code even before
        // the card animates in.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        lastDetectedCode = digits
    }
}

/// Stand-alone delegate so the controller doesn't have to host the
/// `AVCapturePhotoCaptureDelegate` conformance directly (the conformance
/// requires NSObject + a specific signature shape that would otherwise
/// pollute the ObservableObject's interface).
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    var completion: ((UIImage?) -> Void)?

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let raw = UIImage(data: data) else {
            completion?(nil); completion = nil; return
        }
        // Downsample before handing off — same memory hygiene as the legacy
        // photo flows. 48 MP frames sitting in @State across a sheet
        // present is an OOM trap.
        let small = CapturedImage.downsample(raw)
        completion?(small)
        completion = nil
    }
}

// MARK: - Camera preview layer wrapper

/// SwiftUI bridge that hosts the AVCaptureVideoPreviewLayer on a UIKit
/// view. Mirrors the legacy `BarcodeCameraView` so the preview rendering
/// pipeline is identical (resizeAspectFill, layout-driven frame).
struct UnifiedCameraPreview: UIViewRepresentable {
    let controller: UnifiedCameraController

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.session = controller.session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.session = controller.session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var session: AVCaptureSession? {
            get { previewLayer.session }
            set {
                previewLayer.session = newValue
                previewLayer.videoGravity = .resizeAspectFill
            }
        }
    }
}

#Preview {
    UnifiedCameraSheet()
        .environmentObject(AppModel(
            totals: MockData.today,
            meals: [],
            profile: MockData.profile
        ))
        .preferredColorScheme(.dark)
}
