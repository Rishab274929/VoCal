//
//  CameraCaptureView.swift
//  VoCal
//
//  Lightweight camera + photo-library wrapper for the meal photo +
//  body-photo flows. Uses UIImagePickerController under a SwiftUI
//  representable so we get the system camera UI without rolling our
//  own AVCaptureSession. Returns a `UIImage` via callback.
//

import SwiftUI
import UIKit
import PhotosUI
import AVFoundation

// MARK: - Image helpers
//
// iPhone 17 Pro captures at 48 MP (~12,000×8,000 ≈ 140 MB uncompressed in
// memory once UIKit decodes the JPEG). Holding even one of those in `@State`
// across a SwiftUI re-render path was OOM'ing previews on older devices and
// thrashing memory on newer ones. Downsample the moment the picker hands us
// the image — never let the original-resolution bitmap live longer than the
// picker callback.

enum CapturedImage {
    /// 2,048 px on the longest edge: well under the screen's native scale
    /// even on iPad Pro, fully covers the 768 px upload size, and renders
    /// cleanly in SwiftUI without re-decoding the full sensor frame.
    static let maxEdge: CGFloat = 2048

    /// Aspect-fit downsample. Honors `imageOrientation` (camera captures are
    /// often `.right` / `.up` from sensor; UIKit fixes orientation at draw
    /// time so the returned image always has `.up`). Returns the original
    /// if it's already small enough.
    static func downsample(_ image: UIImage, maxEdge: CGFloat = maxEdge) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let longest = max(w, h)
        guard longest > maxEdge, longest > 0 else { return image }
        let scale = maxEdge / longest
        let target = CGSize(width: floor(w * scale), height: floor(h * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

// MARK: - Camera picker (system camera)

struct CameraPicker: UIViewControllerRepresentable {
    enum Source { case camera, library }

    @Environment(\.dismiss) private var dismiss
    let source: Source
    let onPicked: (UIImage) -> Void
    /// Optional hook for surfacing permission denials back to the host view.
    /// When set and access is `.denied` / `.restricted`, the picker is not
    /// instantiated and this is called with `false` instead.
    var onAuthorization: ((Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        switch source {
        case .camera:
            // Defensive: AVCaptureDevice.authorizationStatus reflects whether
            // the user has granted camera. UIImagePickerController would show
            // a black screen on `.denied` without surfacing it — we want to
            // bail out so the host can show a permissions hint instead.
            let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            if cameraAvailable && (status == .authorized || status == .notDetermined) {
                picker.sourceType = .camera
                if status == .notDetermined {
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        DispatchQueue.main.async { self.onAuthorization?(granted) }
                    }
                }
            } else {
                // Denied / restricted / simulator → library fallback so we
                // never present an unusable camera view.
                picker.sourceType = .photoLibrary
                if status == .denied || status == .restricted {
                    DispatchQueue.main.async { self.onAuthorization?(false) }
                }
            }
        case .library:
            picker.sourceType = .photoLibrary
        }
        picker.allowsEditing = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let raw = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            // Downsample BEFORE the SwiftUI binding receives it. Keeps the
            // 48 MP sensor frame from living in `@State` for the lifetime of
            // the sheet.
            let image = raw.map { CapturedImage.downsample($0) }
            picker.dismiss(animated: true) {
                if let image { self.parent.onPicked(image) }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Meal photo capture sheet
//
// Snaps or selects a meal photo, shows a first-pass "AI parsing…" preview,
// then routes into the voice follow-up flow ("Anything underneath I can't
// see?") which feeds the existing voice parse pipeline.

struct MealPhotoSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var parsing = false
    @State private var firstPassMeal: VoiceParseResponse.ParsedMeal?
    @State private var followUpQuestion: String?
    @State private var followUpAnswer = ""
    @State private var savedMeal: MealEntry?
    /// Source returned by the backend (`"photo"` vs `"voice+photo"`); we mirror
    /// that into `MealEntry.Source` instead of hardcoding `.voicePhoto`, which
    /// previously stamped every save as `voice+photo` even when the user never
    /// spoke a word.
    @State private var parsedSourceTag: String = "photo"
    /// Surfaced to the user when mic/speech permission is denied — without
    /// this the SpeechRecorder silently no-ops and the live-transcript
    /// affordance just stays inert.
    @State private var micPermissionDenied = false
    /// Surfaced when the camera permission is denied at the system level.
    @State private var cameraPermissionDenied = false

    /// Spoken description of the plate. The photo is decorative — this
    /// transcript is what we actually send to /api/voice/parse for the
    /// conversational refine loop.
    @State private var description: String = ""
    @State private var lastReasoning: String = ""
    @StateObject private var recorder = SpeechRecorder()

    var body: some View {
        ZStack {
            Theme.Palette.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 12)

                if let img = image {
                    previewBlock(img: img)
                } else {
                    captureChoiceBlock
                }

                Spacer()

                if image != nil && savedMeal == nil {
                    confirmFooter
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker(
                source: .camera,
                onPicked: { picked in
                    image = picked
                    startListening()
                },
                onAuthorization: { granted in
                    cameraPermissionDenied = !granted
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingLibrary) {
            CameraPicker(source: .library) { picked in
                image = picked
                startListening()
            }
            .ignoresSafeArea()
        }
        .onDisappear { recorder.stop() }
        .onChange(of: recorder.partialTranscript) { _, new in
            if recorder.isRecording { description = new }
        }
    }

    /// Asks for mic + speech perms and starts continuous on-device STT
    /// the moment the photo is captured. The user can stop and edit by
    /// tapping the text field. Surfaces a denial flag so the user isn't
    /// left wondering why the live-transcript dot never lights up.
    private func startListening() {
        Task {
            await recorder.requestAuthorization()
            guard recorder.isAuthorized else {
                micPermissionDenied = true
                return
            }
            micPermissionDenied = false
            do {
                try recorder.start()
            } catch {
                // SpeechRecorder.start can throw if audio session setup fails
                // mid-flight (eg. a phone call grabs the input). Treat that
                // as a "speak later" — typed input still works.
                micPermissionDenied = true
            }
        }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("MEAL PHOTO")
                    .eyebrow(Theme.Palette.pulse)
                Text(image == nil ? "Snap what's on the plate." : "Here's what I see.")
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

    // MARK: capture choice

    private var captureChoiceBlock: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                    .frame(height: 240)
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Theme.Palette.voltage)
                    Text("Photo-first logging")
                        .font(Theme.Font.serif(18, weight: .medium))
                        .foregroundStyle(Theme.Palette.bone)
                    Text("I'll start with a guess and ask one quick follow-up.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.smoke)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            HStack(spacing: 10) {
                GhostButton(title: "Library", icon: "photo.on.rectangle") { showingLibrary = true }
                VoltageButton(title: "Open camera", icon: "camera.fill") { showingCamera = true }
            }
            if cameraPermissionDenied {
                Text("Camera access is off. Tap Library, or enable the camera in Settings → VoCal.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.pulse)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: preview

    private func previewBlock(img: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1)
                )

            if parsing {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.Palette.voltage).controlSize(.small)
                    Text("Parsing your description…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.smoke)
                }
            } else if let saved = savedMeal {
                resultCard(meal: saved)
            } else if let q = followUpQuestion {
                FollowUpQuestionCard(question: q, answer: $followUpAnswer)
            } else if let m = firstPassMeal {
                preCard(m)
            } else {
                // Pre-parse state: photo on top, mic + transcript below.
                // The photo is decorative — what we actually send to the
                // backend is the spoken description.
                descriptionBlock
            }
        }
    }

    /// Mic + transcript composer. Routes through the same /api/voice/parse
    /// the voice flow uses, so the model can ask the same smart follow-ups
    /// ("Single scoop of guac?") on top of the picture.
    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(recorder.isRecording ? "LIVE — say what's on the plate" : "DESCRIBE WHAT YOU'RE EATING")
                    .eyebrow(recorder.isRecording ? Theme.Palette.pulse : Theme.Palette.smoke)
                if recorder.isRecording {
                    Circle()
                        .fill(Theme.Palette.pulse)
                        .frame(width: 6, height: 6)
                        .scaleEffect(recorder.isRecording ? 1 : 0.5)
                        .animation(.easeInOut(duration: 0.6).repeatForever(), value: recorder.isRecording)
                }
            }
            if micPermissionDenied {
                Text("Mic access is off — type what's on the plate, or enable it in Settings → VoCal.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.pulse)
            }
            if cameraPermissionDenied && image == nil {
                Text("Camera access is off — pick from your library or enable it in Settings → VoCal.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.pulse)
            }
            TextField(
                "",
                text: $description,
                prompt: Text("beans and rice, plus some chicken").foregroundStyle(Theme.Palette.smoke),
                axis: .vertical
            )
            .lineLimit(2...4)
            .foregroundStyle(Theme.Palette.bone)
            .textInputAutocapitalization(.sentences)
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(Theme.Palette.inkSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1)
                    )
            )
            HStack(spacing: 10) {
                Button {
                    if recorder.isRecording {
                        Task { _ = await recorder.finish() }
                    } else {
                        startListening()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(recorder.isRecording ? "Stop" : "Hold to speak")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(recorder.isRecording ? Theme.Palette.pulse : Theme.Palette.voltage))
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
    }

    private func preCard(_ meal: VoiceParseResponse.ParsedMeal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FIRST PASS")
                .eyebrow()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(meal.kcal)")
                    .font(Theme.Font.serif(40, weight: .medium))
                    .foregroundStyle(Theme.Palette.bone)
                    .monospacedDigit()
                Text("kcal")
                    .font(Theme.Font.serif(16, weight: .regular, italic: true))
                    .foregroundStyle(Theme.Palette.smoke)
            }
            Text(meal.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.bone)
            HStack(spacing: 8) {
                MacroPill(letter: "P", value: meal.protein_g, tint: Theme.Palette.protein)
                MacroPill(letter: "C", value: meal.carbs_g, tint: Theme.Palette.carbs)
                MacroPill(letter: "F", value: meal.fat_g, tint: Theme.Palette.fat)
            }
        }
        .padding(16)
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

    private func resultCard(meal: MealEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LOGGED")
                .eyebrow(Theme.Palette.voltage)
            Text(meal.name)
                .font(Theme.Font.serif(22, weight: .medium))
                .foregroundStyle(Theme.Palette.bone)
            Text("\(meal.calories) kcal · \(meal.protein)P · \(meal.carbs)C · \(meal.fat)F")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.ash)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Palette.voltage.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Palette.voltage.opacity(0.5), lineWidth: 1)
                )
        )
    }

