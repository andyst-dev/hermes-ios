import Foundation

enum HermesConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(HermesHost)
    case failed(String)
}

struct HermesHost: Codable, Equatable, Identifiable {
    var id: String { baseURL.absoluteString }
    let name: String
    let baseURL: URL
    let profile: String
}

/// Parsed `hermes doctor` report: raw CLI output plus the ⚠/✗ issues
/// the plugin extracted, each with a fix suggestion.
struct HermesDoctorIssue: Decodable, Equatable {
    let problem: String
    let solution: String
}

struct HermesDoctorReport: Decodable, Equatable {
    let ok: Bool
    let output: String
    let issues: [HermesDoctorIssue]
}

/// `hermes update --check` result: whether an update is available and
/// what it brings (incoming commit highlights + full changelog).
struct HermesUpdateStatus: Decodable, Equatable {
    let ok: Bool
    let updateAvailable: Bool
    let highlights: [String]
    let fullChangelog: String
    let output: String
}

/// Aggregated desktop usage: totals, per-model breakdown and the last
/// 14 days of activity (from the local state DB).
struct HermesStatsReport: Decodable, Equatable {
    let ok: Bool
    let total: HermesStatsTotal
    let byModel: [HermesModelStat]
    let byProvider: [HermesProviderStat]
    let daily: [HermesDailyStat]
}

struct HermesStatsTotal: Decodable, Equatable {
    let sessions: Int
    let messages: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let reasoningTokens: Int
    let estimatedCostUsd: Double
    let actualCostUsd: Double

    /// Billed usage (input + output). Cache reads are excluded: they are
    /// far cheaper and would dwarf the visual bars.
    var totalTokens: Int { inputTokens + outputTokens }
}

struct HermesModelStat: Decodable, Equatable, Identifiable {
    var id: String { model }
    let model: String
    let sessions: Int
    let messages: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let reasoningTokens: Int
    let estimatedCostUsd: Double
    let actualCostUsd: Double
    /// Desktop billing state for these sessions: "estimated" (pay-per-token),
    /// "included" (subscription), or "" when untracked (tokens not recorded).
    let costStatus: String
    /// Sessions whose token usage was never recorded by the desktop (their
    /// real cost is missing from the estimate).
    let untrackedSessions: Int

    /// Billed usage (input + output). Cache reads are excluded: they are
    /// far cheaper and would dwarf the visual bars.
    var totalTokens: Int { inputTokens + outputTokens }

    var isSubscriptionIncluded: Bool { costStatus.lowercased().contains("included") }
    var isFullyUntracked: Bool { untrackedSessions >= sessions && totalTokens == 0 }
    var isPartiallyTracked: Bool { untrackedSessions > 0 && !isFullyUntracked }
}

struct HermesDailyStat: Decodable, Equatable, Identifiable {
    var id: String { day }
    let day: String
    let sessions: Int
    let tokens: Int
}

/// Same aggregation grouped by billing provider (nous portal, deepseek,
/// openai-codex, anthropic...). "unknown" = provider not recorded.
struct HermesProviderStat: Decodable, Equatable, Identifiable {
    var id: String { provider }
    let provider: String
    let sessions: Int
    let messages: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let reasoningTokens: Int
    let estimatedCostUsd: Double
    let actualCostUsd: Double
    let costStatus: String
    let untrackedSessions: Int
    /// Per-model breakdown inside this provider (for the drill-down).
    let models: [HermesProviderModel]

    /// Billed usage (input + output). Cache reads are excluded: they are
    /// far cheaper and would dwarf the visual bars.
    var totalTokens: Int { inputTokens + outputTokens }

    var isSubscriptionIncluded: Bool { costStatus.lowercased().contains("included") }
    var isFullyUntracked: Bool { untrackedSessions >= sessions && totalTokens == 0 }
    var isPartiallyTracked: Bool { untrackedSessions > 0 && !isFullyUntracked }
}

/// One model line inside a provider's breakdown.
struct HermesProviderModel: Decodable, Equatable, Identifiable {
    var id: String { model }
    let model: String
    let sessions: Int
    let messages: Int
    let tokens: Int
    let estimatedCostUsd: Double
    let costStatus: String
    let untrackedSessions: Int
}

