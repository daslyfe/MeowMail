import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Group {
            if store.accounts.isEmpty {
                SetupView()
            } else {
                #if os(macOS)
                DesktopLayout()
                #else
                PhoneLayout()
                #endif
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct SetupView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 18) {
            Text("meowmail").font(Theme.serif(48))
            Text("Paste the iOS OAuth client ID from Google Cloud, then connect your first Gmail account.")
                .font(Theme.thin(16))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
            TextField("123456-abc.apps.googleusercontent.com", text: $store.clientID)
                .textFieldStyle(.plain)
                .font(Theme.typewriter(14))
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    Line().stroke(Theme.ink, style: StrokeStyle(lineWidth: 1, dash: [1, 2])).frame(height: 1)
                }
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button("connect gmail") {
                store.clientID = store.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { await store.addAccount() }
            }
            .buttonStyle(SilverButtonStyle())
            .disabled(GoogleSignIn.redirectScheme(for: store.clientID.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
        }
        .padding(24)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.content)
    }
}

#if os(macOS)
struct DesktopLayout: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            AccountRail()
            ChannelSidebar { store.openWithLatest(channel: $0) }
                .frame(width: 230)
            if let channel = store.selectedChannel {
                ThreadList(channel: channel) { store.open(thread: $0) }
                    .frame(width: 320)
            }
            DashedRule(axis: .vertical)
            if let id = store.selectedThreadID, let thread = store.thread(id) {
                ChatView(thread: thread).id(id)
            } else {
                Text("pick a thread")
                    .font(Theme.serif(22))
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.content)
            }
        }
    }
}
#else
struct PhoneLayout: View {
    @Environment(AppStore.self) private var store
    @State private var path: [Route] = []

    enum Route: Hashable {
        case channel(String)
        case thread(String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            HStack(spacing: 0) {
                AccountRail()
                ChannelSidebar { id in
                    store.open(channel: id)
                    path.append(.channel(id))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if store.isDemo, path.isEmpty, let id = store.selectedThreadID {
                    path = [.thread(id)]
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .channel(let id):
                    if let channel = store.selectedAccount?.channels.first(where: { $0.id == id }) {
                        ThreadList(channel: channel) { threadID in
                            store.open(thread: threadID)
                            path.append(.thread(threadID))
                        }
                        .navigationTitle("# \(channel.name)")
                        .navigationBarTitleDisplayMode(.inline)
                    }
                case .thread(let id):
                    if let thread = store.thread(id) {
                        ChatView(thread: thread)
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
        }
    }
}
#endif
