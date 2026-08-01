import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(store.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(18)
                }
                .onChange(of: store.messages) { _, messages in
                    guard let last = messages.last else { return }
                    withAnimation(.snappy) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            ComposerView()
        }
        .background(HermesTheme.background.opacity(0.72))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if store.isStreaming {
                    Button(role: .destructive) { Task { await store.stop() } } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                }
            }
        }
    }
}

private struct MessageBubble: View {
    let message: HermesMessage

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 44) }
            VStack(alignment: .leading, spacing: 10) {
                Text(message.text)
                    .font(.system(.body, design: .default))
                    .foregroundStyle(textColor)
                    .textSelection(.enabled)
                ForEach(message.toolCalls) { tool in
                    ToolCallCard(tool: tool)
                }
            }
            .padding(15)
            .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(border, lineWidth: 1))
            .shadow(color: .black.opacity(message.role == .assistant ? 0.05 : 0.0), radius: 12, x: 0, y: 8)
            if message.role != .user { Spacer(minLength: 44) }
        }
    }

    private var background: Color {
        switch message.role {
        case .user: HermesTheme.userBubble
        case .assistant: HermesTheme.card
        case .system: HermesTheme.red.opacity(0.08)
        }
    }

    private var border: Color {
        switch message.role {
        case .user: HermesTheme.userBubbleBorder
        case .assistant: HermesTheme.stroke
        case .system: HermesTheme.red.opacity(0.16)
        }
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
        HStack(alignment: .bottom, spacing: 10) {
            Button {} label: {
                Image(systemName: "plus")
                    .frame(width: 36, height: 36)
                    .background(HermesTheme.secondary, in: Circle())
                    .overlay(Circle().stroke(HermesTheme.stroke, lineWidth: 1))
            }
            TextField("Message Hermes", text: $store.composerText, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(.body, design: .default))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))
            Button {
                Task { await store.sendComposer() }
            } label: {
                Image(systemName: store.isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(store.composerText.isEmpty ? HermesTheme.secondary : HermesTheme.primary, in: Circle())
                    .foregroundStyle(store.composerText.isEmpty ? HermesTheme.foreground : HermesTheme.primaryForeground)
            }
            .disabled(store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.isStreaming)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}
