import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Scroll geometry snapshot used to detect the user leaving the bottom while
/// a turn streams (offset decreasing) vs. content simply growing.
private struct ScrollState: Equatable {
    var offset: CGFloat
    var nearBottom: Bool
}

struct ChatView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore
    @Binding var showingInspector: Bool
    @Binding var showingModels: Bool
    var onBack: (() -> Void)? = nil
    @State private var userScrolledUp = false

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
                .onScrollGeometryChange(for: ScrollState.self) { geometry in
                    let maxOffset = geometry.contentSize.height - geometry.containerSize.height
                    let nearBottom = maxOffset <= 0 || geometry.contentOffset.y >= maxOffset - 30
                    return ScrollState(offset: geometry.contentOffset.y, nearBottom: nearBottom)
                } action: { old, new in
                    // Only an active scroll UP (offset decreasing) means the
                    // user left the bottom. Content growth while pinned keeps
                    // the offset the same, so it never looks like a scroll-up.
                    if new.offset < old.offset - 8 {
                        userScrolledUp = true
                    } else if new.nearBottom {
                        userScrolledUp = false
                    }
                }
                .onAppear {
                    userScrolledUp = false
                    scrollToBottom(proxy)
                }
                .onChange(of: store.selectedSessionID) { _, _ in
                    // Open a conversation already at the end: jump straight
                    // to the latest message, no animated scroll.
                    userScrolledUp = false
                    scrollToBottom(proxy)
                }
                .onChange(of: store.messages) { _, messages in
                    guard !messages.isEmpty else { return }
                    // Follow the stream, but respect the user reading higher
                    // up: once they scroll up, stop pulling to the bottom
                    // until they scroll back down.
                    guard !userScrolledUp else { return }
                    scrollToBottom(proxy)
                }
            }
            if let approval = store.pendingApproval {
                ApprovalCard(request: approval)
            }
            ComposerView()
        }
        .background(HermesTheme.background.ignoresSafeArea())
        .sheet(isPresented: $showingInspector) {
            HermesMobileScreen(title: "Inspector", subtitle: "this conversation", icon: "sidebar.right", showsDone: true) {
                InspectorView().environmentObject(store)
            }
        }
        .sheet(isPresented: $showingModels) {
            ModelPickerView().environmentObject(store)
        }
        .onAppear {
            store.startLiveDraftPolling()
        }
        .onDisappear {
            store.stopLiveDraftPolling()
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo("chat-bottom", anchor: .bottom)
        }
    }
}

