import XCTest
@testable import MeowMail

final class CoreTests: XCTestCase {
    private func message(id: String = "m1", from: String = "a@x.com", to: [String] = [], cc: [String] = [],
                         labels: Set<String> = ["INBOX"], date: Date = Date(), text: String = "hi") -> Message {
        Message(id: id, threadID: "t1", from: Address(email: from), to: to.map { Address(email: $0) },
                cc: cc.map { Address(email: $0) }, subject: "Plans", date: date, labels: labels,
                plain: text, html: nil, chatText: text, isRichLayout: false,
                messageIDHeader: "<\(id)@mail>", references: nil, attachments: [])
    }

    private func thread(_ messages: [Message]) -> MailThread {
        MailThread(id: "t1", historyID: "1", snippet: "", messages: messages)
    }

    func testAddressParsingHandlesQuotedCommas() {
        let list = Address.parseList("\"Doe, Jane\" <Jane@X.com>, bob@y.com, not-an-address")
        XCTAssertEqual(list, [Address(name: "Doe, Jane", email: "jane@x.com"), Address(email: "bob@y.com")])
    }

    func testStripsGmailQuoteAcrossWrappedLine() {
        let text = "Sounds good!\n\nOn Tue, Oct 6, 2026 at 3:14 PM Moo Sella\n<moosella4@gmail.com> wrote:\n> old text"
        XCTAssertEqual(QuoteStripper.strip(text), "Sounds good!")
    }

    func testStripsSignatureAndOutlookBlock() {
        XCTAssertEqual(QuoteStripper.strip("Yes\n-- \nJade\nCEO"), "Yes")
        XCTAssertEqual(QuoteStripper.strip("Yes\n\nFrom: Bob\nSent: Monday\nTo: Jade\n\nold"), "Yes")
    }

    func testKeepsInlineRepliesBetweenQuotes() {
        XCTAssertEqual(QuoteStripper.strip("> question?\nanswer\n> other"), "> question?\nanswer")
    }

    func testNeverReturnsBlank() {
        XCTAssertEqual(QuoteStripper.strip("> only a quote"), "> only a quote")
    }

    func testHTMLDropsQuoteAndDecodesEntities() {
        let html = "<html><head><style>p{}</style></head><div>Tom &amp; Jerry&#39;s<br>next</div><div class=\"gmail_quote\">old</div></html>"
        XCTAssertEqual(HTMLText.plain(html, dropQuotes: true), "Tom & Jerry's\nnext")
    }

    func testTimelineExcludesPromotionsAndSocial() {
        XCTAssertTrue(thread([message()]).inTimeline)
        XCTAssertFalse(thread([message(labels: ["INBOX", "CATEGORY_PROMOTIONS"])]).inTimeline)
        XCTAssertFalse(thread([message(labels: ["INBOX", "CATEGORY_SOCIAL"])]).inTimeline)
        XCTAssertFalse(thread([message(labels: ["SENT"])]).inTimeline)
    }

    func testPersonChannelMatchesCcEvenInPromotions() {
        var channel = Channel(kind: .person, name: "moo")
        channel.addresses = ["moosella4@gmail.com"]
        let cc = message(cc: ["moosella4@gmail.com"], labels: ["CATEGORY_PROMOTIONS"])
        XCTAssertTrue(thread([cc]).belongs(to: channel))
        XCTAssertFalse(thread([message()]).belongs(to: channel))
        XCTAssertFalse(thread([message(cc: ["moosella4@gmail.com"], labels: ["TRASH"])]).belongs(to: channel))
    }