struct HermesSession: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var subtitle: String
    var updatedAt: Date
    var status: SessionStatus
    var source: String? = nil
    var pinned: Bool? = nil

    enum SessionStatus: String, Codable, CaseIterable {
        case idle
        case running
        case waitingApproval
        case failed
        case completed
    }
}

struct HermesMessage: Codable, Equatable, Identifiable {
    let id: String
    var role: Role
    var text: String
    var createdAt: Date
    var toolCalls: [HermesToolCall]
    /// Reasoning/thinking text, streamed separately from the answer.
    /// Optional so transcripts (which never carry it) decode cleanly.
    var thinking: String? = nil

    enum Role: String, Codable {
        case user
        case assistant
        case system
        case tool
    }
}

extension HermesMessage {
    var isTranscriptVisible: Bool {
        guard role == .user || role == .assistant else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[CONTEXT COMPACTION — REFERENCE ONLY]") { return false }
        if trimmed.hasPrefix("[CONTEXT COMPACTION - REFERENCE ONLY]") { return false }
        if trimmed.contains("--- END OF CONTEXT SUMMARY") { return false }
        if trimmed.contains("## Historical Task Snapshot") { return false }
        return true
    }
}

struct HermesToolCall: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var command: String?
    var status: Status
    var summary: String

    enum Status: String, Codable {
        case queued
        case running
        case succeeded
        case failed
        case waitingApproval
    }
}

struct OutboundPrompt: Codable, Equatable {
    var sessionID: String?
    var text: String
    var attachments: [Attachment]

    struct Attachment: Codable, Equatable, Identifiable {
        let id: UUID
        var filename: String
        var mimeType: String
        var sizeBytes: Int
        var path: String? = nil
    }
}

/// A dangerous-command approval requested by the Desktop during a streaming
/// chat turn. The phone must answer with a verdict to unblock the turn.
struct ApprovalRequest: Equatable, Identifiable {
    let id: String
    let command: String
    let description: String
}

struct HermesModel: Codable, Equatable, Identifiable {
    let id: String
    var displayName: String
    var provider: String
    var providerName: String? = nil
    var supportsVision: Bool
    var supportsTools: Bool
    var isActive: Bool? = nil
}

struct HermesModelSelection: Codable, Equatable {
    var provider: String
    var model: String
}

/// Reasoning-effort control for the agent (desktop's ``agent.reasoning_effort``).
/// ``effort == "none"`` disables thinking; the rest are increasing levels.
struct HermesReasoningEffort: Codable, Equatable {
    var effort: String
    var options: [String]

    static let defaultOptions = [
        "none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra",
    ]

    var thinkingEnabled: Bool { effort != "none" && !effort.isEmpty }
}

struct HermesProfile: Codable, Equatable, Identifiable {
    let id: String
    var displayName: String
    var isActive: Bool
}

struct HermesFileArtifact: Codable, Equatable, Identifiable {
    let id: UUID
    var label: String
    var path: String
    var kind: Kind

    enum Kind: String, Codable {
        case text
        case image
        case html
        case pdf
        case directory
    }
}

struct HermesFileEntry: Codable, Equatable, Identifiable {
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int?
    let mtime: Double?
    let mimeType: String?
}

struct HermesDesktopAttachment: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let path: String
    let mimeType: String
    let sizeBytes: Int
}

struct HermesFileListing: Codable, Equatable {
    let path: String
    let entries: [HermesFileEntry]
}

struct HermesFileContent: Codable, Equatable {
    let name: String
    let content: String
    let truncated: Bool
}

struct HermesJob: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var detail: String
    var status: Status

    enum Status: String, Codable {
        case running
        case waitingApproval
        case completed
        case failed
        case scheduled
    }
}

struct HermesApproval: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var detail: String
    var risk: Risk

    enum Risk: String, Codable {
        case low
        case medium
        case high
    }
}

struct HermesCapabilitySnapshot: Codable, Equatable {
    var models: [HermesModel]
    var profiles: [HermesProfile]
    var files: [HermesFileArtifact]
    var jobs: [HermesJob]
    var approvals: [HermesApproval]
    var tools: [String]
}

/// Remote tunnel state (cloudflared quick tunnel / ngrok — no VPN).
struct HermesTunnelStatus: Codable, Equatable {
    let ok: Bool
    let active: Bool
    let provider: String
    let publicUrl: String
    let localUrl: String
    let error: String
}

