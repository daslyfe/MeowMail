import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(AppStore.self) private var store
    var thread: MailThread
    @State private var draft = Draft()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(thread.messages.enumerated()), id: \.element.id) { index, message in
                            MessageRow(message: message, grouped: isGrouped(index))
                                .id(message.id)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onAppear { proxy.scrollTo(thread.messages.last?.id, anchor: .bottom) }
                .onChange(of: thread.messages.count) {
                    proxy.scrollTo(thread.messages.last?.id, anchor: .bottom)
                }
            }
            Composer(draft: $draft, thread: thread)
        }
        .background(Theme.content)
        .onAppear { resetDraft() }
        .onChange(of: thread.messages.count) { resetDraftIfEmpty() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(thread.subject).font(.headline).lineLimit(2)
            Text("\(thread.participants.count) people · \(thread.messages.count) messages")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func isGrouped(_ index: Int) -> Bool {
        guard index > 0 else { return false }
        let previous = thread.messages[index - 1]
        let current = thread.messages[index]
        return previous.from.email == current.from.email
            && current.date.timeIntervalSince(previous.date) < 600
            && previous.to == current.to
            && previous.cc == current.cc
    }

    private func resetDraft() {
        draft = .reply(to: thread, account: store.selectedEmail ?? "")
    }

    private func resetDraftIfEmpty() {
        if draft.body.isEmpty && draft.attachments.isEmpty { resetDraft() }
    }
}

private struct MessageRow: View {
    @Environment(AppStore.self) private var store
    var message: Message
    var grouped: Bool
    @State private var showOriginal = false
    @State private var previewURL: URL?
    @State private var loadingAttachment: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if grouped {
                Color.clear.frame(width: 40, height: 1)
            } else {
                Avatar(address: message.from)
            }
            VStack(alignment: .leading, spacing: 4) {
                if !grouped { heading }
                content
                if !message.attachments.isEmpty { attachmentChips }
                if canToggle {
                    Button(showOriginal ? "Hide original" : "Show original") { showOriginal.toggle() }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, grouped ? 2 : 12)
        .quickLookPreview($previewURL)
    }

    private var canToggle: Bool { !message.isRichLayout && message.fullText != message.chatText }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(message.isFromMe ? "You" : message.from.display)
                    .fontWeight(.semibold)
                    .foregroundStyle(message.isFromMe ? Theme.accent : Theme.color(for: message.from.email))
                Text(message.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
            Text(recipients).font(.caption2).foregroundStyle(Theme.muted).lineLimit(2)
        }
    }

    private var recipients: String {
        let to = message.to.map(\.firstName).joined(separator: ", ")
        let cc = message.cc.map(\.firstName).joined(separator: ", ")
        return cc.isEmpty ? "to \(to)" : "to \(to) · cc \(cc)"
    }

    @ViewBuilder private var content: some View {
        if message.isRichLayout, let html = message.html {
            HTMLMessageView(html: html)
        } else {
            Text(LinkedText.make(showOriginal ? message.fullText : message.chatText))
                .textSelection(.enabled)
        }
    }

    private var attachmentChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(message.attachments) { attachment in
                Button {
                    Task {
                        loadingAttachment = attachment.id
                        previewURL = await store.download(attachment: attachment, messageID: message.id)
                        loadingAttachment = nil
                    }
                } label: {
                    HStack(spacing: 8) {
                        if loadingAttachment == attachment.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "doc.fill")
                        }
                        VStack(alignment: .leading) {
                            Text(attachment.filename).lineLimit(1)
                            Text(attachment.sizeText).font(.caption2).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(10)
                    .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }
}

enum LinkedText {
    /// Makes web addresses in plain text tappable.
    static func make(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return result }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, let range = Range(match.range, in: text),
                  let start = AttributedString.Index(range.lowerBound, within: result),
                  let end = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[start..<end].link = url
        }
        return result
    }
}

struct Composer: View {
    @Environment(AppStore.self) private var store
    @Binding var draft: Draft
    var thread: MailThread?
    var onSent: () -> Void = {}