    // MARK: footer

    private var confirmFooter: some View {
        HStack(spacing: 12) {
            GhostButton(title: "Retake", icon: "arrow.counterclockwise") {
                image = nil
                firstPassMeal = nil
                followUpQuestion = nil
                followUpAnswer = ""
                description = ""
                lastReasoning = ""
                parsedSourceTag = "photo"
                recorder.stop()
            }
            if firstPassMeal == nil && followUpQuestion == nil {
                // Pre-parse: route through the photo or voice endpoint
                // depending on what we have. With a photo the spoken
                // description is optional — vision can read the plate
                // by itself — so Parse is enabled as long as EITHER input
                // is present.
                let hasDescription = !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let canParse = hasDescription || image != nil
                VoltageButton(title: "Parse", icon: "arrow.right") {
                    Task { await parseDescription() }
                }
                .opacity(canParse ? 1 : 0.4)
                .allowsHitTesting(canParse)
            } else if let _ = followUpQuestion {
                // Backend asked a refining question — submit the answer.
                VoltageButton(title: "Submit", icon: "arrow.right") {
                    Task { await answerFollowUp() }
                }
                .opacity(followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .allowsHitTesting(!followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                // Parsed cleanly — save it. Source is taken from the backend
                // response (photo / voice+photo / voice) inside commit().
                VoltageButton(title: "Save", icon: "checkmark") {
                    commit()
                }
            }
        }
    }

    // MARK: AI pipeline
    //
    // Photo-first when an image is present: route through /api/photo/parse
    // (Wafer GLM-5.1 → Gemini Flash → OpenRouter gpt-4o-mini) with the
    // spoken description riding along as `voice_context`. The vision model
    // can ask the same kind of clarifying question the voice flow does
    // ("Single scoop of guac?") and we replay the user's answer through
    // the same endpoint with `followUpAnswer` set.
    //
    // Defensive: if no photo is present (shouldn't happen in this sheet —
    // `parseDescription` is only reachable after `previewBlock` renders —
    // but belt-and-suspenders) we fall back to the voice-only path so the
    // user can still log via typed/spoken description.

    private func parseDescription() async {
        // Flush mic if still capturing — get the user's final words in.
        if recorder.isRecording {
            let final = await recorder.finish()
            if !final.isEmpty { description = final }
        }
        let transcript = description.trimmingCharacters(in: .whitespacesAndNewlines)
        // With a photo, an empty transcript is OK — the vision model can
        // parse the plate from pixels alone. Without a photo we still need
        // *something* to send.
        if image == nil && transcript.isEmpty { return }
        parsing = true
        defer { parsing = false }
        do {
            let response = try await runParse(
                transcript: transcript.isEmpty ? nil : transcript,
                followUp: nil
            )
            lastReasoning = response.reasoning
            if let q = response.follow_up_question, response.meal == nil {
                followUpQuestion = q
            } else if let meal = response.meal {
                firstPassMeal = meal
                parsedSourceTag = meal.source
            } else {
                followUpQuestion = "Could you add a portion size or brand name?"
            }
        } catch {
            // Surface the real reason so the user knows it's a network issue
            // rather than the backend rejecting their description. Do NOT
            // fall back to a fabricated meal — the brief is explicit that
            // we must not silently invent 450-kcal stubs.
            followUpQuestion = "Couldn't reach the server (\(error.localizedDescription)). Add a brand or portion and try again?"
        }
    }

    private func answerFollowUp() async {
        parsing = true
        defer { parsing = false }
        let transcript = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        // Treat universal opt-outs as "nothing extra" so the backend doesn't
        // get tripped up trying to parse "no" / "nope" / "skip" as a food.
        let normalized = answer.lowercased()
        let isOptOut: Bool = {
            switch normalized {
            case "", "no", "nope", "n", "none", "nothing", "skip", "no thanks", "nah":
                return true
            default:
                return false
            }
        }()
        let effectiveAnswer = isOptOut ? "nothing extra" : answer
        do {
            let response = try await runParse(
                transcript: transcript.isEmpty ? nil : transcript,
                followUp: effectiveAnswer
            )
            lastReasoning = response.reasoning
            if let meal = response.meal {
                firstPassMeal = meal
                parsedSourceTag = meal.source
                followUpQuestion = nil
            } else if let q = response.follow_up_question {
                // Server wants another round — keep refining.
                followUpQuestion = q
                followUpAnswer = ""
            } else {
                followUpQuestion = "Still not enough info to log. Add a brand or portion?"
                followUpAnswer = ""
            }
        } catch {
            followUpQuestion = "Couldn't reach the server (\(error.localizedDescription)). Try a brand or portion size?"
            followUpAnswer = ""
        }
    }

    /// Single dispatch point so both `parseDescription` and `answerFollowUp`
    /// pick the photo endpoint when an image is present and the voice
    /// endpoint when it isn't. Keeps the network-error handling and the
    /// caller-side state mutation in one branch each.
    private func runParse(transcript: String?, followUp: String?) async throws -> VoiceParseResponse {
        if let img = image {
            return try await PhotoParseAPI.parse(
                image: img,
                voiceContext: transcript,
                followUpAnswer: followUp
            )
        }
        // Defensive voice-only path. Shouldn't be reached in normal use of
        // this sheet because `parseDescription` is gated behind an image,
        // but a future refactor that drops the gate gets safe behavior.
        return try await VoiceParseAPI.parse(
            transcript: transcript ?? "",
            followUp: followUp
        )
    }

    /// Map the backend's `source` string ("photo", "voice+photo", "voice")
    /// onto our local enum so the meal entry is tagged honestly. Falls back
    /// to `.photo` for unknown values.
    private static func mapSource(_ tag: String) -> MealEntry.Source {
        switch tag {
        case "voice+photo": return .voicePhoto
        case "voice":       return .voice
        case "barcode":     return .barcode
        case "manual":      return .manual
        default:            return .photo
        }
    }

    private func commit(meal optionalMeal: VoiceParseResponse.ParsedMeal? = nil, source: MealEntry.Source? = nil) {
        guard let m = optionalMeal ?? firstPassMeal else { return }
        // Prefer the backend's source tag (`photo` vs `voice+photo` vs `voice`)
        // over the caller's hint so we don't stamp every photo-flow save as
        // `voice+photo` when the user actually skipped speaking.
        let effectiveSource = source ?? Self.mapSource(parsedSourceTag)
        let entry = MealEntry(
            name: m.name,
            detail: m.detail,
            calories: m.kcal,
            protein: m.protein_g,
            carbs: m.carbs_g,
            fat: m.fat_g,
            loggedAt: .now,
            slot: MealEntry.Slot(rawValue: m.slot) ?? .snack,
            source: effectiveSource
        )
        appModel.addMeal(entry)
        savedMeal = entry
        // Free the captured image bitmap once we've committed so it doesn't
        // sit in `@State` through the auto-dismiss delay.
        image = nil
        // Auto-dismiss after a beat so the user sees the confirmation
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run { dismiss() }
        }
    }
}

#Preview {
    MealPhotoSheet()
        .environmentObject(AppModel(
            totals: MockData.today,
            meals: MockData.recentMeals,
            profile: MockData.profile
        ))
        .preferredColorScheme(.dark)
}
