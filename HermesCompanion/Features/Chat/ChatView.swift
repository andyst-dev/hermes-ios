import PhotosUI
import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showingInspector: Bool
    @Binding var showingModels: Bool
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            CompactChatControls(showingInspector: $showingInspector, showingModels: $showingModels, onBack: onBack)
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
                        Color.clear
                            .frame(height: 1)
                            .id("chat-bottom")
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
                .onAppear {
                    scrollToBottom(proxy)
                }
                .onChange(of: store.selectedSessionID) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: store.messages) { _, messages in
                    guard !messages.isEmpty else { return }
                    scrollToBottom(proxy)
                }
            }
            ComposerView()
        }
        .background(HermesTheme.background.opacity(0.72))
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.snappy) { proxy.scrollTo("chat-bottom", anchor: .bottom) }
        }
    }
}

private struct CompactChatControls: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showingInspector: Bool
    @Binding var showingModels: Bool
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let onBack {
                compactButton("chevron.left", action: onBack)
                    .accessibilityLabel("Back to chats")
                Text(store.selectedSession?.title ?? "New Session")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HermesTheme.mutedForeground)
                    .lineLimit(1)
            }
            Spacer()
            compactButton("cpu") { showingModels = true }
                .accessibilityLabel("Change model")
            compactButton("sidebar.right") { showingInspector = true }
                .accessibilityLabel("Conversation info")
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
                MarkdownMessageText(message.text, baseSize: 14, lineLimit: 4)
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
                MarkdownMessageText(message.text, baseSize: 15, textColor: textColor)
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

private struct MarkdownMessageText: View {
    private let blocks: [MarkdownBlock]
    private let baseSize: CGFloat
    private let textColor: Color
    private let lineLimit: Int?

    init(_ text: String, baseSize: CGFloat, textColor: Color = HermesTheme.ink, lineLimit: Int? = nil) {
        self.blocks = MarkdownBlock.parse(text)
        self.baseSize = baseSize
        self.textColor = textColor
        self.lineLimit = lineLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(blocks) { block in
                switch block.kind {
                case .prose(let text):
                    Text(markdown: text)
                        .font(.system(size: baseSize, weight: .regular, design: .default))
                        .lineSpacing(4)
                        .foregroundStyle(textColor)
                        .textSelection(.enabled)
                        .lineLimit(lineLimit)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let text):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(text)
                            .font(.system(size: max(baseSize - 1, 12), weight: .regular, design: .monospaced))
                            .foregroundStyle(HermesTheme.ink)
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                    }
                    .background(HermesTheme.card.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownBlock: Identifiable {
    enum Kind {
        case prose(String)
        case code(String)
    }

    let id = UUID()
    let kind: Kind

    static func parse(_ raw: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var prose: [String] = []
        var code: [String] = []
        var insideCode = false

        func flushProse() {
            let text = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(MarkdownBlock(kind: .prose(text))) }
            prose.removeAll()
        }

        func flushCode() {
            let text = code.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !text.isEmpty { blocks.append(MarkdownBlock(kind: .code(text))) }
            code.removeAll()
        }

        for line in raw.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if insideCode {
                    flushCode()
                    insideCode = false
                } else {
                    flushProse()
                    insideCode = true
                }
            } else if insideCode {
                code.append(line)
            } else {
                prose.append(line)
            }
        }

        if insideCode { flushCode() }
        flushProse()
        if blocks.isEmpty { return [MarkdownBlock(kind: .prose(raw))] }
        return blocks
    }
}

private extension Text {
    init(markdown raw: String) {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            self.init(attributed)
        } else {
            self.init(raw)
        }
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
    @State private var showingPhotoPicker = false
    @State private var showingDesktopFiles = false
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: 6) {
            if !store.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.pendingAttachments) { attachment in
                            HStack(spacing: 6) {
                                Image(systemName: "photo")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(HermesTheme.primary)
                                Text(attachment.filename)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(HermesTheme.ink)
                                    .lineLimit(1)
                                Button {
                                    store.removePendingAttachment(id: attachment.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(HermesTheme.mutedForeground)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(HermesTheme.userBubble, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(HermesTheme.userBubbleBorder, lineWidth: 1))
                        }
                    }
                }
            }

            HStack(alignment: .center, spacing: 8) {
                Menu {
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        Label("Choose photos", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showingDesktopFiles = true
                    } label: {
                        Label("Choose from Desktop", systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(HermesTheme.primary)
                .accessibilityLabel("Add attachment")

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
                .disabled(store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.pendingAttachments.isEmpty && !store.isStreaming)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .photosPicker(isPresented: $showingPhotoPicker, selection: $pickerItems, maxSelectionCount: 3, matching: .images)
        .sheet(isPresented: $showingDesktopFiles) {
            DesktopFilePickerView()
                .environmentObject(store)
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else { continue }
                    let id = UUID()
                    let filename = "photo-\(id.uuidString.prefix(8)).jpg"
                    let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
                    try? data.write(to: fileURL)
                    store.addPendingAttachment(OutboundPrompt.Attachment(id: id, filename: filename, mimeType: "image/jpeg", sizeBytes: data.count))
                }
                pickerItems = []
            }
        }
    }

    private var sendForeground: Color {
        store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.pendingAttachments.isEmpty ? HermesTheme.foreground : HermesTheme.primaryForeground
    }
}
