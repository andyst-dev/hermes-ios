import Foundation

enum PreviewData {
    static let sessions: [HermesSession] = [
        HermesSession(id: "pr-clean", title: "PR Discord permissions", subtitle: "NousResearch/hermes-agent · docs", updatedAt: .now, status: .completed),
        HermesSession(id: "ios", title: "Hermes iOS Companion", subtitle: "SwiftUI prototype · running", updatedAt: .now, status: .running),
        HermesSession(id: "approval", title: "Release review", subtitle: "Waiting for approval", updatedAt: .now, status: .waitingApproval)
    ]

    static let messages: [HermesMessage] = [
        HermesMessage(id: UUID(), role: .assistant, text: "Connecté au Mac. Je peux piloter Hermes, lire les sessions, suivre les tools et lancer les validations.", createdAt: .now, toolCalls: []),
        HermesMessage(id: UUID(), role: .user, text: "Trouve un PR méga clean facile", createdAt: .now, toolCalls: []),
        HermesMessage(
            id: UUID(),
            role: .assistant,
            text: "J’ai trouvé un candidat docs ciblé et sans duplicate. Je patch minimalement puis je build le site.",
            createdAt: .now,
            toolCalls: [
                HermesToolCall(id: UUID(), name: "github", command: "gh issue view", status: .succeeded, summary: "Issue open, no assignee, no duplicate PR"),
                HermesToolCall(id: UUID(), name: "terminal", command: "npm run build", status: .succeeded, summary: "Docusaurus build completed")
            ]
        )
    ]
}
