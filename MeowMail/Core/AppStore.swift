import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    private struct SavedState: Codable {
        var accounts: [Account]
        var selectedEmail: String?
    }

    var clientID: String {
        didSet { if !isDemo { UserDefaults.standard.set(clientID, forKey: "googleClientID") } }
    }
    var accounts: [Account] = []
    var threads: [String: [String: MailThread]] = [:]
    var selectedEmail: String?
    var selectedChannelID: String?
    var selectedThreadID: String?
    var searchResults: [String]?
    var isSyncing = false
    var errorMessage: String?

    let isDemo: Bool
    private let tokens = TokenProvider()
    private let signIn = GoogleSignIn()
    private var lastSync = Date.distantPast
    private var pausedUntil: [String: Date] = [:]

    init(demo: Bool = false) {
        isDemo = demo
        clientID = UserDefaults.standard.string(forKey: "googleClientID") ?? ""
        if demo {
            DemoData.load(into: self)
        } else {
            load()
        }
    }

    // MARK: Lookups

    var selectedAccount: Account? { accounts.first { $0.email == selectedEmail } }

    var selectedChannel: Channel? { selectedAccount?.channels.first { $0.id == selectedChannelID } }

    func thread(_ id: String) -> MailThread? {
        guard let selectedEmail else { return nil }
        return threads[selectedEmail]?[id]
    }

    func threads(in channel: Channel, account: String) -> [MailThread] {
        (threads[account]?.values.filter { $0.belongs(to: channel) } ?? [])
            .sorted { lhs, rhs in
                let leftPinned = channel.pinned.contains(lhs.id)
                let rightPinned = channel.pinned.contains(rhs.id)
                if leftPinned != rightPinned { return leftPinned }
                return lhs.lastDate > rhs.lastDate
            }
    }

    func newCount(_ channel: Channel, account: String) -> Int {
        threads(in: channel, account: account).filter { $0.hasNewActivity(since: channel.lastChecked) }.count
    }

    func hasNewThreads(_ account: Account) -> Bool {
        threads[account.email]?.values.contains { $0.inTimeline && $0.hasNewActivity(since: account.lastChecked) } ?? false
    }

    var knownContacts: [Address] {
        guard let selectedEmail, let mail = threads[selectedEmail] else { return [] }
        var seen: [String: Address] = [:]
        for thread in mail.values {
            for message in thread.messages {
                for address in [message.from] + message.to + message.cc where address.email != selectedEmail {
                    if seen[address.email]?.name == nil { seen[address.email] = address }
                }
            }
        }
        return seen.values.sorted { $0.display.lowercased() < $1.display.lowercased() }
    }

    // MARK: Navigation

    func select(account email: String) {
        selectedEmail = email
        selectedThreadID = nil
        searchResults = nil
        mutateAccount(email) { $0.lastChecked = Date() }
        selectedChannelID = selectedAccount?.channels.first?.id
        save()
    }

    /// Clears a channel's badge. Gmail's read status is unchanged until a thread is opened.
    func open(channel id: String) {
        selectedChannelID = id
        selectedThreadID = nil
        searchResults = nil
        guard let selectedEmail else { return }
        mutateChannel(selectedEmail, id) { $0.lastChecked = Date() }
        save()
    }

    func open(thread id: String) {
        selectedThreadID = id
        guard let selectedEmail, let thread = threads[selectedEmail]?[id], thread.isUnread else { return }
        var updated = thread
        updated.messages = thread.messages.map { message in
            var copy = message
            copy.labels.remove("UNREAD")
            return copy
        }
        threads[selectedEmail]?[id] = updated
        guard !isDemo else { return }
        let api = api(selectedEmail)
        Task {
            do {
                try await api.markRead(threadID: id)
                saveThreads(selectedEmail)
            } catch {
                threads[selectedEmail]?[id]?.messages = thread.messages
                report(error, account: selectedEmail, background: true)
            }
        }
    }

    // MARK: Channels and pins

    func saveChannel(_ channel: Channel) {
        guard let selectedEmail else { return }
        mutateAccount(selectedEmail) { account in
            if let index = account.channels.firstIndex(where: { $0.id == channel.id }) {
                account.channels[index] = channel
            } else {
                account.channels.append(channel)
            }
        }
        save()
        Task { await syncChannel(channel, account: selectedEmail) }
    }

    func deleteChannel(_ id: String) {
        guard let selectedEmail else { return }
        mutateAccount(selectedEmail) { $0.channels.removeAll { $0.id == id && $0.kind != .all } }
        if selectedChannelID == id { selectedChannelID = selectedAccount?.channels.first?.id }
        save()
    }

    func togglePin(thread id: String, channel channelID: String) {
        guard let selectedEmail else { return }
        mutateChannel(selectedEmail, channelID) { channel in
            if channel.pinned.remove(id) == nil { channel.pinned.insert(id) }
        }
        save()
    }

    func removeAccount(_ email: String) {
        accounts.removeAll { $0.email == email }
        threads[email] = nil
        Keychain.delete(account: email)
        Task { await tokens.forget(account: email) }
        try? FileManager.default.removeItem(at: threadsURL(email))
        if selectedEmail == email {
            selectedEmail = nil
            if let next = accounts.first?.email { select(account: next) }
        }
        save()
    }

    // MARK: Sign-in

    func addAccount() async {
        guard !isDemo else { return }
        do {
            let result = try await signIn.signIn(clientID: clientID)
            // The address isn't known until the token works, so read it with a temporary key.
            let pending = "pending-\(UUID().uuidString)"
            Keychain.save(result.refresh, account: pending)
            await tokens.store(accessToken: result.access, expiresIn: result.expiresIn, account: pending)
            defer { Keychain.delete(account: pending) }
            let email = try await api(pending).profileEmail()

            Keychain.save(result.refresh, account: email)
            await tokens.store(accessToken: result.access, expiresIn: result.expiresIn, account: email)
            if accounts.contains(where: { $0.email == email }) {
                mutateAccount(email) { $0.needsReconnect = false }
            } else {
                accounts.append(Account(email: email))
            }
            select(account: email)
            await sync()
        } catch {
            report(error)
        }
    }

    // MARK: Sync

    private static let timelineQuery = "in:inbox -category:promotions -category:social"
    static let syncInterval: TimeInterval = 60
    // Gmail starts refusing at about 60 requests a minute, so this allows 36.
    private static let batchSize = 3
    private static let batchPause: Duration = .seconds(5)

    /// The Mac app becomes active on every window switch, so this skips syncs that aren't due.
    func syncIfDue() async {
        if Date().timeIntervalSince(lastSync) >= Self.syncInterval { await sync() }
    }

    func sync() async {
        guard !isDemo, !isSyncing else { return }
        isSyncing = true
        lastSync = Date()
        defer { isSyncing = false }
        for account in accounts where !account.needsReconnect {
            if let paused = pausedUntil[account.email], paused > Date() { continue }
            do {
                try await syncTimeline(account.email)
                for channel in account.channels where channel.kind == .person {
                    try await fetch(query: channel.gmailQuery, max: 50, account: account.email)
                }
            } catch {
                report(error, account: account.email, background: true)
            }
            // Saved even after a failure, so downloaded threads aren't fetched again.
            saveThreads(account.email)
        }
    }

    private func syncChannel(_ channel: Channel, account: String) async {
        guard !isDemo, channel.kind == .person else { return }
        do {
            try await fetch(query: channel.gmailQuery, max: 100, account: account)
        } catch {
            report(error, account: account, background: true)
        }
        saveThreads(account)
    }

    private func syncTimeline(_ account: String) async throws {
        let stubs = try await fetch(query: Self.timelineQuery, max: 100, account: account)

        // Threads that dropped off the list were probably archived or deleted
        // elsewhere, so refresh them to pick up their current labels.
        let listed = Set(stubs.map(\.id))
        let oldest = stubs.compactMap { threads[account]?[$0.id]?.lastDate }.min() ?? .distantFuture
        let stale = threads[account]?.values
            .filter { $0.inTimeline && !listed.contains($0.id) && $0.lastDate >= oldest }
            .map(\.id) ?? []
        try await download(stale, account: account)
    }

    @discardableResult
    private func fetch(query: String, max: Int, account: String) async throws -> [ThreadStub] {
        let stubs = try await api(account).listThreads(query: query, max: max)
        let changed = stubs.filter { threads[account]?[$0.id]?.historyID != $0.historyId }.map(\.id)
        try await download(changed, account: account)
        // Compare against the list's own value next time, so a thread whose
        // history ID differs between endpoints isn't downloaded on every sync.
        for stub in stubs {
            if let historyID = stub.historyId { threads[account]?[stub.id]?.historyID = historyID }
        }
        return stubs
    }

    private func download(_ ids: [String], account: String) async throws {
        let api = api(account)
        for start in stride(from: 0, to: ids.count, by: Self.batchSize) {
            if start > 0 { try await Task.sleep(for: Self.batchPause) }
            let batch = ids[start..<min(start + Self.batchSize, ids.count)]
            try await withThrowingTaskGroup(of: (String, MailThread?).self) { group in
                for id in batch {
                    group.addTask {
                        do {
                            return (id, try await api.thread(id))
                        } catch GmailError.notFound {
                            return (id, nil)
                        }
                    }
                }
                for try await (id, thread) in group {
                    threads[account, default: [:]][id] = thread
                }
            }
        }
    }

    func search(_ query: String) async {
        guard let selectedEmail else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = nil
            return
        }
        if isDemo {
            searchResults = threads[selectedEmail]?.values
                .filter { $0.subject.localizedCaseInsensitiveContains(trimmed) }
                .map(\.id)
            return
        }
        do {
            let stubs = try await fetch(query: trimmed, max: 50, account: selectedEmail)
            searchResults = stubs.map(\.id).filter { threads[selectedEmail]?[$0] != nil }
        } catch {
            report(error, account: selectedEmail)
        }
    }

    // MARK: Sending and attachments

    func send(_ draft: Draft) async -> Bool {
        guard let selectedEmail else { return false }
        guard !isDemo else { return true }
        do {
            let raw = MIMEBuilder.build(draft, from: selectedEmail)
            try await api(selectedEmail).send(raw: raw, threadID: draft.threadID)
            if let id = draft.threadID {
                try await download([id], account: selectedEmail)
            }
            saveThreads(selectedEmail)
            return true
        } catch {
            report(error, account: selectedEmail)
            return false
        }
    }

    /// Downloads an attachment to a private temporary folder and returns its location.
    func download(attachment: AttachmentRef, messageID: String) async -> URL? {
        guard let selectedEmail, !isDemo else { return nil }
        do {
            let data = try await api(selectedEmail).attachment(messageID: messageID, attachmentID: attachment.attachmentID)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = URL(fileURLWithPath: attachment.filename).lastPathComponent
            let url = folder.appendingPathComponent(name.isEmpty ? "attachment" : name)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            report(error, account: selectedEmail)
            return nil
        }
    }

    // MARK: Helpers

    private func api(_ account: String) -> GmailAPI {
        GmailAPI(account: account, clientID: clientID, tokens: tokens)
    }

    /// Background syncs stay quiet when offline or interrupted; they simply retry.
    private func report(_ error: Error, account: String? = nil, background: Bool = false) {
        if case AuthError.reconnectRequired(let email) = error {
            mutateAccount(email) { $0.needsReconnect = true }
            save()
        }
        if case GmailError.rateLimited(let retryAfter) = error, let account {
            pausedUntil[account] = Date().addingTimeInterval(max(retryAfter ?? 0, Self.syncInterval))
            if background { return }
        }
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        if background, error is URLError { return }
        if (error as NSError).domain == "com.apple.AuthenticationServices.WebAuthenticationSession" { return }
        errorMessage = error.localizedDescription
    }

    private func mutateAccount(_ email: String, _ change: (inout Account) -> Void) {
        guard let index = accounts.firstIndex(where: { $0.email == email }) else { return }
        change(&accounts[index])
    }

    private func mutateChannel(_ email: String, _ id: String, _ change: (inout Channel) -> Void) {
        mutateAccount(email) { account in
            guard let index = account.channels.firstIndex(where: { $0.id == id }) else { return }
            change(&account.channels[index])
        }
    }

    // MARK: Persistence

    private var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("MeowMail", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var stateURL: URL { folder.appendingPathComponent("state.json") }

    private func threadsURL(_ email: String) -> URL {
        folder.appendingPathComponent("threads-\(email).json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        accounts = state.accounts
        selectedEmail = state.selectedEmail ?? accounts.first?.email
        selectedChannelID = selectedAccount?.channels.first?.id
        for account in accounts {
            if let data = try? Data(contentsOf: threadsURL(account.email)),
               let mail = try? JSONDecoder().decode([String: MailThread].self, from: data) {
                threads[account.email] = mail
            }
        }
    }

    private func save() {
        guard !isDemo else { return }
        let state = SavedState(accounts: accounts, selectedEmail: selectedEmail)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    private func saveThreads(_ email: String) {
        guard !isDemo, let mail = threads[email] else { return }
        let url = threadsURL(email)
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(mail) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
