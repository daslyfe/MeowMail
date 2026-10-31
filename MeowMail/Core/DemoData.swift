import Foundation

/// Sample mail shown when the app is launched with `-demo`, for trying the
/// interface without signing in. Nothing here touches the network.
enum DemoData {
    @MainActor
    static func load(into store: AppStore) {
        let me = "me@example.com"
        let sam = Address(name: "Sam Rivera", email: "sam@example.com")
        let priya = Address(name: "Priya Shah", email: "priya@example.com")
        let lee = Address(name: "Lee Chen", email: "lee@example.com")
        let self_ = Address(name: "Me", email: me)
        let now = Date()

        func message(_ id: String, _ thread: String, _ from: Address, _ to: [Address], cc: [Address] = [],
                     _ subject: String, minutes: Double, labels: Set<String>, _ text: String,
                     attachments: [AttachmentRef] = []) -> Message {
            Message(id: id, threadID: thread, from: from, to: to, cc: cc, subject: subject,
                    date: now.addingTimeInterval(-minutes * 60), labels: labels, plain: text, html: nil,
                    chatText: text, isRichLayout: false, messageIDHeader: "<\(id)@example.com>",
                    references: nil, attachments: attachments)
        }

        let trip = MailThread(id: "trip", historyID: "1", snippet: "Booked! Tickets attached.", messages: [
            message("t1", "trip", sam, [self_, priya], "Lisbon in March?", minutes: 2900, labels: ["INBOX"],
                    "Are we still on for Lisbon? Flights are cheap the second week of March."),
            message("t2", "trip", priya, [sam, self_], "Re: Lisbon in March?", minutes: 2800, labels: ["INBOX"],
                    "I'm in. Can we stay near Alfama?"),
            message("t3", "trip", self_, [sam, priya], "Re: Lisbon in March?", minutes: 1500, labels: ["SENT"],
                    "Works for me. Sam, can you book the flights?"),
            message("t4", "trip", sam, [self_, priya], cc: [lee], "Re: Lisbon in March?", minutes: 12, labels: ["INBOX", "UNREAD"],
                    "Booked! Tickets attached. Added Lee so they can sort the apartment.",
                    attachments: [AttachmentRef(id: "a1", attachmentID: "a1", filename: "tickets.pdf",
                                                mimeType: "application/pdf", size: 482_000)]),
        ])
        let invoice = MailThread(id: "invoice", historyID: "1", snippet: "Here's the October invoice.", messages: [
            message("i1", "invoice", lee, [self_], "October invoice", minutes: 45, labels: ["INBOX", "UNREAD"],
                    "Here's the October invoice. Thanks for a great month."),
        ])
        let lunch = MailThread(id: "lunch", historyID: "1", snippet: "Thursday works!", messages: [
            message("l1", "lunch", priya, [self_], "Lunch this week", minutes: 1600, labels: ["INBOX"],
                    "Free for lunch this week?"),
            message("l2", "lunch", self_, [priya], "Re: Lunch this week", minutes: 1580, labels: ["SENT"],
                    "Thursday works!"),
        ])

        var timeline = Channel.timeline()
        timeline.lastChecked = now.addingTimeInterval(-3600)
        timeline.pinned = ["lunch"]
        var samChannel = Channel(kind: .person, name: "sam")
        samChannel.addresses = [sam.email]
        samChannel.lastChecked = now.addingTimeInterval(-3600)
        var priyaChannel = Channel(kind: .person, name: "priya")
        priyaChannel.addresses = [priya.email]

        var account = Account(email: me, channels: [timeline, samChannel, priyaChannel])
        account.lastChecked = now.addingTimeInterval(-3600)
        var work = Account(email: "work@example.com")
        work.lastChecked = now

        store.accounts = [account, work]
        store.threads = [me: Dictionary(uniqueKeysWithValues: [trip, invoice, lunch].map { ($0.id, $0) })]
        store.selectedEmail = me
        store.selectedChannelID = timeline.id
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-demoThread"),
           index + 1 < ProcessInfo.processInfo.arguments.count {
            store.selectedThreadID = ProcessInfo.processInfo.arguments[index + 1]
        }
    }
}
