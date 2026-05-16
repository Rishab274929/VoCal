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
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker(source: .camera) { picked in
                image = picked
                Task { await runFirstPass() }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingLibrary) {
            CameraPicker(source: .library) { picked in
                image = picked
                Task { await runFirstPass() }
            }
            .ignoresSafeArea()
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
                    Text("Analyzing photo…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.smoke)
                }
            } else if let saved = savedMeal {
                resultCard(meal: saved)
            } else if let q = followUpQuestion {
                FollowUpQuestionCard(question: q, answer: $followUpAnswer)
            } else if let m = firstPassMeal {
                preCard(m)
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
            }
            VoltageButton(title: followUpQuestion == nil ? "Save" : "Submit", icon: followUpQuestion == nil ? "checkmark" : "arrow.right") {
                if followUpQuestion == nil { commit() }
                else { Task { await answerFollowUp() } }
            }
            .opacity((followUpQuestion != nil && followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.4 : 1)
            .allowsHitTesting(followUpQuestion == nil || !followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: AI pipeline
    //
    // Two-shot flow:
    //   1. First pass with only the image → backend gpt-4o-mini parses
    //      visible ingredients and returns either a meal or a follow-up
    //      question ("Anything underneath I can't see?").
    //   2. If a follow-up came back, the user types their answer and we
    //      submit the SAME image plus the answer as `voice_context`. The
    //      vision model re-parses with the hidden-layer hint.

    private func runFirstPass() async {
        guard let img = image else { return }
        parsing = true
        defer { parsing = false }
        do {
            let response = try await PhotoParseAPI.parse(image: img, voiceContext: nil)
            if let q = response.follow_up_question, response.meal == nil {
                firstPassMeal = nil
                followUpQuestion = q
            } else if let meal = response.meal {
                firstPassMeal = meal
                followUpQuestion = nil
            } else {
                firstPassMeal = .init(
                    name: "Photo unparsed",
                    detail: "Try the voice flow instead, or try again with a clearer shot.",
                    kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0,
                    slot: "snack", source: "photo", confidence: 0.0
                )
            }
        } catch {
            firstPassMeal = .init(
                name: "Photo parse failed",
                detail: error.localizedDescription,
                kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0,
                slot: "snack", source: "photo", confidence: 0.0
            )
        }
    }

    private func answerFollowUp() async {
        guard let img = image else { return }
        parsing = true
        defer { parsing = false }
        let answer = followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let response = try await PhotoParseAPI.parse(image: img, voiceContext: answer)
            if let meal = response.meal {
                firstPassMeal = meal
                followUpQuestion = nil
                commit(meal: meal, source: .voicePhoto)
            } else {
                // Backend wants another follow-up. Show it; user can answer again.
                followUpQuestion = response.follow_up_question
                followUpAnswer = ""
            }
        } catch {
            followUpQuestion = "Couldn't reach the vision model. Tap Save to log a rough estimate, or Retake to try again."
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
