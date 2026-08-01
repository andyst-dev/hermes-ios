import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(store.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(20)
                }
                .onChange(of: store.messages) { _, messages in
                    guard let last = messages.last else { return }
                    withAnimation(.snappy) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            ComposerView()
        }
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
                    .font(.body)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                ForEach(message.toolCalls) { tool in
                    ToolCallCard(tool: tool)
                }
            }
            .padding(16)
            .background(background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))
            if message.role != .user { Spacer(minLength: 44) }
        }
    }

    private var background: Color {
        switch message.role {
        case .user: HermesTheme.blue.opacity(0.32)
        case .assistant: HermesTheme.panel
        case .system: HermesTheme.red.opacity(0.18)
        }
    }
}

private struct ToolCallCard: View {
    let tool: HermesToolCall

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.name)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.88))
                Text(tool.summary)
                    .font(.caption)
                    .foregroundStyle(HermesTheme.muted)
                    .lineLimit(2)
                if let command = tool.command {
                    Text(command)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        case .running: HermesTheme.blue
        case .succeeded: HermesTheme.green
        case .failed: HermesTheme.red
        case .waitingApproval: HermesTheme.gold
        }
    }
}

private struct ComposerView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Button {} label: {
                Image(systemName: "plus")
                    .frame(width: 38, height: 38)
                    .background(HermesTheme.panel, in: Circle())
            }
            TextField("Message Hermes", text: $store.composerText, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(HermesTheme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Button {
                Task { await store.sendComposer() }
            } label: {
                Image(systemName: store.isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(store.composerText.isEmpty ? HermesTheme.panel : HermesTheme.gold, in: Circle())
                    .foregroundStyle(store.composerText.isEmpty ? .white : .black)
            }
            .disabled(store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.isStreaming)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
