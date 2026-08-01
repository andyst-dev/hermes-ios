import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showingCommands: Bool
    @Binding var showingInspector: Bool
    @Binding var showingModels: Bool
    @Binding var showingTerminal: Bool

    var body: some View {
        VStack(spacing: 0) {
            CompactChatControls(showingCommands: $showingCommands, showingInspector: $showingInspector, showingModels: $showingModels, showingTerminal: $showingTerminal)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                        ForEach(ChatTurn.build(from: store.messages)) { turn in
                            Section {
                                ForEach(turn.responses) { message in
                                    ResponseBlock(message: message)
                                        .id(message.id)
                                }
                            } header: {
                                if let userMessage = turn.userMessage {
                                    StickyUserPrompt(message: userMessage)
                                        .id(userMessage.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
                .onChange(of: store.messages) { _, messages in
                    guard let last = messages.last else { return }
                    withAnimation(.snappy) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            ComposerView()
        }
        .background(HermesTheme.background.opacity(0.72))
    }
}

private struct CompactChatControls: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showingCommands: Bool
    @Binding var showingInspector: Bool
    @Binding var showingModels: Bool
    @Binding var showingTerminal: Bool

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            compactButton("command") { showingCommands = true }
                .accessibilityLabel("Commands")
            compactButton("cpu") { showingModels = true }
                .accessibilityLabel("Change model")
            compactButton("terminal") { showingTerminal = true }
                .accessibilityLabel("Terminal")
            compactButton("sidebar.right") { showingInspector = true }
                .accessibilityLabel("Desktop state")
            if store.isStreaming {
                compactButton("stop.fill", role: .destructive) { Task { await store.stop() } }
                    .accessibilityLabel("Stop")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(HermesTheme.background.opacity(0.72))
    }

    private func compactButton(_ systemName: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(HermesTheme.primary)
    }
}

private struct ChatTurn: Identifiable {
    let id: String
    var userMessage: HermesMessage?
    var responses: [HermesMessage]

    static func build(from messages: [HermesMessage]) -> [ChatTurn] {
        var turns: [ChatTurn] = []
        var current = ChatTurn(id: "intro", userMessage: nil, responses: [])

        for message in messages {
            if message.role == .user {
                if current.userMessage != nil || !current.responses.isEmpty { turns.append(current) }
                current = ChatTurn(id: message.id, userMessage: message, responses: [])
            } else {
                current.responses.append(message)
            }
        }

        if current.userMessage != nil || !current.responses.isEmpty { turns.append(current) }
        return turns
    }
}

private struct StickyUserPrompt: View {
    let message: HermesMessage

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(message.text)
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundStyle(HermesTheme.ink)
                    .textSelection(.enabled)
                    .lineLimit(4)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(HermesTheme.userBubble, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(HermesTheme.userBubbleBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 9)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(
            LinearGradient(colors: [HermesTheme.background.opacity(0.98), HermesTheme.background.opacity(0.82)], startPoint: .top, endPoint: .bottom)
        )
    }
}

private struct ResponseBlock: View {
    let message: HermesMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .lineSpacing(4)
                    .foregroundStyle(textColor)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(message.toolCalls) { tool in
                ToolCallCard(tool: tool)
            }
        }
        .padding(.bottom, 12)
    }

    private var textColor: Color {
        message.role == .system ? HermesTheme.red : HermesTheme.ink
    }
}

private struct ToolCallCard: View {
    let tool: HermesToolCall

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.name)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(HermesTheme.ink.opacity(0.84))
                Text(tool.summary)
                    .font(.caption)
                    .foregroundStyle(HermesTheme.mutedForeground)
                    .lineLimit(2)
                if let command = tool.command {
                    Text(command)
                        .font(HermesTheme.mono)
                        .foregroundStyle(HermesTheme.ink.opacity(0.66))
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(11)
        .background(HermesTheme.muted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))
    }

    private var icon: String {
        switch tool.status {
        case .queued: "clock"
        case .running: "terminal"
        case .succeeded: "checkmark"
        case .failed: "xmark"
        case .waitingApproval: "hand.raised.fill"
        }
    }

    private var color: Color {
        switch tool.status {
        case .queued: HermesTheme.muted
        case .running: HermesTheme.primary
        case .succeeded: HermesTheme.green
        case .failed: HermesTheme.red
        case .waitingApproval: HermesTheme.warm
        }
    }
}

private struct ComposerView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {} label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(HermesTheme.primary)

            TextField("Ask Hermes…", text: $store.composerText, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 14, design: .default))
                .foregroundStyle(HermesTheme.ink)
                .textInputAutocapitalization(.sentences)
                .frame(minHeight: 28, alignment: .center)

            Button {
                Task { await store.sendComposer() }
            } label: {
                Image(systemName: store.isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(sendForeground)
            }
            .buttonStyle(.plain)
            .disabled(store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.isStreaming)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var sendForeground: Color {
        store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? HermesTheme.foreground : HermesTheme.primaryForeground
    }
}
