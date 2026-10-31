import Foundation

struct ThreadPayload: Decodable {
    var id: String
    var historyId: String?
    var snippet: String?
    var messages: [MessagePayload]?
}

struct MessagePayload: Decodable {
    var id: String
    var threadId: String
    var labelIds: [String]?
    var internalDate: String?
    var payload: Part?

    struct Part: Decodable {
        var partId: String?
        var mimeType: String?
        var filename: String?
        var headers: [Header]?
        var body: Body?
        var parts: [Part]?
    }

    struct Header: Decodable {
        var name: String
        var value: String
    }

    struct Body: Decodable {
        var attachmentId: String?
        var size: Int?
        var data: String?
    }
}

enum Base64URL {
    static func decode(_ text: String) -> Data? {
        var value = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value.removeAll { $0 == "=" || $0.isNewline }
        let padding = (4 - value.count % 4) % 4
        return Data(base64Encoded: value + String(repeating: "=", count: padding))
    }
}

enum GmailParser {
    static func thread(_ payload: ThreadPayload) -> MailThread {
        let messages = (payload.messages ?? []).map(message).sorted { $0.date < $1.date }
        return MailThread(id: payload.id,
                          historyID: payload.historyId ?? "",
                          snippet: decodeSnippet(payload.snippet ?? ""),
                          messages: messages)
    }

    static func message(_ payload: MessagePayload) -> Message {
        let root = payload.payload
        func header(_ name: String) -> String? {
            root?.headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        var plain: String?
        var html: String?
        var attachments: [AttachmentRef] = []
        if let root {
            walk(root, messageID: payload.id, plain: &plain, html: &html, attachments: &attachments)
        }

        let milliseconds = Double(payload.internalDate ?? "") ?? 0
        let rich = html.map(HTMLText.isRichLayout) ?? false
        let chatText: String
        if let plain, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chatText = QuoteStripper.strip(plain)
        } else if let html {
            chatText = QuoteStripper.strip(HTMLText.plain(html, dropQuotes: true))
        } else {
            chatText = ""
        }

        return Message(id: payload.id,
                       threadID: payload.threadId,
                       from: Address.parseList(header("From") ?? "").first ?? Address(email: "unknown@unknown"),
                       to: Address.parseList(header("To") ?? ""),
                       cc: Address.parseList(header("Cc") ?? ""),
                       subject: header("Subject") ?? "",
                       date: Date(timeIntervalSince1970: milliseconds / 1000),
                       labels: Set(payload.labelIds ?? []),
                       plain: plain,
                       html: html,
                       chatText: chatText,
                       isRichLayout: rich,
                       messageIDHeader: header("Message-ID"),
                       references: header("References"),
                       attachments: attachments)
    }

    private static func walk(_ part: MessagePayload.Part,
                             messageID: String,
                             plain: inout String?,
                             html: inout String?,
                             attachments: inout [AttachmentRef]) {
        let mime = part.mimeType?.lowercased() ?? ""
        if let filename = part.filename, !filename.isEmpty, let attachmentID = part.body?.attachmentId {
            attachments.append(AttachmentRef(id: "\(messageID)-\(part.partId ?? filename)",
                                             attachmentID: attachmentID,
                                             filename: filename,
                                             mimeType: mime,
                                             size: part.body?.size ?? 0))
        } else if let encoded = part.body?.data, let data = Base64URL.decode(encoded) {
            let text = String(decoding: data, as: UTF8.self)
            if mime == "text/plain", plain == nil { plain = text }
            if mime == "text/html", html == nil { html = text }
        }
        for child in part.parts ?? [] {
            walk(child, messageID: messageID, plain: &plain, html: &html, attachments: &attachments)
        }
    }

    private static func decodeSnippet(_ text: String) -> String { HTMLText.plain(text) }
}
