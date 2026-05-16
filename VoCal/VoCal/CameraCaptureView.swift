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

// MARK: - Camera picker (system camera)

struct CameraPicker: UIViewControllerRepresentable {
    enum Source { case camera, library }

    @Environment(\.dismiss) private var dismiss
    let source: Source
    let onPicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        switch source {
        case .camera:
            picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
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
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
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
            CameraPicker(source: .camera) { picked in
                image = picked
                startListening()
            }
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
    /// tapping the text field.
    private func startListening() {
        Task {
            await recorder.requestAuthorization()
            guard recorder.isAuthorized else { return }
            try? recorder.start()
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
                        _ = recorder.finish()
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
                recorder.stop()
            }
            if firstPassMeal == nil && followUpQuestion == nil {
                // Pre-parse: send the spoken description through /api/voice/parse.
                VoltageButton(title: "Parse", icon: "arrow.right") {
                    Task { await parseDescription() }
                }
                .opacity(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .allowsHitTesting(!description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else if let _ = followUpQuestion {
                // Backend asked a refining question — submit the answer.
                VoltageButton(title: "Submit", icon: "arrow.right") {
                    Task { await answerFollowUp() }
                }
                .opacity(followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .allowsHitTesting(!followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                // Parsed cleanly — save it.
                VoltageButton(title: "Save", icon: "checkmark") {
                    commit(source: .voicePhoto)
                }
            }
        }
    }

    // MARK: AI pipeline
    //
    // The photo is decorative. The spoken description (`description`) is
    // what we send to /api/voice/parse — the same conversational engine
    // VoiceCaptureSheet uses. That endpoint already knows how to ask smart
    // follow-ups ("Single scoop of guac?"), so the photo flow gets refine
    // loops for free.
    //
    // A real plate-vision pass is still available via /api/photo/parse
    // (Wafer GLM-5.1 → OpenRouter gpt-4o-mini), but is intentionally not
    // wired here yet — the spoken description outperforms a pure photo
    // parse for most plates.

    private func parseDescription() async {
        let transcript = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        // Flush mic if still capturing — get the user's final words in.
        if recorder.isRecording {
            let final = recorder.finish()
            if !final.isEmpty { description = final }
        }
        parsing = true
        defer { parsing = false }
        do {
            let response = try await VoiceParseAPI.parse(
                transcript: description.trimmingCharacters(in: .whitespacesAndNewlines),
                followUp: nil
            )
            lastReasoning = response.reasoning
            if let q = response.follow_up_question, response.meal == nil {
                followUpQuestion = q
            } else if let meal = response.meal {
                firstPassMeal = meal
            } else {
                followUpQuestion = "Could you add a portion size or brand name?"
            }
        } catch {
            followUpQuestion = "Couldn't reach the server. Add a brand or portion and try again?"
        }
    }

    private func answerFollowUp() async {
        parsing = true
        defer { parsing = false }
        let answer = followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let response = try await VoiceParseAPI.parse(
                transcript: description.trimmingCharacters(in: .whitespacesAndNewlines),
                followUp: answer
            )
            lastReasoning = response.reasoning
            if let meal = response.meal {
                firstPassMeal = meal
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
            followUpQuestion = "Couldn't reach the server. Try a brand or portion size?"
            followUpAnswer = ""
        }
    }

    private func commit(meal optionalMeal: VoiceParseResponse.ParsedMeal? = nil, source: MealEntry.Source = .photo) {
        guard let m = optionalMeal ?? firstPassMeal else { return }
        let entry = MealEntry(
            name: m.name,
            detail: m.detail,
            calories: m.kcal,
            protein: m.protein_g,
            carbs: m.carbs_g,
            fat: m.fat_g,
            loggedAt: .now,
            slot: MealEntry.Slot(rawValue: m.slot) ?? .snack,
            source: source
        )
        appModel.addMeal(entry)
        savedMeal = entry
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
