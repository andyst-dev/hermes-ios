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

struct HermesSession: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var subtitle: String
    var updatedAt: Date
    var status: SessionStatus

    enum SessionStatus: String, Codable, CaseIterable {
        case idle
        case running
        case waitingApproval
        case failed
        case completed
    }
}

struct HermesMessage: Codable, Equatable, Identifiable {
    let id: UUID
    var role: Role
    var text: String
    var createdAt: Date
    var toolCalls: [HermesToolCall]

    enum Role: String, Codable {
        case user
        case assistant
        case system
    }
}

struct HermesToolCall: Codable, Equatable, Identifiable {
    let id: UUID
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
    }
}
