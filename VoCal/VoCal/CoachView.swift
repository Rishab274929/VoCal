//
//  CoachView.swift
//  VoCal
//
//  Voice-first nutrition coach. Big serif intro, message thread,
//  composer with mic-first input. Calls backend /api/coach when wired;
//  uses heuristic replies offline so the demo always feels alive.
//

import SwiftUI

struct CoachView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var input: String = ""
    @State private var isThinking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 18)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        introBlock
                        ForEach(appModel.coachMessages) { msg in
                            CoachBubble(role: msg.role, content: msg.content)
                                .id(msg.id)
                        }
                        if isThinking {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Theme.Palette.voltage)
                                Text("thinking…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.Palette.smoke)
                            }
                            .padding(.leading, 16)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.hidden)
                .onChange(of: appModel.coachMessages.count) { _, _ in
                    if let last = appModel.coachMessages.last {
                        withAnimation(.spring) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            composer
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("COACH")
                    .eyebrow(Theme.Palette.pulse)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Theme.Palette.voltage).frame(width: 6, height: 6)
                    Text("on duty")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Palette.smoke)
                }
            }
            Text("Talk to it. It knows your day.")
                .font(Theme.Font.serif(28, weight: .medium))
                .foregroundStyle(Theme.Palette.bone)
        }
    }

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Palette.voltage)
                Text("Try asking")
                    .eyebrow()
            }
            VStack(alignment: .leading, spacing: 8) {
                suggestionPill("How do I hit 180g protein today?")
                suggestionPill("What if I want pasta for dinner?")
                suggestionPill("Why am I always hungry at 4pm?")
            }
        }
        .padding(.bottom, 4)
    }

    private func suggestionPill(_ text: String) -> some View {
        Button {
            input = text
        } label: {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.ash)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule().strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField(
                    "",
                    text: $input,
                    prompt: Text("Ask anything…").foregroundStyle(Theme.Palette.smoke)
                )
                .foregroundStyle(Theme.Palette.bone)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .onSubmit { send() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.Palette.inkSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1)
                    )
            )

            Button {
                if input.isEmpty {
                    // Mic mode (stub)
                } else {
                    send()
                }
            } label: {
                ZStack {
                    Circle().fill(input.isEmpty ? Theme.Palette.pulse : Theme.Palette.voltage)
                    Image(systemName: input.isEmpty ? "mic.fill" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                }
                .frame(width: 44, height: 44)
                .shadow(color: (input.isEmpty ? Theme.Palette.pulse : Theme.Palette.voltage).opacity(0.4), radius: 12)
            }
            .buttonStyle(.plain)
        }
    }

    private func send() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appModel.appendCoach(CoachMessage(role: .user, content: trimmed))
        input = ""
        isThinking = true
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            let reply = generateReply(for: trimmed)
            await MainActor.run {
                appModel.appendCoach(CoachMessage(role: .assistant, content: reply))
                isThinking = false
            }
        }
    }

    private func generateReply(for prompt: String) -> String {
        let lower = prompt.lowercased()
        let proteinShort = max(0, appModel.totals.proteinGoal - appModel.totals.proteinEaten)
        let kcalLeft = appModel.totals.calorieRemaining

        if lower.contains("protein") {
            return "You're at \(appModel.totals.proteinEaten)g of \(appModel.totals.proteinGoal)g protein — \(proteinShort)g short with \(kcalLeft) kcal left. A grilled chicken bowl from Cava (≈40g protein, ~520 kcal) or Chick-fil-A's grilled nuggets 12-ct (~38g protein, ~210 kcal) would clear most of it."
        }
        if lower.contains("pasta") || lower.contains("dinner") {
            return "With \(kcalLeft) kcal to play with, a 2-cup serving of spaghetti pomodoro lands around 560 kcal. Add a 4 oz grilled chicken breast (~190 kcal, 35g protein) and you're at 750 kcal — well under budget, and you finish the day on protein."
        }
        if lower.contains("hungry") || lower.contains("snack") {
            return "Could be a protein gap — you've leaned breakfast-heavy and light on protein at lunch. A Greek yogurt + handful of almonds (~250 kcal, 18g protein) usually kills the 4pm dip without ruining dinner."
        }
        return "I'm watching your day: \(appModel.totals.caloriesEaten) eaten, \(kcalLeft) remaining, \(appModel.totals.proteinEaten)g protein in. What were you thinking of having?"
    }
}

#Preview {
    CoachView()
        .environmentObject(AppModel(
            totals: MockData.today,
            meals: MockData.recentMeals,
            profile: MockData.profile,
            coachMessages: MockData.coachIntro
        ))
        .preferredColorScheme(.dark)
        .background(Theme.Palette.ink)
}