    func testNewActivityIgnoresOwnAndReadMessages() {
        let checked = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)
        XCTAssertTrue(thread([message(labels: ["UNREAD"], date: later)]).hasNewActivity(since: checked))
        XCTAssertFalse(thread([message(labels: [], date: later)]).hasNewActivity(since: checked))
        XCTAssertFalse(thread([message(labels: ["UNREAD", "SENT"], date: later)]).hasNewActivity(since: checked))
        XCTAssertFalse(thread([message(labels: ["UNREAD"], date: checked)]).hasNewActivity(since: checked))
    }

    func testReplyAllExcludesSelfAndKeepsCc() {
        let original = message(from: "a@x.com", to: ["me@gmail.com", "b@x.com"], cc: ["c@x.com"])
        let draft = Draft.reply(to: thread([original]), account: "me@gmail.com")
        XCTAssertEqual(draft.to, "a@x.com, b@x.com")
        XCTAssertEqual(draft.cc, "c@x.com")
        XCTAssertEqual(draft.subject, "Re: Plans")
        XCTAssertEqual(draft.inReplyTo, "<m1@mail>")
        XCTAssertTrue(draft.quoted.contains("> hi"))
    }

    func testReplyToOwnMessageGoesToOriginalRecipients() {
        let mine = message(from: "me@gmail.com", to: ["a@x.com"], labels: ["SENT"])
        XCTAssertEqual(Draft.reply(to: thread([mine]), account: "me@gmail.com").to, "a@x.com")
    }

    func testNewRecipientsAreDetected() {
        var draft = Draft.reply(to: thread([message(to: ["me@gmail.com"])]), account: "me@gmail.com")
        draft.cc = "new@x.com"
        XCTAssertEqual(draft.newRecipients(comparedTo: thread([message(to: ["me@gmail.com"])])).map(\.email), ["new@x.com"])
    }

    func testMIMEPreventsHeaderInjection() {
        let draft = Draft(to: "a@x.com", subject: "Hi\r\nBcc: evil@x.com", body: "body")
        let raw = String(decoding: MIMEBuilder.build(draft, from: "me@gmail.com"), as: UTF8.self)
        XCTAssertFalse(raw.contains("\r\nBcc:"))
    }

    func testMIMEWithAttachmentRoundTrips() {
        let bytes = Data((0..<1000).map { UInt8($0 % 256) })
        var draft = Draft(to: "a@x.com", cc: "b@x.com", subject: "Résumé", body: "héllo")
        draft.attachments = [OutgoingAttachment(filename: "café.bin", mimeType: "application/octet-stream", data: bytes)]
        let raw = String(decoding: MIMEBuilder.build(draft, from: "me@gmail.com", boundary: "BOUND"), as: UTF8.self)

        XCTAssertTrue(raw.contains("Cc: b@x.com\r\n"))
        XCTAssertTrue(raw.contains("Subject: =?UTF-8?B?"))
        XCTAssertTrue(raw.contains("filename*=UTF-8''caf%C3%A9.bin"))
        XCTAssertTrue(raw.contains("multipart/mixed; boundary=\"BOUND\""))
        XCTAssertTrue(raw.hasSuffix("--BOUND--\r\n"))

        let parts = raw.components(separatedBy: "--BOUND")
        XCTAssertEqual(parts.count, 4)
        let encoded = parts[2].components(separatedBy: "\r\n\r\n")[1]
        XCTAssertEqual(Data(base64Encoded: encoded, options: .ignoreUnknownCharacters), bytes)
    }

    func testParsesNestedMultipartWithAttachment() throws {
        let json = """
        {"id":"t","historyId":"9","snippet":"a &amp; b","messages":[{"id":"m","threadId":"t","labelIds":["INBOX","UNREAD"],
        "internalDate":"1700000000000","payload":{"mimeType":"multipart/mixed","headers":[
        {"name":"From","value":"Moo <moosella4@gmail.com>"},{"name":"To","value":"me@gmail.com"},
        {"name":"Subject","value":"Trip"},{"name":"Message-ID","value":"<abc@mail>"}],
        "parts":[{"partId":"0","mimeType":"multipart/alternative","parts":[
        {"partId":"0.0","mimeType":"text/plain","body":{"data":"SGV5IQoKT24gTW9uLCBCb2Igd3JvdGU6Cj4gb2xk"}}]},
        {"partId":"1","mimeType":"application/pdf","filename":"map.pdf","body":{"attachmentId":"att","size":2048}}]}}]}
        """
        let thread = GmailParser.thread(try JSONDecoder().decode(ThreadPayload.self, from: Data(json.utf8)))
        let message = try XCTUnwrap(thread.messages.first)
        XCTAssertEqual(thread.snippet, "a & b")
        XCTAssertEqual(message.from, Address(name: "Moo", email: "moosella4@gmail.com"))
        XCTAssertEqual(message.chatText, "Hey!")
        XCTAssertEqual(message.attachments.map(\.filename), ["map.pdf"])
        XCTAssertTrue(message.isUnread)
    }

    func testQuotaErrorsAreRateLimits() {
        let quota = Data(#"{"error":{"message":"Quota exceeded for quota metric 'Total Query Cost'","errors":[{"reason":"rateLimitExceeded"}]}}"#.utf8)
        let denied = Data(#"{"error":{"message":"Insufficient Permission","errors":[{"reason":"insufficientPermissions"}]}}"#.utf8)
        XCTAssertTrue(GmailAPI.isRateLimit(status: 403, body: quota))
        XCTAssertTrue(GmailAPI.isRateLimit(status: 429, body: Data()))
        XCTAssertFalse(GmailAPI.isRateLimit(status: 403, body: denied))
    }

    func testChannelQueryCoversFromToAndCc() {
        var channel = Channel(kind: .person, name: "moo")
        channel.addresses = ["m@x.com"]
        XCTAssertEqual(channel.gmailQuery, "from:m@x.com OR to:m@x.com OR cc:m@x.com")
    }
}
