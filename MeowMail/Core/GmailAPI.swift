import Foundation

enum GmailError: LocalizedError {
    case http(Int, String)
    case notFound
    case rateLimited(retryAfter: TimeInterval?)

    var errorDescription: String? {
        switch self {
        case .http(let status, let message): return "Gmail error \(status): \(message)"
        case .notFound: return "Gmail couldn't find that item."
        case .rateLimited: return "Gmail is limiting requests right now. Try again in a minute."
        }
    }
}

struct ThreadStub: Decodable {
    var id: String
    var historyId: String?
}

struct GmailAPI {
    let account: String
    let clientID: String
    let tokens: TokenProvider

    private static let base = "https://gmail.googleapis.com/gmail/v1/users/me"
    private static let upload = "https://gmail.googleapis.com/upload/gmail/v1/users/me/messages/send?uploadType=multipart"

    private struct ErrorBody: Decodable {
        struct Reason: Decodable { var reason: String? }
        struct Inner: Decodable {
            var message: String?
            var errors: [Reason]?
        }
        var error: Inner?
    }

    /// Gmail reports most quota limits as 403, the same status as a permissions failure.
    static func isRateLimit(status: Int, body: Data) -> Bool {
        if status == 429 { return true }
        guard status == 403, let error = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error else { return false }
        let reasons = error.errors?.compactMap(\.reason) ?? []
        return reasons.contains { $0.localizedCaseInsensitiveContains("RateLimit") }
            || error.message?.localizedCaseInsensitiveContains("quota exceeded") == true
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        var request = request
        let token = try await tokens.accessToken(account: account, clientID: clientID)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        for attempt in 0..<3 {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) { return data }
            if status == 404 { throw GmailError.notFound }
            // The quota is per minute, so retrying within seconds can't succeed.
            if Self.isRateLimit(status: status, body: data) {
                let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
                throw GmailError.rateLimited(retryAfter: header.flatMap(TimeInterval.init))
            }
            if status >= 500, attempt < 2 {
                try await Task.sleep(for: .seconds(1 << attempt))
                continue
            }
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error?.message
            throw GmailError.http(status, message ?? "Request failed")
        }
        throw GmailError.http(0, "Request failed")
    }

    private func get(_ path: String, _ query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(string: "\(Self.base)/\(path)")!
        if !query.isEmpty { components.queryItems = query }
        return try await perform(URLRequest(url: components.url!))
    }

    func listThreads(query: String, max: Int) async throws -> [ThreadStub] {
        struct Page: Decodable { var threads: [ThreadStub]? }
        let data = try await get("threads", [.init(name: "q", value: query),
                                             .init(name: "maxResults", value: String(max))])
        return try JSONDecoder().decode(Page.self, from: data).threads ?? []
    }

    func thread(_ id: String) async throws -> MailThread {
        let data = try await get("threads/\(id)", [.init(name: "format", value: "full")])
        let payload = try JSONDecoder().decode(ThreadPayload.self, from: data)
        return GmailParser.thread(payload)
    }

    func markRead(threadID: String) async throws {
        var request = URLRequest(url: URL(string: "\(Self.base)/threads/\(threadID)/modify")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"removeLabelIds":["UNREAD"]}"#.utf8)
        _ = try await perform(request)
    }

    func attachment(messageID: String, attachmentID: String) async throws -> Data {
        struct Body: Decodable { var data: String }
        let raw = try await get("messages/\(messageID)/attachments/\(attachmentID)")
        let body = try JSONDecoder().decode(Body.self, from: raw)
        guard let data = Base64URL.decode(body.data) else { throw GmailError.http(0, "Attachment was damaged") }
        return data
    }

    /// Uses the upload endpoint because it accepts far larger messages than JSON.
    func send(raw: Data, threadID: String?) async throws {
        struct Metadata: Encodable { var threadId: String? }
        let boundary = "meowmail-upload-\(UUID().uuidString)"
        var body = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
        body.append(try JSONEncoder().encode(Metadata(threadId: threadID)))
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: message/rfc822\r\n\r\n".utf8))
        body.append(raw)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: URL(string: Self.upload)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        _ = try await perform(request)
    }

    func profileEmail() async throws -> String {
        struct Profile: Decodable { var emailAddress: String }
        let data = try await get("profile")
        return try JSONDecoder().decode(Profile.self, from: data).emailAddress.lowercased()
    }
}
