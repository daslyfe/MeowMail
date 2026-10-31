import Foundation

struct OutgoingAttachment: Identifiable, Hashable {
    var id = UUID()
    var filename: String
    var mimeType: String
    var data: Data
}

struct Draft: Hashable {
    var threadID: String?
    var to: String = ""
    var cc: String = ""
    var subject: String = ""
    var body: String = ""
    var inReplyTo: String?
    var references: String?
    var quoted: String = ""
    var attachments: [OutgoingAttachment] = []

    static let attachmentLimit = 25 * 1024 * 1024

    var attachmentBytes: Int { attachments.reduce(0) { $0 + $1.data.count } }
    var toAddresses: [Address] { Address.parseList(to) }
    var ccAddresses: [Address] { Address.parseList(cc) }

    /// Reply-all to the latest message, leaving out the account's own address.
    static func reply(to thread: MailThread, account: String) -> Draft {
        guard let last = thread.messages.last else { return Draft(threadID: thread.id) }
        let me = account.lowercased()
        let primary = last.isFromMe ? last.to : [last.from] + last.to
        var seen: Set<String> = [me]
        let to = primary.filter { seen.insert($0.email).inserted }
        let cc = last.cc.filter { seen.insert($0.email).inserted }

        let subject = last.subject.lowercased().hasPrefix("re:") ? last.subject : "Re: \(last.subject)"
        let references = [last.references, last.messageIDHeader].compactMap { $0 }.joined(separator: " ")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, MMM d, yyyy 'at' h:mm a"
        let history = last.fullText
            .components(separatedBy: .newlines)
            .map { "> \($0)" }
            .joined(separator: "\n")
        let quoted = "On \(formatter.string(from: last.date)), \(last.from.display) wrote:\n\(history)"

        return Draft(threadID: thread.id,
                     to: to.map(\.email).joined(separator: ", "),
                     cc: cc.map(\.email).joined(separator: ", "),
                     subject: subject,
                     inReplyTo: last.messageIDHeader,
                     references: references.isEmpty ? nil : references,
                     quoted: quoted)
    }

    /// Recipients who have not been on this thread before.
    func newRecipients(comparedTo thread: MailThread) -> [Address] {
        (toAddresses + ccAddresses).filter { !thread.participants.contains($0.email) }
    }
}

enum MIMEBuilder {
    static func build(_ draft: Draft, from: String, date: Date = Date(), boundary: String = "meowmail-\(UUID().uuidString)") -> Data {
        var headers: [String] = []
        func add(_ name: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            headers.append("\(name): \(sanitize(value))")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        add("From", from)
        add("To", draft.toAddresses.map(\.email).joined(separator: ", "))
        add("Cc", draft.ccAddresses.map(\.email).joined(separator: ", "))
        add("Subject", encodeHeader(draft.subject))
        add("Date", formatter.string(from: date))
        add("In-Reply-To", draft.inReplyTo)
        add("References", draft.references)
        add("MIME-Version", "1.0")

        let text = draft.quoted.isEmpty ? draft.body : "\(draft.body)\n\n\(draft.quoted)"
        let bodyPart = """
        Content-Type: text/plain; charset="UTF-8"\r
        Content-Transfer-Encoding: base64\r
        \r
        \(wrappedBase64(Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)))\r\n
        """

        var data = Data()
        if draft.attachments.isEmpty {
            data.append(Data((headers.joined(separator: "\r\n") + "\r\n").utf8))
            data.append(Data(bodyPart.utf8))
            return data
        }

        headers.append("Content-Type: multipart/mixed; boundary=\"\(boundary)\"")
        data.append(Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8))
        data.append(Data("--\(boundary)\r\n".utf8))
        data.append(Data(bodyPart.utf8))
        for attachment in draft.attachments {
            let part = """
            --\(boundary)\r
            Content-Type: \(sanitize(attachment.mimeType))\r
            Content-Transfer-Encoding: base64\r
            Content-Disposition: attachment; \(filenameParameter(attachment.filename))\r
            \r
            \(wrappedBase64(attachment.data))\r\n
            """
            data.append(Data(part.utf8))
        }
        data.append(Data("--\(boundary)--\r\n".utf8))
        return data
    }

    /// Strips line breaks so user input can never inject extra headers.
    private static func sanitize(_ value: String) -> String {
        value.components(separatedBy: .newlines).joined(separator: " ")
    }

    private static func encodeHeader(_ value: String) -> String {
        let clean = sanitize(value)
        guard clean.unicodeScalars.contains(where: { !$0.isASCII }) else { return clean }
        return "=?UTF-8?B?\(Data(clean.utf8).base64EncodedString())?="
    }

    private static func filenameParameter(_ filename: String) -> String {
        let clean = sanitize(filename)
        if clean.unicodeScalars.allSatisfy(\.isASCII) {
            let escaped = clean.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "filename=\"\(escaped)\""
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = clean.addingPercentEncoding(withAllowedCharacters: allowed) ?? "attachment"
        return "filename*=UTF-8''\(encoded)"
    }

    private static func wrappedBase64(_ data: Data) -> String {
        data.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
    }
}
