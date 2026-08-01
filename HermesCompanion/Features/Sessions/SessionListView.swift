import SwiftUI

struct SessionListView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showingSettings: Bool

    var body: some View {
        List(selection: $store.selectedSessionID) {
            Section {
                ForEach(store.sessions) { session in
                    Button {
                        Task { await store.select(session: session) }
                    } label: {
                        SessionRow(session: session, selected: session.id == store.selectedSessionID)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            } header: {
                ConnectionHeader(showingSettings: $showingSettings)
                    .textCase(nil)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
    }
}

private struct ConnectionHeader: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showingSettings: Bool

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(color: HermesTheme.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HermesTheme.ink)
                if case .connected(let host) = store.connection {
                    Text("\(host.name) · \(host.profile)")
                        .font(.caption)
                        .foregroundStyle(HermesTheme.mutedForeground)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

private struct SessionRow: View {
    let session: HermesSession
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(statusColor.opacity(0.18))
                .frame(width: 36, height: 36)
                .overlay(StatusDot(color: statusColor))
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HermesTheme.ink)
                    .lineLimit(1)
                Text(session.subtitle)
                    .font(.caption)
                    .foregroundStyle(HermesTheme.mutedForeground)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(selected ? HermesTheme.elevated : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statusColor: Color {
        switch session.status {
        case .idle: HermesTheme.muted
        case .running: HermesTheme.primary
        case .waitingApproval: HermesTheme.warm
        case .failed: HermesTheme.red
        case .completed: HermesTheme.green
        }
    }
}
