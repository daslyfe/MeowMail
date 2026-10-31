import SwiftUI

struct AccountRail: View {
    @Environment(AppStore.self) private var store
    @State private var confirmRemove: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(store.accounts) { account in
                    Button { store.select(account: account.email) } label: { icon(account) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(account.email)
                        .contextMenu {
                            Button("Remove account", role: .destructive) { confirmRemove = account.email }
                        }
                }
                Button { Task { await store.addAccount() } } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                        .frame(width: 48, height: 48)
                        .background(Theme.sidebar, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Gmail account")
            }
            .padding(.vertical, 12)
        }
        .frame(width: 72)
        .background(Theme.rail)
        .confirmationDialog("Remove this account from meowmail?", isPresented: Binding(
            get: { confirmRemove != nil },
            set: { if !$0 { confirmRemove = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let confirmRemove { store.removeAccount(confirmRemove) }
            }
        } message: {
            Text("Your Gmail isn't changed, but this device's channels and pins for it are deleted.")
        }
    }

    private func icon(_ account: Account) -> some View {
        let selected = account.email == store.selectedEmail
        return RoundedRectangle(cornerRadius: selected ? 16 : 24)
            .fill(Theme.color(for: account.email))
            .frame(width: 48, height: 48)
            .overlay {
                Text(account.email.prefix(1).uppercased())
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }
            .overlay(alignment: .bottomTrailing) {
                if account.needsReconnect {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.yellow)
                } else if store.hasNewThreads(account) {
                    Circle()
                        .fill(Theme.unread)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Theme.rail, lineWidth: 3))
                }
            }
    }
}

struct ChannelSidebar: View {
    @Environment(AppStore.self) private var store
    @State private var editing: Channel?
    @State private var composing = false
    var onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let account = store.selectedAccount {
                HStack {
                    Text(account.email)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Button { composing = true } label: { Image(systemName: "square.and.pencil") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New email")
                }
                .padding(14)
                Divider()

                if account.needsReconnect {
                    Button("Reconnect this account") { Task { await store.addAccount() } }
                        .padding(12)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(account.channels.filter { $0.kind == .all }) { row($0, account: account) }
                        HStack {
                            Text("PEOPLE").font(.caption.bold()).foregroundStyle(Theme.muted)
                            Spacer()
                            Button { editing = Channel(kind: .person, name: "") } label: { Image(systemName: "plus") }
                                .buttonStyle(.plain)
                                .accessibilityLabel("New channel")
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                        ForEach(account.channels.filter { $0.kind == .person }) { row($0, account: account) }
                    }
                    .padding(8)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sidebar)
        .sheet(item: $editing) { ChannelEditor(channel: $0) }
        .sheet(isPresented: $composing) { NewEmailView() }
    }

    private func row(_ channel: Channel, account: Account) -> some View {
        let count = store.newCount(channel, account: account.email)
        let selected = channel.id == store.selectedChannelID
        return Button { onSelect(channel.id) } label: {
            HStack(spacing: 8) {
                Text("#").foregroundStyle(Theme.muted)
                Text(channel.name)
                    .fontWeight(count > 0 ? .semibold : .regular)
                    .lineLimit(1)
                Spacer()
                if count > 0 { CountBadge(count: count) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(selected ? Theme.field : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if channel.kind == .person {
                Button("Edit channel") { editing = channel }
                Button("Delete channel", role: .destructive) { store.deleteChannel(channel.id) }
            }
        }
    }
}

struct ChannelEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var channel: Channel
    @State private var addressText = ""
    @State private var filter = ""

    private var parsed: Set<String> { Set(Address.parseList(addressText).map(\.email)) }

    private var suggestions: [Address] {
        store.knownContacts
            .filter { !parsed.contains($0.email) }
            .filter { filter.isEmpty || $0.display.localizedCaseInsensitiveContains(filter) || $0.email.contains(filter.lowercased()) }
            .prefix(30)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Channel name", text: $channel.name)
                    .autocorrectionDisabled()
                Section("Email addresses") {
                    TextField("moosella4@gmail.com, other@example.com", text: $addressText, axis: .vertical)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                }
                Section("People you've emailed") {
                    TextField("Filter", text: $filter)
                    ForEach(suggestions, id: \.email) { person in
                        Button {
                            addressText = (Array(parsed).sorted() + [person.email]).joined(separator: ", ")
                            if channel.name.isEmpty { channel.name = person.firstName.lowercased() }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(person.display)
                                Text(person.email).font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(channel.name.isEmpty ? "New channel" : channel.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        channel.addresses = parsed
                        store.saveChannel(channel)
                        dismiss()
                    }
                    .disabled(channel.name.trimmingCharacters(in: .whitespaces).isEmpty || parsed.isEmpty)
                }
            }
        }
        .onAppear { addressText = channel.addresses.sorted().joined(separator: ", ") }
        #if os(macOS)
        .frame(width: 440, height: 520)
        #endif
    }
}

struct ThreadList: View {
    @Environment(AppStore.self) private var store
    var channel: Channel
    var onOpen: (String) -> Void
    @State private var query = ""

    private var account: String { store.selectedEmail ?? "" }

    private var rows: [MailThread] {
        if let ids = store.searchResults {
            return ids.compactMap(store.thread)
        }
        return store.threads(in: channel, account: account)
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            HStack {
                Text("# \(channel.name)").font(.headline)
                Spacer()
                if store.isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Button { Task { await store.sync() } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain)
                        .keyboardShortcut("r")
                        .help("Refresh")
                }
            }
            .padding(14)
            #endif
            TextField("Search Gmail", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .onSubmit { Task { await store.search(query) } }
                .onChange(of: query) { _, value in
                    if value.isEmpty { store.searchResults = nil }
                }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(rows) { row($0) }
                }
                .padding(8)
            }
            .refreshable { await store.sync() }
            .overlay {
                if rows.isEmpty {
                    Text(store.isSyncing ? "Loading…" : "No threads here yet")
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.content)
    }

    private func row(_ thread: MailThread) -> some View {
        let pinned = channel.pinned.contains(thread.id)
        let selected = thread.id == store.selectedThreadID
        return Button { onOpen(thread.id) } label: {
            HStack(alignment: .top, spacing: 10) {
                Avatar(address: thread.messages.last?.from ?? Address(email: "?"), size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if pinned {
                            Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Theme.accent)
                        }
                        Text(thread.subject)
                            .fontWeight(thread.isUnread ? .bold : .regular)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(thread.lastDate.chatStamp).font(.caption2).foregroundStyle(Theme.muted)
                    }
                    Text(senders(thread)).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                    HStack(spacing: 4) {
                        if thread.attachmentCount > 0 {
                            Image(systemName: "paperclip").font(.caption2).foregroundStyle(Theme.muted)
                        }
                        Text(thread.snippet).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                if thread.isUnread {
                    Circle().fill(Theme.unread).frame(width: 8, height: 8).padding(.top, 5)
                }
            }
            .padding(8)
            .background(selected ? Theme.field : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(pinned ? "Unpin" : "Pin to top of channel") {
                store.togglePin(thread: thread.id, channel: channel.id)
            }
        }
        .swipeActions {
            Button(pinned ? "Unpin" : "Pin") { store.togglePin(thread: thread.id, channel: channel.id) }
        }
    }

    private func senders(_ thread: MailThread) -> String {
        var names: [String] = []
        for message in thread.messages {
            let name = message.isFromMe ? "You" : message.from.firstName
            if !names.contains(name) { names.append(name) }
        }
        return names.joined(separator: ", ")
    }
}
