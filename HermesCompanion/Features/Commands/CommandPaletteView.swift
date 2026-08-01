import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var commands: [MobileCommand] {
        let all = MobileCommand.allCases
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "command")
                        .foregroundStyle(HermesTheme.ring)
                    TextField("Search commands", text: $query)
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(14)
                .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HermesTheme.border, lineWidth: 1))
                .padding(.horizontal)

                List(commands) { command in
                    Button {
                        Task {
                            await store.runCommand(command)
                            dismiss()
                        }
                    } label: {
                        Label(command.title, systemImage: command.icon)
                            .foregroundStyle(HermesTheme.foreground)
                            .font(.system(.body, design: .default).weight(.medium))
                    }
                    .listRowBackground(HermesTheme.card)
                }
                .scrollContentBackground(.hidden)
            }
            .background(HermesTheme.background)
            .navigationTitle("Command Palette")
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}