    @State private var showRecipients = false
    @State private var showFiles = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var isSending = false
    @State private var confirmNewPeople = false

    private var isTooLarge: Bool { draft.attachmentBytes > Draft.attachmentLimit }

    private var canSend: Bool {
        !isSending && !isTooLarge && !draft.toAddresses.isEmpty
            && !(draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.attachments.isEmpty)
    }

    private var newPeople: [Address] {
        guard let thread else { return [] }
        return draft.newRecipients(comparedTo: thread)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if thread != nil {
                Button {
                    showRecipients.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showRecipients ? "chevron.down" : "chevron.right")
                        Text(summary).lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit recipients")
            }
            if showRecipients || thread == nil {
                recipientField("To", text: $draft.to)
                recipientField("Cc", text: $draft.cc)
            }
            if !draft.attachments.isEmpty { pendingAttachments }
            if isTooLarge {
                Text("Attachments are over Gmail's 25 MB limit.")
                    .font(.caption)
                    .foregroundStyle(Theme.unread)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button { showFiles = true } label: { Image(systemName: "paperclip") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Attach file")

                PhotosPicker(selection: $photos, matching: .images) {
                    Image(systemName: "photo")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attach photo")

                TextField(thread == nil ? "Write your email" : "Reply", text: $draft.body, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .padding(8)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 8))

                Button {
                    if newPeople.isEmpty { send() } else { confirmNewPeople = true }
                } label: {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSend ? Theme.accent : Theme.muted)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(12)
        .background(Theme.sidebar)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls { addFile(url) }
        }
        .onChange(of: photos) { _, items in
            Task { await addPhotos(items) }
        }
        .confirmationDialog("Add \(newPeople.map(\.email).joined(separator: ", "))?",
                            isPresented: $confirmNewPeople, titleVisibility: .visible) {
            Button("Send") { send() }
        } message: {
            Text("They'll be able to read the earlier messages quoted in this reply.")
        }
    }

    private var summary: String {
        let people = (draft.toAddresses + draft.ccAddresses).map(\.firstName).joined(separator: ", ")
        return "Reply to \(people)"
    }

    private func recipientField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(Theme.muted).frame(width: 24, alignment: .leading)
            TextField("name@example.com, …", text: text)
                .textFieldStyle(.plain)
                .font(.callout)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
        }
    }

    private var pendingAttachments: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(draft.attachments) { attachment in
                    HStack(spacing: 4) {
                        Text(attachment.filename).font(.caption).lineLimit(1)
                        Button {
                            draft.attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(attachment.filename)")
                    }
                    .padding(6)
                    .background(Theme.field, in: Capsule())
                }
            }
        }
    }

    private func addFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            store.errorMessage = "Couldn't read \(url.lastPathComponent)."
            return
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        draft.attachments.append(OutgoingAttachment(filename: url.lastPathComponent, mimeType: mime, data: data))
    }

    private func addPhotos(_ items: [PhotosPickerItem]) async {
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let type = item.supportedContentTypes.first ?? .jpeg
            let suffix = type.preferredFilenameExtension ?? "jpg"
            draft.attachments.append(OutgoingAttachment(filename: "photo-\(index + 1).\(suffix)",
                                                        mimeType: type.preferredMIMEType ?? "image/jpeg",
                                                        data: data))
        }
        photos = []
    }

    private func send() {
        isSending = true
        let outgoing = draft
        Task {
            let sent = await store.send(outgoing)
            isSending = false
            guard sent else { return }
            draft.body = ""
            draft.attachments = []
            if let thread {
                draft = .reply(to: store.thread(thread.id) ?? thread, account: store.selectedEmail ?? "")
            }
            onSent()
        }
    }
}

struct NewEmailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Draft()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Subject", text: $draft.subject)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .padding(12)
                Divider()
                Spacer()
                Composer(draft: $draft, thread: nil) { dismiss() }
            }
            .background(Theme.content)
            .navigationTitle("New email")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 420)
        #endif
    }
}
