import SwiftUI

struct ServerProxyDraft {
    var enabled: Bool
    var host: String
    var port: String
    var username: String
    var password: String

    init(_ proxy: ServerProxy? = nil) {
        enabled = proxy != nil
        host = proxy?.host ?? ""
        port = proxy.map { String($0.port) } ?? ""
        username = proxy?.username ?? ""
        password = proxy?.password ?? ""
    }

    func value() throws -> ServerProxy? {
        guard enabled else { return nil }
        return try ServerProxy(host: host, port: port, username: username, password: password)
    }
}

struct ServerProxyFields: View {
    @Binding var draft: ServerProxyDraft
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Proxy", selection: $draft.enabled) {
                Text("System Settings").tag(false)
                Text(verbatim: "HTTP CONNECT").tag(true)
            }
            if draft.enabled {
                HStack {
                    TextField("Proxy Host", text: $draft.host, prompt: Text(verbatim: "127.0.0.1"))
                        .accessibilityLabel("Proxy Host")
                    TextField("Port", text: $draft.port, prompt: Text("Port"))
                        .accessibilityLabel("Proxy Port")
                        .frame(width: 80)
                }
                TextField("Proxy Username (Optional)", text: $draft.username)
                    .textContentType(.username)
                SecureField("Proxy Password (Optional)", text: $draft.password)
                    .textContentType(.password)
            }
        }
        .textFieldStyle(.roundedBorder)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: draft.enabled)
    }
}

struct ServerProxySettings: View {
    let entry: AccountVault.Entry
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ServerProxyDraft?
    @State private var operation = AccountOperation()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Server Proxy").font(.headline)
            Text(entry.account.serverURL.absoluteString).foregroundStyle(.secondary).textSelection(.enabled)

            if let fields = Binding($draft) {
                ServerProxyFields(draft: fields)
                if fields.wrappedValue.enabled {
                    Text("Finder access is paused while this server uses an HTTP CONNECT proxy.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            AccountOperationStatus(operation: operation)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    operation.run {
                        try await app.updateProxy(try draft?.value(), for: entry)
                        dismiss()
                    }
                }.keyboardShortcut(.defaultAction)
                    .disabled(draft == nil || app.switching)
            }
        }
        .disabled(operation.busy)
        .padding(24)
        .frame(width: 420)
        .task {
            do { draft = ServerProxyDraft(try AccountVault.loadProxies()[ServerProxy.serverKey(entry.account.serverURL)]) }
            catch { operation.error = error.localizedDescription }
        }
    }
}
