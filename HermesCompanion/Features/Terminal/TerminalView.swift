import SwiftUI

struct TerminalView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draftCommand = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TerminalHeader()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(lines) { line in
                                TerminalLineRow(line: line)
                                    .id(line.id)
                            }
                        }
                        .padding(14)
                    }
                    .background(Color.black.opacity(0.36))
                    .onChange(of: lines) { _, latest in
                        guard let last = latest.last else { return }
                        withAnimation(.snappy) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                RemoteCommandBar(text: $draftCommand)
            }
            .background(HermesTheme.background.ignoresSafeArea())
            .navigationTitle("Terminal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var lines: [TerminalLine] {
        store.terminalLines.isEmpty ? TerminalLine.placeholder : store.terminalLines
    }
}

private struct TerminalHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(HermesTheme.red).frame(width: 8, height: 8)
            Circle().fill(HermesTheme.warm).frame(width: 8, height: 8)
            Circle().fill(HermesTheme.green).frame(width: 8, height: 8)
            Text("remote hermes desktop")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(HermesTheme.mutedForeground)
            Spacer()
            Text("read-only")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .textCase(.uppercase)
                .foregroundStyle(HermesTheme.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(HermesTheme.card)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(HermesTheme.stroke), alignment: .bottom)
    }
}

private struct TerminalLineRow: View {
    let line: TerminalLine

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(prefix)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(prefixColor)
                .frame(width: 22, alignment: .trailing)
            Text(line.text)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var prefix: String {
        switch line.kind {
        case .input: ">"
        case .output: "•"
        case .command: "$"
        case .status: "→"
        }
    }

    private var prefixColor: Color {
        switch line.kind {
        case .input: HermesTheme.primary
        case .output: HermesTheme.ink.opacity(0.7)
        case .command: HermesTheme.green
        case .status: HermesTheme.warm
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .command: HermesTheme.green
        case .status: HermesTheme.mutedForeground
        default: HermesTheme.ink
        }
    }
}

private struct RemoteCommandBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Text("$")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(HermesTheme.green)
            TextField("Remote command prompt coming with streaming bridge", text: $text)
                .font(.system(size: 12, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(true)
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(HermesTheme.mutedForeground)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(HermesTheme.card)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(HermesTheme.stroke), alignment: .top)
    }
}

extension TerminalLine {
    static let placeholder: [TerminalLine] = [
        TerminalLine(kind: .status, text: "Hermes Desktop terminal mirror ready."),
        TerminalLine(kind: .output, text: "Tool calls and remote command output from the selected conversation appear here."),
        TerminalLine(kind: .status, text: "Direct iPhone shell execution stays locked; Hermes runs commands on the paired desktop.")
    ]
}