/// A scheduled cron job on the gateway.
struct HermesCronJob: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let prompt: String
    let schedule: String
    let scheduleDisplay: String
    let state: String
    let enabled: Bool
    let nextRunAt: String?
    let lastRunAt: String?
    let deliver: String
    let skills: [String]
    let latestExecution: HermesCronExecution?

    // The real gateway sends `schedule` as an object {kind, expr, display}
    // while the mock sends a plain String — accept both.
    enum CodingKeys: String, CodingKey {
        case id, name, prompt, schedule, scheduleDisplay, state, enabled
        case nextRunAt, lastRunAt, deliver, skills, latestExecution
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        prompt = try c.decode(String.self, forKey: .prompt)
        if let plain = try? c.decode(String.self, forKey: .schedule) {
            schedule = plain
        } else if let obj = try? c.decode([String: String].self, forKey: .schedule) {
            schedule = obj["display"] ?? obj["expr"] ?? ""
        } else {
            schedule = ""
        }
        scheduleDisplay = (try? c.decode(String.self, forKey: .scheduleDisplay)) ?? schedule
        state = try c.decode(String.self, forKey: .state)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        nextRunAt = try? c.decodeIfPresent(String.self, forKey: .nextRunAt)
        lastRunAt = try? c.decodeIfPresent(String.self, forKey: .lastRunAt)
        deliver = (try? c.decode(String.self, forKey: .deliver)) ?? ""
        skills = (try? c.decode([String].self, forKey: .skills)) ?? []
        latestExecution = try? c.decodeIfPresent(HermesCronExecution.self, forKey: .latestExecution)
    }

    var isPaused: Bool {
        state == "paused" || !enabled
    }

    // Convenience memberwise init (used by the mock transport).
    init(
        id: String,
        name: String,
        prompt: String,
        schedule: String,
        scheduleDisplay: String,
        state: String,
        enabled: Bool,
        nextRunAt: String? = nil,
        lastRunAt: String? = nil,
        deliver: String = "",
        skills: [String] = [],
        latestExecution: HermesCronExecution? = nil
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.schedule = schedule
        self.scheduleDisplay = scheduleDisplay
        self.state = state
        self.enabled = enabled
        self.nextRunAt = nextRunAt
        self.lastRunAt = lastRunAt
        self.deliver = deliver
        self.skills = skills
        self.latestExecution = latestExecution
    }

    var stateLabel: String {
        switch state {
        case "running": "Running now"
        case "paused": "Paused"
        case "completed": "Completed"
        case "failed": "Failed"
        default: "Scheduled"
        }
    }
}

struct HermesCronExecution: Codable, Equatable, Identifiable {
    let id: String
    let status: String
    let startedAt: String?
    let finishedAt: String?
    let summary: String?

    var statusLabel: String {
        switch status {
        case "running": "Running"
        case "completed": "Completed"
        case "failed": "Failed"
        case "skipped": "Skipped"
        default: status.isEmpty ? "—" : status.capitalized
        }
    }
}

/// What the background refresh polls: approvals waiting for a phone verdict
/// plus cron executions that just finished.
struct HermesPendingNotifications: Codable, Equatable {
    let ok: Bool
    let approvals: [HermesPendingApproval]
    let recentCron: [HermesRecentCronRun]
}

struct HermesPendingApproval: Codable, Equatable, Identifiable {
    let id: String
    let sessionID: String
    let command: String
}

struct HermesRecentCronRun: Codable, Equatable, Identifiable {
    let jobID: String
    let status: String
    let claimedAt: String?
    let finishedAt: String?
    let summary: String?

    var id: String { "\(jobID)-\(claimedAt ?? finishedAt ?? UUID().uuidString)" }

    var isFinished: Bool {
        status == "completed" || status == "failed"
    }
}

/// A desktop skill (SKILL.md with YAML frontmatter).
struct HermesSkill: Codable, Equatable, Identifiable {
    let name: String
    let category: String
    let description: String
    let body: String?

    var id: String { name }
}

/// One persistent-memory entry (agent notes or user profile).
struct HermesMemoryEntry: Codable, Equatable, Identifiable {
    let index: Int
    let content: String

    var id: Int { index }
}

struct HermesMemory: Codable, Equatable {
    let ok: Bool
    var memory: [HermesMemoryEntry]
    var user: [HermesMemoryEntry]
}
