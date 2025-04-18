import Foundation
import UIKit

// MARK: - Chat Models
struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let content: String
    let type: MessageType
    let timestamp: Date
    var status: MessageStatus

    enum MessageType: Equatable {
        case user
        case assistant
    }

    enum MessageStatus: Equatable {
        case sending
        case sent
        case failed(Error)

        static func == (lhs: ChatMessage.MessageStatus, rhs: ChatMessage.MessageStatus) -> Bool {
            switch (lhs, rhs) {
            case (.sending, .sending):
                return true
            case (.sent, .sent):
                return true
            case (.failed(let lhsError), .failed(let rhsError)):
                return lhsError.localizedDescription == rhsError.localizedDescription
            default:
                return false
            }
        }

        var isError: Bool {
            if case .failed = self {
                return true
            }
            return false
        }
    }

    init(
        id: UUID = UUID(),
        content: String,
        type: MessageType,
        timestamp: Date = Date(),
        status: MessageStatus = .sent
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.timestamp = timestamp
        self.status = status
    }

    // MARK: - Helper Methods

    /// Copy the message content to the clipboard
    func copyText() {
        UIPasteboard.general.string = content
        #if DEBUG
        print("💬 ChatMessage: Copied message content to clipboard")
        #endif
    }

    /// Check if the message is from the user
    var isUser: Bool {
        return type == .user
    }
}

// MARK: - Chat State
enum ChatState: Equatable {
    case idle
    case typing
    case processing
    case error(String)

    var isProcessing: Bool {
        if case .processing = self {
            return true
        }
        return false
    }
}

// MARK: - Chat Error
enum ChatError: LocalizedError {
    case emptyMessage
    case networkError(Error)
    case processingError(String)

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "Message cannot be empty"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .processingError(let message):
            return "Processing error: \(message)"
        }
    }
}
