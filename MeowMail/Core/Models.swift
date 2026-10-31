import Foundation

struct Address: Codable, Hashable {
    var name: String?
    var email: String

    init(name: String? = nil, email: String) {
        self.name = name?.isEmpty == true ? nil : name
        self.email = email.lowercased()
    }

    var display: String { name ?? email }

    var firstName: String {
        guard let name else { return email.components(separatedBy: "@")[0] }
        return name.components(separatedBy: " ")[0]
    }

    /// Parses a header such as `"Doe, Jane" <jane@x.com>, bob@y.com`.
    static func parseList(_ header: String) -> [Address] {
        splitList(header).compactMap(parseOne)
    }

    private static func splitList(_ header: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var inAngle = false
        for ch in header {
            switch ch {
            case "\"": inQuotes.toggle()
            case "<" where !inQuotes: inAngle = true
            case ">" where !inQuotes: inAngle = false
            case ",", ";":
                if !inQuotes && !inAngle {
                    parts.append(current)
                    current = ""
                    continue
                }
            default: break
            }
            current.append(ch)
        }
        parts.append(current)
        return parts
    }

    private static func parseOne(_ raw: String) -> Address? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let open = text.lastIndex(of: "<"), let close = text.lastIndex(of: ">"), open < close {
            let email = String(text[text.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            guard isValidEmail(email) else { return nil }
            let name = text[..<open]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return Address(name: name, email: email)
        }
        return isValidEmail(text) ? Address(email: text) : nil
    }

    static func isValidEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
            && !text.contains(where: { $0.isWhitespace || "<>,;\"".contains($0) })
    }
}

struct AttachmentRef: Codable, Hashable, Identifiable {
    var id: String
    var attachmentID: String
    var filename: String
    var mimeType: String
    var size: Int

    var sizeText: String { ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) }
}

struct Message: Codable, Identifiable, Hashable {
    var id: String
    var threadID: String
    var from: Address
    var to: [Address]
    var cc: [Address]
    var subject: String
    var date: Date
    var labels: Set<String>
    var plain: String?
    var html: String?
    var chatText: String
    var isRichLayout: Bool
    var messageIDHeader: String?
    var references: String?
    var attachments: [AttachmentRef]

    var isUnread: Bool { labels.contains("UNREAD") }
    var isFromMe: Bool { labels.contains("SENT") }

    /// The complete text of the message, with quoted history left in.
    var fullText: String { plain ?? html.map { HTMLText.plain($0) } ?? "" }
}

struct MailThread: Codable, Identifiable, Hashable {
    var id: String
    var historyID: String
    var snippet: String
    var messages: [Message]

    var subject: String {
        let text = messages.first?.subject ?? ""
        return text.isEmpty ? "(no subject)" : text
    }

    var lastDate: Date { messages.last?.date ?? .distantPast }

    var lastIncomingDate: Date? { messages.last(where: { !$0.isFromMe })?.date }

    var isUnread: Bool { messages.contains(where: \.isUnread) }

    var participants: Set<String> {
        var result: Set<String> = []
        for message in messages {
            result.insert(message.from.email)
            message.to.forEach { result.insert($0.email) }
            message.cc.forEach { result.insert($0.email) }
        }
        return result
    }

    var attachmentCount: Int { messages.reduce(0) { $0 + $1.attachments.count } }

    private var isDiscarded: Bool {
        messages.allSatisfy { $0.labels.contains("TRASH") || $0.labels.contains("SPAM") }
    }

    /// Whether any message is in the inbox outside the Promotions and Social tabs.
    var inTimeline: Bool {
        !isDiscarded && messages.contains {
            $0.labels.contains("INBOX")
                && !$0.labels.contains("CATEGORY_PROMOTIONS")
                && !$0.labels.contains("CATEGORY_SOCIAL")
        }
    }

    func belongs(to channel: Channel) -> Bool {
        switch channel.kind {
        case .all:
            return inTimeline
        case .person:
            return !isDiscarded && !participants.isDisjoint(with: channel.addresses)
        }
    }

    /// True when an unread incoming message arrived after `date`.
    func hasNewActivity(since date: Date) -> Bool {
        messages.contains { $0.isUnread && !$0.isFromMe && $0.date > date }
    }
}

struct Channel: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case all, person }

    var id: String = UUID().uuidString
    var kind: Kind
    var name: String
    var addresses: Set<String> = []
    var pinned: Set<String> = []
    var lastChecked: Date = Date()

    static func timeline() -> Channel { Channel(kind: .all, name: "threads") }

    var gmailQuery: String {
        addresses.sorted()
            .map { "from:\($0) OR to:\($0) OR cc:\($0)" }
            .joined(separator: " OR ")
    }
}

struct Account: Codable, Identifiable, Hashable {
    var email: String
    var channels: [Channel] = [.timeline()]
    var lastChecked: Date = Date()
    var needsReconnect = false

    var id: String { email }
}
