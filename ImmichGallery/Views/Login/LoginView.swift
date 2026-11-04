import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var app

    private enum Step { case server, credentials(ImmichClient, ServerFeatures, ServerVersion?) }
    private enum Method: String, CaseIterable { case password = "Email & Password", apiKey = "API Key" }

    @State private var step = Step.server
    @State private var serverText = AccountStore.lastServer ?? ""
    @State private var email = ""
    @State private var password = ""
    @State private var apiKey = ""
    @State private var method = Method.password
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focused: Field?

    private enum Field { case server, email, password, apiKey }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                Text("Immich Gallery")
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Group {
                switch step {
                case .server: serverForm
                case .credentials(let client, let features, let version):
                    credentialsForm(client: client, features: features, version: version)
                }
            }
            .frame(width: 340)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(isWorking)
        .onAppear { focused = .server }
    }

    private var subtitle: String {
        switch step {
        case .server: String(localized: "Enter the address of your Immich server.")
        case .credentials(let client, _, _): String(localized: "Sign in to \(client.serverURL.host() ?? client.serverURL.absoluteString)")
        }
    }

    private var serverForm: some View {
        VStack(spacing: 14) {
            TextField("Server", text: $serverText, prompt: Text("https://photos.example.com"))
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($focused, equals: .server)
                .onSubmit(connect)
            primaryButton("Continue", action: connect)
                .disabled(serverText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func credentialsForm(client: ImmichClient, features: ServerFeatures, version: ServerVersion?) -> some View {
        VStack(spacing: 14) {
            if features.passwordLogin {
                Picker("Method", selection: $method) {
                    ForEach(Method.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if method == .password && features.passwordLogin {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .focused($focused, equals: .email)
                    .onSubmit { focused = .password }
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focused, equals: .password)
                    .onSubmit { signIn(client) }
            } else {
                SecureField("API Key", text: $apiKey)
                    .focused($focused, equals: .apiKey)
                    .onSubmit { signIn(client) }
                Text("Create an API key in Immich under Account Settings → API Keys. Useful if your server uses OAuth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            primaryButton("Sign In") { signIn(client) }

            HStack {
                Button("Change Server") {
                    errorMessage = nil
                    step = .server
                }
                .buttonStyle(.link)
                Spacer()
                if let version {
                    Text("Immich \(version.description)")
                        .foregroundStyle(version.isSupported ? Color.secondary : Color.orange)
                        .help(version.isSupported ? "" : String(localized: "This server is older than Immich 2.0 and may not work correctly."))
                }
            }
            .font(.caption)
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.large)
    }

    private func primaryButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isWorking ? 0 : 1)
                if isWorking { ProgressView().controlSize(.small) }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
    }

    private func connect() {
        run {
            let client = try await ImmichClient.discover(serverText)
            async let features = try? client.serverFeatures()
            async let version = try? client.serverVersion()
            let f = await features ?? ServerFeatures()
            method = f.passwordLogin ? .password : .apiKey
            step = .credentials(client, f, await version)
            focused = f.passwordLogin ? .email : .apiKey
        }
    }

    private func signIn(_ client: ImmichClient) {
        run {
            let credential: Credential
            if method == .password {
                let response = try await client.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
                credential = .accessToken(response.accessToken)
            } else {
                credential = .apiKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            try await app.signIn(client: client, credential: credential)
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        errorMessage = nil
        isWorking = true
        Task {
            do { try await work() } catch { errorMessage = error.localizedDescription }
            isWorking = false
        }
    }
}