private struct CompactChatControls: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore
    @Binding var showingInspector: Bool
    @Binding var showingModels: Bool
    var onBack: (() -> Void)? = nil
    @State private var shareURL: URL?

    var body: some View {
        HStack(spacing: 8) {
            if let onBack {
                compactButton("xmark", action: onBack)
                    .accessibilityLabel("Close chat")
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
            if let shareURL {
                ShareLink(item: shareURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(HermesTheme.primary)
                .accessibilityLabel("Export conversation")
            }
            if store.isStreaming {
                compactButton("stop.fill", role: .destructive) { Task { await store.stop() } }
                    .accessibilityLabel("Stop")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(HermesTheme.background.ignoresSafeArea())
        .onAppear { refreshShareURL() }
        .onChange(of: store.messages) { refreshShareURL() }
        .onChange(of: store.selectedSessionID) { refreshShareURL() }
    }

    private func refreshShareURL() {
        shareURL = store.exportMarkdownFileURL()
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
    @ObservedObject private var theme = ThemeManager.shared
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
    @ObservedObject private var theme = ThemeManager.shared
    let message: HermesMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let thinking = message.thinking, !thinking.isEmpty {
                ThinkingBlock(text: thinking)
            }
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

/// Collapsible reasoning block. The thinking streams here, separate from the
/// answer, so the reply stays concise - expand to read it, like on Desktop.
private struct ThinkingBlock: View {
    @ObservedObject private var theme = ThemeManager.shared
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11, weight: .medium))
                    Text("Thinking")
                        .font(.system(size: 12, weight: .semibold))
                        .textCase(.uppercase)
                        .kerning(0.8)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(HermesTheme.mutedForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(HermesTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if expanded {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(HermesTheme.mutedForeground)
                    .lineSpacing(3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HermesTheme.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(HermesTheme.border.opacity(0.6), lineWidth: 1)
                    )
            }
        }
    }
}

private struct MarkdownMessageText: View {
    @ObservedObject private var theme = ThemeManager.shared
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
                case .table(let header, let rows):
                    TableView(header: header, rows: rows)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Renders a GFM markdown table as a bordered grid (header + rows), matching
/// the Desktop chat's table look.
private struct TableView: View {
    @ObservedObject private var theme = ThemeManager.shared
    let header: [String]
    let rows: [[String]]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(header.indices, id: \.self) { c in
                    Text(header[c])
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(HermesTheme.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(HermesTheme.card.opacity(0.85))
            Divider().overlay(HermesTheme.border.opacity(0.8))

            ForEach(rows.indices, id: \.self) { r in
                let row = rows[r]
                HStack(spacing: 10) {
                    ForEach(header.indices, id: \.self) { c in
                        Text(row.count > c ? row[c] : "")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(HermesTheme.ink.opacity(0.85))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                if r < rows.count - 1 {
                    Divider().overlay(HermesTheme.border.opacity(0.5))
                }
            }
        }
        .background(HermesTheme.card.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))
    }
}

private struct MarkdownBlock: Identifiable {
    enum Kind {
        case prose(String)
        case code(String)
        case table(header: [String], rows: [[String]])
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

        let lines = raw.components(separatedBy: .newlines)
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if insideCode {
                    flushCode()
                    insideCode = false
                } else {
                    flushProse()
                    insideCode = true
                }
                i += 1
                continue
            }
            if insideCode {
                code.append(line)
                i += 1
                continue
            }
            if trimmed.hasPrefix("|") {
                flushProse()
                if let (block, consumed) = parseTable(lines, from: i) {
                    blocks.append(block)
                    i += consumed
                    continue
                }
                prose.append(line)
                i += 1
                continue
            }
            prose.append(line)
            i += 1
        }

        if insideCode { flushCode() }
        flushProse()
        if blocks.isEmpty { return [MarkdownBlock(kind: .prose(raw))] }
        return blocks
    }

    /// Parse a GFM-style table starting at `lines[start]` (a `|`-prefixed
    /// header line), with the second line being the `| --- | --- |` separator.
    /// Returns the table block and how many lines it consumed.
    static func parseTable(_ lines: [String], from start: Int) -> (MarkdownBlock, Int)? {
        func cells(_ line: String) -> [String] {
            var parts = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.first?.isEmpty == true { parts.removeFirst() }
            if parts.last?.isEmpty == true { parts.removeLast() }
            return parts
        }
        let header = cells(lines[start])
        guard header.count >= 2, start + 1 < lines.count else { return nil }
        let sep = lines[start + 1].trimmingCharacters(in: .whitespaces)
        guard sep.hasPrefix("|"), sep.dropFirst().contains("-") else { return nil }
        var rows: [[String]] = []
        var consumed = 2
        var j = start + 2
        while j < lines.count {
            let t = lines[j].trimmingCharacters(in: .whitespaces)
            if !t.hasPrefix("|") { break }
            rows.append(cells(lines[j]))
            j += 1
            consumed += 1
        }
        return (MarkdownBlock(kind: .table(header: header, rows: rows)), consumed)
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

private struct HermesTodoItem {
    var content: String
    var status: TodoStatus
}

private enum TodoStatus: String {
    case pending
    case in_progress
    case completed
    case cancelled
}

/// Parse the todo items out of a `todo` tool call's JSON command (the args
/// carry `{"todos": [{content, id, status}], ...}`). Mirrors the Desktop's
/// parseTodos.
private func parseTodos(from command: String) -> [HermesTodoItem]? {
    guard let data = command.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
    let raw: Any?
    if let arr = obj as? [Any] {
        raw = arr
    } else if let dict = obj as? [String: Any] {
        raw = dict["todos"]
    } else {
        raw = nil
    }
    guard let arr = raw as? [[String: Any]] else { return nil }
    var items: [HermesTodoItem] = []
    for item in arr {
        guard let content = item["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let statusRaw = item["status"] as? String,
              let status = TodoStatus(rawValue: statusRaw) else { continue }
        items.append(HermesTodoItem(content: content, status: status))
    }
    return items.isEmpty ? nil : items
}

/// Collapsible "Tasks N/M" checklist for the agent's `todo` tool, matching the
/// Desktop status stack (✓ done / … in progress / ○ pending / ✕ cancelled).
private struct TodoChecklistView: View {
    @ObservedObject private var theme = ThemeManager.shared
    let items: [HermesTodoItem]
    @State private var expanded = true

    private var doneCount: Int { items.filter { $0.status == .completed }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: "checklist")
                        .font(.system(size: 11, weight: .medium))
                    Text("Tasks \(doneCount)/\(items.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .textCase(.uppercase)
                        .kerning(0.6)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(HermesTheme.mutedForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(HermesTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            statusGlyph(item.status)
                            Text(item.content)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(textColor(item.status))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HermesTheme.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(HermesTheme.border.opacity(0.6), lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private func statusGlyph(_ status: TodoStatus) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(HermesTheme.green)
        case .in_progress:
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(HermesTheme.warm)
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.7))
        case .cancelled:
            Image(systemName: "xmark.circle")
                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.6))
        }
    }

    private func textColor(_ status: TodoStatus) -> Color {
        switch status {
        case .cancelled: HermesTheme.mutedForeground.opacity(0.6)
        default: HermesTheme.ink.opacity(0.88)
        }
    }
}

private struct ToolCallCard: View {
    @ObservedObject private var theme = ThemeManager.shared
    let tool: HermesToolCall

    var body: some View {
        if let todos = todoItems {
            TodoChecklistView(items: todos)
        } else {
            defaultRow
        }
    }

    private var todoItems: [HermesTodoItem]? {
        guard tool.name.lowercased() == "todo" else { return nil }
        return parseTodos(from: tool.command ?? "")
    }

    private var defaultRow: some View {
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
                if !tool.summary.isEmpty,
                   tool.summary.caseInsensitiveCompare(tool.name) != .orderedSame,
                   tool.summary.caseInsensitiveCompare("tool") != .orderedSame {
                    Text(tool.summary)
                        .font(.caption)
                        .foregroundStyle(HermesTheme.mutedForeground)
                        .lineLimit(2)
                }
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
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore
    @StateObject private var voice = VoiceTranscriber()
    @State private var showingPhotoPicker = false
    @State private var showingDesktopFiles = false
    @State private var showingFilesImporter = false
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: 6) {
            if !store.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.pendingAttachments) { attachment in
                            HStack(spacing: 6) {
                                Image(systemName: (attachment.mimeType ?? "").hasPrefix("image/") ? "photo" : "doc")
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
                    Button {
                        showingFilesImporter = true
                    } label: {
                        Label("Choose from Files", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(HermesTheme.sendReady)
                .accessibilityLabel("Add attachment")

                TextField("Ask Hermes…", text: $store.composerText, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.system(size: 14, design: .default))
                    .foregroundStyle(HermesTheme.ink)
                    .textInputAutocapitalization(.sentences)
                    .frame(minHeight: 28, alignment: .center)

                Button {
                    if voice.isRecording {
                        voice.stop()
                    } else {
                        voice.start { text in
                            if store.composerText.isEmpty {
                                store.composerText = text
                            } else {
                                store.composerText += " " + text
                            }
                        }
                    }
                } label: {
                    Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(voice.isRecording ? HermesTheme.red : HermesTheme.sendReady)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voice input")

                Button {
                    Task { await store.sendComposer() }
                } label: {
                    Image(systemName: store.isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(sendForeground)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer.send")
                .accessibilityLabel(store.isStreaming ? "Stop" : "Send")
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
        .fileImporter(isPresented: $showingFilesImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task {
                for url in urls {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
                    let id = UUID()
                    let filename = url.lastPathComponent.isEmpty ? "file-\(id.uuidString.prefix(8))" : url.lastPathComponent
                    let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
                    try? data.write(to: fileURL)
                    let mime = UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    store.addPendingAttachment(OutboundPrompt.Attachment(id: id, filename: filename, mimeType: mime, sizeBytes: data.count))
                }
            }
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
        let canSend = !store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.pendingAttachments.isEmpty
        if store.isStreaming { return HermesTheme.sendReady }
        // Empty → deep brown (clearly idle); ready to send → warm cream,
        // deliberately darker than the near-white foreground.
        return canSend ? HermesTheme.sendReady : HermesTheme.sendIdle
    }
}

/// Dangerous-command approval surfaced by the Desktop during a streaming
/// turn. The turn is blocked until the phone answers.
private struct ApprovalCard: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore
    let request: ApprovalRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HermesTheme.destructive)
                Text("Approbation requise")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(HermesTheme.foreground)
            }
            if !request.description.isEmpty {
                Text(request.description)
                    .font(.system(size: 12))
                    .foregroundStyle(HermesTheme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(request.command)
                .font(HermesTheme.mono)
                .foregroundStyle(HermesTheme.foreground)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HermesTheme.popover, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(HermesTheme.destructive.opacity(0.55), lineWidth: 1)
                )
            HStack(spacing: 8) {
                Button {
                    store.respond(toApproval: request, verdict: "once")
                } label: {
                    Text("Approuver une fois")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(HermesTheme.primaryForeground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(HermesTheme.primary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                Button {
                    store.respond(toApproval: request, verdict: "deny")
                } label: {
                    Text("Refuser")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(HermesTheme.destructive)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(HermesTheme.popover, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(HermesTheme.destructive.opacity(0.6), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(14)
        .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HermesTheme.destructive.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 12)
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }
}
