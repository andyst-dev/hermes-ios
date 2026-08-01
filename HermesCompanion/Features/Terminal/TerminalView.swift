import SwiftUI

struct TerminalView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draftCommand = ""

    var body: some View {
        HermesMobileScreen(title: "Terminal", subtitle: terminalSubtitle, icon: "terminal", showsDone: true) {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            HermesMobileSection(title: "Remote log", icon: "waveform.path.ecg", accent: HermesTheme.green) {
                                LazyVStack(alignment: .leading, spacing: 5) {
                                    ForEach(lines) { line in
                                        TerminalLineRow(line: line)
                                            .id(line.id)
                                    }
                                }
                                .padding(.vertical, 2)
                            }

                            HermesMobileSection(title: "Command bridge", icon: "lock", accent: HermesTheme.warm) {
                                RemoteCommandBar(text: $draftCommand)
                            }
                        }
                        .padding(.horizontal, 13)
                        .padding(.top, 10)
                        .padding(.bottom, 24)
                    }
                    .onChange(of: lines) { _, latest in
                        guard let last = latest.last else { return }
                        withAnimation(.snappy) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var terminalSubtitle: String { "remote desktop · read-only" }

    private var lines: [TerminalLine] {
        store.terminalLines.isEmpty ? TerminalLine.placeholder : store.terminalLines
    }
}

private struct TerminalLineRow: View {
    let line: TerminalLine

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(prefix)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(prefixColor)
                .frame(width: 18, alignment: .trailing)
            Text(line.text)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(line.kind == .input ? HermesTheme.userBubble : Color.clear, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
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
            TextField("Remote command bridge locked", text: $text)
                .font(.system(size: 12, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(true)
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(HermesTheme.mutedForeground)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(HermesTheme.background.opacity(0.34), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension TerminalLine {
    static let placeholder: [TerminalLine] = [
        TerminalLine(kind: .status, text: "Hermes Desktop terminal mirror ready."),
        TerminalLine(kind: .output, text: "Tool calls and remote command output from the selected conversation appear here."),
        TerminalLine(kind: .status, text: "Direct iPhone shell execution stays locked; Hermes runs commands on the paired desktop.")
    ]
}
