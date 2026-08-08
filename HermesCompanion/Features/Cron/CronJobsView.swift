import SwiftUI

/// Gateway scheduled jobs: list, pause/resume, run now, remove, and per-job
/// execution history. Data comes from the plugin backend's cron routes
/// (`/api/mobile/cron`); when the backend does not ship them (standalone
/// bridge), the store flags `cronUnavailable` and the view explains.
struct CronJobsView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore
    @State private var expandedJobID: String?
    @State private var jobToRemove: HermesCronJob?
    @State private var executions: [String: [HermesCronExecution]] = [:]
    @State private var loaded = false
    @State private var showingCreator = false

    var body: some View {
        HermesMobileScreen(title: "Cron jobs", subtitle: subtitle, icon: "clock.badge.checkmark", showsDone: true, onAdd: {
            showingCreator = true
        }) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if store.cronUnavailable && !loaded {
                        unavailableCard
                    } else if store.cronJobs.isEmpty {
                        emptyCard
                    } else {
                        ForEach(store.cronJobs) { job in
                            jobCard(job)
                        }
                        .animation(.snappy, value: store.cronJobs.map(\.id))
                    }
                }
                .padding(.horizontal, 13)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .refreshable {
                await store.refreshCron()
            }
        }
        .sheet(isPresented: $showingCreator) {
            CronJobCreatorView().environmentObject(store)
        }
        .alert("Remove cron job?", isPresented: Binding(
            get: { jobToRemove != nil },
            set: { if !$0 { jobToRemove = nil } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                if let job = jobToRemove {
                    Task { await store.cronRemove(jobID: job.id) }
                }
            }
        } message: {
            Text("This removes the job from the gateway. Its past output stays on the Mac.")
        }
        .task {
            guard !loaded else { return }
            await store.refreshCron()
            loaded = true
        }
    }

    private var subtitle: String {
        if store.cronUnavailable { return "Available on the desktop plugin backend" }
        let count = store.cronJobs.count
        return count == 1 ? "1 scheduled job" : "\(count) scheduled jobs"
    }

    private var unavailableCard: some View {
        HermesMobileSection(title: "Cron unavailable", icon: "exclamationmark.triangle", accent: HermesTheme.warm) {
            Text("This backend does not expose cron routes. Connect to the Hermes desktop plugin backend (dashboard or remote tunnel) to manage scheduled jobs from the phone.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(HermesTheme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyCard: some View {
        HermesMobileSection(title: "No jobs", icon: "clock", accent: HermesTheme.mutedForeground) {
            Text("No cron jobs yet. Create one on the Mac with `hermes cron create`, then refresh here.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(HermesTheme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func jobCard(_ job: HermesCronJob) -> some View {
        let expanded = expandedJobID == job.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    expandedJobID = expanded ? nil : job.id
                    if !expanded { loadExecutions(job.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: job.isPaused ? "pause.circle" : "clock.badge.checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(jobAccent(job))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(job.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(HermesTheme.ink)
                            .lineLimit(1)
                        Text(job.scheduleDisplay)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(HermesTheme.mutedForeground)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(job.stateLabel.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(jobAccent(job))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(jobAccent(job).opacity(0.13), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(HermesTheme.mutedForeground.opacity(0.5))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider().overlay(HermesTheme.border.opacity(0.5))

                    if !job.prompt.isEmpty {
                        Text(job.prompt)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(HermesTheme.ink.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    infoRow("Next run", job.nextRunAt.map(shortDate) ?? "—")
                    infoRow("Last run", job.lastRunAt.map(shortDate) ?? "Never")
                    if !job.deliver.isEmpty {
                        infoRow("Deliver", job.deliver)
                    }
                    if !job.skills.isEmpty {
                        infoRow("Skills", job.skills.joined(separator: ", "))
                    }

                    if let executions = executions[job.id], !executions.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("RECENT RUNS")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1.6)
                                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.8))
                            ForEach(executions) { execution in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(executionColor(execution.status))
                                        .frame(width: 6, height: 6)
                                    Text(execution.statusLabel)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(executionColor(execution.status))
                                    Spacer()
                                    Text(execution.startedAt.map(shortDateTime) ?? "—")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(HermesTheme.mutedForeground.opacity(0.8))
                                }
                                if let summary = execution.summary, !summary.isEmpty {
                                    Text(summary)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(HermesTheme.mutedForeground.opacity(0.75))
                                        .padding(.leading, 14)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }

                    HStack(spacing: 8) {
                        actionButton(job.isPaused ? "Resume" : "Pause", icon: job.isPaused ? "play.circle" : "pause.circle", accent: job.isPaused ? HermesTheme.green : HermesTheme.warm) {
                            Task { job.isPaused ? await store.cronResume(jobID: job.id) : await store.cronPause(jobID: job.id) }
                        }
                        actionButton("Run now", icon: "bolt.fill", accent: HermesTheme.primary) {
                            Task { await store.cronRun(jobID: job.id) }
                        }
                        Spacer()
                        Button {
                            jobToRemove = job
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(HermesTheme.destructive)
                                .frame(width: 30, height: 28)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 11)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(HermesTheme.card.opacity(0.32), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(HermesTheme.border.opacity(0.7), lineWidth: 1))
    }

    private func actionButton(_ title: String, icon: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.7))
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(HermesTheme.ink.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func jobAccent(_ job: HermesCronJob) -> Color {
        switch job.state {
        case "running": HermesTheme.primary
        case "paused": HermesTheme.warm
        case "failed": HermesTheme.destructive
        case "completed": HermesTheme.green
        default: HermesTheme.green
        }
    }

    private func executionColor(_ status: String) -> Color {
        switch status {
        case "running": HermesTheme.primary
        case "failed": HermesTheme.destructive
        case "completed", "succeeded": HermesTheme.green
        default: HermesTheme.mutedForeground
        }
    }

    private func loadExecutions(_ jobID: String) {
        Task {
            do {
                let rows = try await store.cronExecutions(jobID: jobID)
                await MainActor.run { executions[jobID] = rows }
            } catch {}
        }
    }

    private func shortDate(_ iso: String) -> String {
        iso
    }

    private func shortDateTime(_ iso: String) -> String {
        iso
    }
}
