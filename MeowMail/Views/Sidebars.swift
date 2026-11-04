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
                    Text("+")
                        .font(Theme.display(24))
                        .foregroundStyle(Theme.faint)
                        .frame(width: 44, height: 44)
                        .overlay(Rectangle().stroke(Theme.ink, style: StrokeStyle(lineWidth: 0.5, dash: [3, 2])))
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
        return Rectangle()
            .fill(Theme.color(for: account.email))
            .frame(width: 44, height: 44)
            .overlay(Rectangle().stroke(Theme.ink, lineWidth: selected ? 2 : 1))
            .shadow(color: selected ? Theme.ink : .clear, radius: 0, x: 2, y: 2)
            .overlay {
                Text(account.email.prefix(1).uppercased())
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.ink)
            }
            .overlay(alignment: .topTrailing) {
                if account.needsReconnect {
                    Text("!").font(Theme.display(12)).foregroundStyle(.white)
                        .frame(width: 14, height: 14).background(Theme.alert)
                        .offset(x: 5, y: -5)
                } else if store.hasNewThreads(account) {
                    Rectangle().fill(Theme.unread).frame(width: 10, height: 10)
                        .offset(x: 4, y: -4)
                }
            }
    }
}

struct ChannelSidebar: View {
    @Environment(AppStore.self) private var store
    @State private var editing: Channel?
    @State private var composing = false
    @State private var dropTargeted = false
    @State private var hovered: String?
    @State private var rowDropTarget: String?
    @State private var renaming: Channel?
    @State private var renameText = ""
    var onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let account = store.selectedAccount {
                HStack(alignment: .firstTextBaseline) {
                    Text(account.email)
                        .font(Theme.serif(17))
                        .lineLimit(1)
                    Spacer()
                    Button { composing = true } label: { Text("new") }
                        .buttonStyle(SilverButtonStyle())
                        .accessibilityLabel("New email")
                }
                .padding(14)
                DashedRule()

                if account.needsReconnect {
                    Button("Reconnect this account") { Task { await store.addAccount() } }
                        .padding(12)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(account.channels.filter { $0.kind == .all }) { row($0, account: account) }
                        followedSection(account)
                        HStack(alignment: .firstTextBaseline) {
                            sectionTitle("people")
                            Spacer()
                            Button { editing = Channel(kind: .person, name: "") } label: {
                                Text("+").font(Theme.display(20)).foregroundStyle(Theme.faint)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("New channel")
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 18)
                        .padding(.bottom, 4)
                        ForEach(account.channels.filter { $0.kind == .person }) { row($0, account: account) }
                    }
                    .padding(8)
                }
                .dropDestination(for: String.self) { ids, _ in
                    ids.forEach(store.followThread)
                    return !ids.isEmpty
                } isTargeted: { dropTargeted = $0 }
                .overlay {
                    if dropTargeted {
                        Rectangle()
                            .stroke(Theme.ink, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .padding(4)
                            .allowsHitTesting(false)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) { PixelStrip().offset(x: 7) }
        .zIndex(1)
        .sheet(item: $editing) { ChannelEditor(channel: $0) }
        .sheet(isPresented: $composing) { NewEmailView() }
        .alert("Rename channel", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Channel name", text: $renameText)
            Button("Rename") {
                if let renaming { store.renameChannel(renaming.id, to: renameText) }
                renaming = nil
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    /// On a Mac the close button appears on hover; touch screens use the long-press menu.
    private func showsClose(_ channel: Channel) -> Bool {
        #if os(macOS)
        return channel.kind == .thread && hovered == channel.id
        #else
        return false
        #endif
    }

    private func unfollow(_ channel: Channel) {
        if hovered == channel.id { hovered = nil }
        store.deleteChannel(channel.id)
    }

    @ViewBuilder
    private func followedSection(_ account: Account) -> some View {
        let followed = account.channels.filter { $0.kind == .thread }
        sectionTitle("following")
            .padding(.horizontal, 10)
            .padding(.top, 18)
            .padding(.bottom, 4)
        if followed.isEmpty {
            Text("drag a thread here to follow it")
                .font(Theme.thin(13))
                .foregroundStyle(Theme.faint)
                .padding(.horizontal, 10)
        }
        ForEach(followed) { channel in
            // Dropping onto a followed channel adds the thread to it instead of making a new channel.
            row(channel, account: account)
                .overlay {
                    if rowDropTarget == channel.id {
                        Rectangle().stroke(Theme.ink, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }
                }
                .dropDestination(for: String.self) { ids, _ in
                    ids.forEach { store.addThread($0, toChannel: channel.id) }
                    return !ids.isEmpty
                } isTargeted: { inside in
                    if inside { rowDropTarget = channel.id } else if rowDropTarget == channel.id { rowDropTarget = nil }
                }
        }
    }

    /// Lowercase bold section titles, like the dashboard's groups.
    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(Theme.display(17)).tracking(0.3).foregroundStyle(Theme.ink)
    }

    private func row(_ channel: Channel, account: Account) -> some View {
        let count = store.newCount(channel, account: account.email)
        let selected = channel.id == store.selectedChannelID
        return Button { onSelect(channel.id) } label: {
            HStack(spacing: 6) {
                Text("#").font(Theme.thin(15)).foregroundStyle(Theme.faint)
                Text(channel.name)
                    .font(Theme.serif(16, bold: count > 0))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    // Followed and people channels each get their own highlighter color; all-mail stays plain.
                    .background(alignment: .bottom) {
                        if channel.kind != .all {
                            Theme.color(for: channel.id).frame(height: 6).offset(y: -1)
                        }
                    }
                Spacer()
                if count > 0 { CountBadge(count: count) }
                if showsClose(channel) { Color.clear.frame(width: 14, height: 1) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(selected ? Theme.paper : .clear)
            .overlay(Rectangle().stroke(selected ? Theme.ink : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if showsClose(channel) {
                Button { unfollow(channel) } label: {
                    Text("×").font(Theme.serif(18))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.faint)
                .padding(.trailing, 10)
                .help("Done with this thread")
                .accessibilityLabel("Stop following \(channel.name)")
            }
        }
        .onHover { inside in
            if inside { hovered = channel.id } else if hovered == channel.id { hovered = nil }
        }
        .contextMenu {
            Button("Rename channel…") {
                renameText = channel.name
                renaming = channel
            }
            if channel.kind == .thread {
                Button("Done with this thread") { unfollow(channel) }
            }
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
            HStack(alignment: .firstTextBaseline) {
                Text("# \(channel.name)").font(Theme.display(20)).tracking(0.3).lineLimit(1)
                Spacer()
                if store.isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Button { Task { await store.sync() } } label: { Text("↻").font(Theme.serif(18)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.faint)
                        .keyboardShortcut("r")
                        .help("Refresh")
                }
            }
            .padding(14)
            #endif
            TextField("search gmail", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.typewriter(14))
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    Line().stroke(Theme.ink, style: StrokeStyle(lineWidth: 1, dash: [1, 2])).frame(height: 1)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .onSubmit { Task { await store.search(query) } }
                .onChange(of: query) { _, value in
                    if value.isEmpty { store.searchResults = nil }
                }
            DashedRule()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { thread in
                        row(thread)
                        DashedRule().padding(.horizontal, 8).opacity(0.5)
                    }
                }
                .padding(.vertical, 4)
            }
            .refreshable { await store.sync() }
            .overlay {
                if rows.isEmpty {
                    Text(store.isSyncing ? "loading…" : "no threads here yet")
                        .font(Theme.thin(14))
                        .foregroundStyle(Theme.faint)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.content)
    }

    private func row(_ thread: MailThread) -> some View {
        let pinned = channel.pinned.contains(thread.id)
        let selected = thread.id == store.selectedThreadID
        // A plain view instead of a Button: on macOS a Button swallows the mouse-down, so dragging never starts.
        return HStack(alignment: .top, spacing: 10) {
                Avatar(address: thread.messages.last?.from ?? Address(email: "?"), size: 32,
                       colorful: store.isColorful(thread, in: channel))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if pinned {
                            Text("📌").font(.system(size: 10))
                        }
                        Text(thread.subject)
                            .font(Theme.serif(16, bold: thread.isUnread))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(thread.lastDate.chatStamp).font(Theme.thin(12)).foregroundStyle(Theme.muted)
                    }
                    Text(senders(thread)).font(Theme.thin(13)).foregroundStyle(Theme.muted).lineLimit(1)
                    HStack(spacing: 4) {
                        if thread.attachmentCount > 0 {
                            Image(systemName: "paperclip").font(.system(size: 10)).foregroundStyle(Theme.faint)
                        }
                        Text(thread.snippet).font(Theme.thin(13)).foregroundStyle(Theme.faint).lineLimit(1)
                    }
                }
                if thread.isUnread {
                    Rectangle().fill(Theme.unread).frame(width: 6, height: 6).padding(.top, 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selected ? Theme.paper : .clear)
            .overlay(Rectangle().stroke(selected ? Theme.ink : .clear, lineWidth: 1))
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture { onOpen(thread.id) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen(thread.id) }
        .draggable(thread.id) {
            Text("# \(thread.subject)")
                .font(Theme.serif(15))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.content)
                .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
        }
        .contextMenu {
            Button(pinned ? "Unpin" : "Pin to top of channel") {
                store.togglePin(thread: thread.id, channel: channel.id)
            }
            if channel.kind == .thread {
                Button("Remove from this channel") { store.removeThread(thread.id, fromChannel: channel.id) }
            } else {
                Button("Give this thread its own channel") { store.followThread(thread.id) }
            }
            let others = (store.selectedAccount?.channels ?? [])
                .filter { $0.kind == .thread && $0.id != channel.id && !$0.followed.contains(thread.id) }
            if !others.isEmpty {
                Menu("Add to channel") {
                    ForEach(others) { other in
                        Button("# \(other.name)") { store.addThread(thread.id, toChannel: other.id) }
                    }
                }
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
