//
//  CoachView.swift
//  VoCal
//
//  Voice-first nutrition coach. Tap-and-talk via VoiceCoachSession:
//   - mic button starts continuous on-device STT
//   - after a 1.5s silence the transcript flushes to the backend /api/coach
//   - the reply is rendered in the thread AND read aloud via AVSpeechSynthesizer
//   - typed input also works for accessibility / quiet rooms
//

import SwiftUI

struct CoachView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var session = VoiceCoachSession()
    @State private var input: String = ""

    /// User-controlled audio mute. Persists across launches so a user who
    /// always studies in quiet places doesn't have to re-mute every time
    /// they open Coach. Mirror of the SharedPreferences key on the Flutter
    /// side so the same setting feels consistent across platforms (note:
    /// not synced — each install holds its own value).
    @AppStorage("vocal.coachVoiceEnabled") private var voiceEnabled: Bool = true

    /// Combined transcript: AppModel's persisted history + this session's
    /// in-memory turns. Lets the user pick up a conversation across launches.
    private var allMessages: [CoachMessage] {
        appModel.coachMessages + session.history
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 18)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        introBlock
                        ForEach(allMessages) { msg in
                            CoachBubble(role: msg.role, content: msg.content)
                                .id(msg.id)
                        }
                        if !session.liveTranscript.isEmpty && session.phase == .listening {
                            // Show the live partial transcript as a pending user bubble.
                            CoachBubble(role: .user, content: session.liveTranscript + " …")
                                .opacity(0.55)
                        }
                        if session.phase == .thinking {
                            statusRow("Coach is thinking…")
                        }
                        if session.phase == .speaking {
                            statusRow("Speaking…")
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.hidden)
                .onChange(of: allMessages.count) { _, _ in
                    if let last = allMessages.last {
                        withAnimation(.spring) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            composer
                .padding(.horizontal, 28)
                .padding(.bottom, 16)
        }
        .onAppear {
            // Sync the persisted user preference into the session on first
            // render. Without this, a user who muted last session would
            // still hear the first reply this session because the session
            // defaults voiceEnabled=true.
            session.voiceEnabled = voiceEnabled
        }
        .onDisappear { session.cancel() }
        .onChange(of: session.history.count) { _, _ in
            // Mirror VoiceCoachSession turns into the persisted AppModel
            // history so they survive force-quit. Only append the newest
            // turn (history index N-1) to avoid quadratic appends.
            guard let latest = session.history.last else { return }
            // De-dupe: if the last persisted message has the same content
            // already, skip.
            if appModel.coachMessages.last?.content != latest.content {
                appModel.appendCoach(latest)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("COACH")
                    .eyebrow(Theme.Palette.pulse)
                Spacer()
                voiceToggle
                statusBadge
            }
            Text("Talk to it. It knows your day.")
                .font(Theme.Font.serif(28, weight: .medium))
                .foregroundStyle(Theme.Palette.bone)
        }
    }

    /// Top-right speaker icon — taps toggle audio playback for coach replies.
    /// The icon swaps to a slash when muted so the state is unambiguous at
    /// a glance. We also `cancel()` an in-flight audio reply on the way to
    /// muted so the user isn't stuck listening to the current line finish.
    /// Pulses subtly while `session.isSpeaking` so the user gets visual
    /// confirmation that audio is actually playing (not just thinking).
    private var voiceToggle: some View {
        Button {
            voiceEnabled.toggle()
            session.voiceEnabled = voiceEnabled
            if !voiceEnabled {
                // Yank any audio that's already playing. cancel() also
                // drops a pending TTS fetch, so flipping the switch
                // mid-reply truly silences the coach immediately.
                session.cancel()
            }
        } label: {
            Image(systemName: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(voiceEnabled ? Theme.Palette.voltage : Theme.Palette.smoke)
                .frame(width: 28, height: 28)
                .background(
                    Circle().strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1)
                )
                .scaleEffect(session.isSpeaking ? 1.08 : 1.0)
                .animation(
                    session.isSpeaking
                        ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true)
                        : .default,
                    value: session.isSpeaking
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(voiceEnabled ? "Mute coach voice" : "Unmute coach voice")
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch session.phase {
        case .idle:
            HStack(spacing: 6) {
                Circle().fill(Theme.Palette.voltage).frame(width: 6, height: 6)
                Text("on duty")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Palette.smoke)
            }
        case .listening:
            HStack(spacing: 6) {
                Circle().fill(Theme.Palette.pulse).frame(width: 6, height: 6)
                    .scaleEffect(1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(), value: session.phase)
                Text("LISTENING")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Palette.pulse)
            }
        case .thinking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(Theme.Palette.voltage)
                Text("THINKING")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Palette.voltage)
            }
        case .speaking:
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.voltage)
                Text("SPEAKING")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Palette.voltage)
            }
        }
    }

    private func statusRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small).tint(Theme.Palette.voltage)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.smoke)
        }
        .padding(.leading, 16)
    }

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Palette.voltage)
                Text(allMessages.isEmpty ? "Try saying" : "Or ask")
                    .eyebrow()
            }
            VStack(alignment: .leading, spacing: 8) {
                suggestionPill("How do I hit 180g protein today?")
                suggestionPill("What if I want pasta for dinner?")
                suggestionPill("What's a good 4pm snack?")
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
                    prompt: Text("Ask anything, or tap the mic…").foregroundStyle(Theme.Palette.smoke)
                )
                .foregroundStyle(Theme.Palette.bone)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .onSubmit { sendTyped() }
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
                if !input.isEmpty {
                    sendTyped()
                } else {
                    switch session.phase {
                    case .listening: session.endTurn()
                    case .speaking:  session.cancel()
                    default:         session.startTurn()
                    }
                }
            } label: {
                ZStack {
                    Circle().fill(micButtonTint)
                    Image(systemName: micButtonIcon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                }
                .frame(width: 44, height: 44)
                .shadow(color: micButtonTint.opacity(0.4), radius: 12)
            }
            .buttonStyle(.plain)
        }
    }

    private var micButtonTint: Color {
        if !input.isEmpty { return Theme.Palette.voltage }
        switch session.phase {
        case .listening: return Theme.Palette.pulse
        case .speaking:  return Theme.Palette.voltage
        default:         return Theme.Palette.pulse
        }
    }

    private var micButtonIcon: String {
        if !input.isEmpty { return "arrow.up" }
        switch session.phase {
        case .listening: return "stop.fill"
        case .speaking:  return "speaker.slash.fill"
        default:         return "mic.fill"
        }
    }

    private func sendTyped() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        input = ""
        session.sendTyped(trimmed)
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
