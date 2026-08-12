import SwiftUI

/// Compose a new gateway cron job from the phone: name, prompt, schedule
/// (preset chips or a custom expression), and enable toggle. Posts to
/// `/api/mobile/cron` via the store and dismisses on success.
struct CronJobCreatorView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var prompt = ""
    @State private var schedule = "every 2h"
    @State private var enabled = true
    @State private var creating = false
    @State private var errorMessage: String?

    private let presets: [(label: String, expr: String)] = [
        ("Every 30 min", "every 30m"),
        ("Every 2 hours", "every 2h"),
        ("Daily 09:00", "0 9 * * *"),
        ("Daily 02:00", "0 2 * * *"),
    ]

    var body: some View {
        HermesMobileScreen(title: "New cron job", subtitle: "Runs on the Mac gateway", icon: "plus.clock", showsDone: true) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HermesMobileSection(title: "Details", icon: "text.alignleft", accent: HermesTheme.primary) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("NAME")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(HermesTheme.mutedForeground)
                            TextField("Optional — defaults to the prompt", text: $name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(HermesTheme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(HermesTheme.userBubble, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            Text("PROMPT")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(HermesTheme.mutedForeground)
                            TextEditor(text: $prompt)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(HermesTheme.ink)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .frame(minHeight: 96)
                                .background(HermesTheme.userBubble, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(alignment: .topLeading) {
                                    if prompt.isEmpty {
                                        Text("What should the agent do? Must be self-contained.")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(HermesTheme.mutedForeground.opacity(0.7))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 14)
                                            .allowsHitTesting(false)
                                    }
                                }
                        }
                    }

                    HermesMobileSection(title: "Schedule", icon: "clock", accent: HermesTheme.primary) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                ForEach(presets, id: \.expr) { preset in
                                    Button {
                                        schedule = preset.expr
                                    } label: {
                                        Text(preset.label)
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundStyle(schedule == preset.expr ? HermesTheme.ink : HermesTheme.mutedForeground)
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 7)
                                            .background(
                                                schedule == preset.expr
                                                    ? HermesTheme.primary.opacity(0.22)
                                                    : HermesTheme.userBubble,
                                                in: Capsule()
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 2)

                            Text("CUSTOM EXPRESSION")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(HermesTheme.mutedForeground)
                            TextField("e.g. 0 18 * * 1-5", text: $schedule)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(HermesTheme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(HermesTheme.userBubble, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    HermesMobileSection(title: "Activation", icon: "bolt.fill", accent: enabled ? HermesTheme.green : HermesTheme.mutedForeground) {
                        Toggle(isOn: $enabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(enabled ? "Enabled" : "Paused after creation")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(HermesTheme.ink)
                                Text("Paused jobs stay listed but never fire.")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(HermesTheme.mutedForeground)
                            }
                        }
                        .tint(HermesTheme.green)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(HermesTheme.red)
                            .padding(.horizontal, 4)
                    }

                    Button {
                        create()
                    } label: {
                        HStack(spacing: 8) {
                            if creating {
                                ProgressView().tint(HermesTheme.primaryForeground)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(creating ? "Creating…" : "Create job")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(HermesTheme.primaryForeground)
                        .background(HermesTheme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(creating)
                }
                .padding(.horizontal, 13)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
    }

    private func create() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSchedule = schedule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            errorMessage = "A prompt is required."
            return
        }
        guard !trimmedSchedule.isEmpty else {
            errorMessage = "A schedule expression is required."
            return
        }
        errorMessage = nil
        creating = true
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await store.cronCreate(
                    name: trimmedName.isEmpty ? nil : trimmedName,
                    prompt: trimmedPrompt,
                    schedule: trimmedSchedule,
                    skills: nil,
                    deliver: nil,
                    enabled: enabled
                )
                creating = false
                dismiss()
            } catch {
                creating = false
                errorMessage = "Could not create the job: \(error.localizedDescription)"
            }
        }
    }
}
