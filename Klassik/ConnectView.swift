import SwiftUI

struct ConnectView: View {
    @Environment(AppModel.self) private var model
    // The screens workflow fills in the fixture server through the environment.
    @State private var url = ProcessInfo.processInfo.environment["KLASSIK_SERVER_URL"] ?? ""
    @State private var username = ProcessInfo.processInfo.environment["KLASSIK_USERNAME"] ?? ""
    @State private var password = ProcessInfo.processInfo.environment["KLASSIK_PASSWORD"] ?? ""
    @State private var error: String?
    @State private var isConnecting = false

    private var candidate: ServerCredentials? {
        guard let url = ServerCredentials.normalizedURL(from: url), !username.isEmpty, !password.isEmpty else { return nil }
        return ServerCredentials(url: url, username: username, password: password)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server URL", text: $url, prompt: Text("music.example.org"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .accessibilityIdentifier("server-url")
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .accessibilityIdentifier("username")
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("password")
                } footer: {
                    Text("Any OpenSubsonic server, such as Navidrome. Klassik reads your tags and never changes them.")
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        if isConnecting {
                            ProgressView()
                        } else {
                            Text("Connect")
                        }
                    }
                    .disabled(candidate == nil || isConnecting)
                    .accessibilityIdentifier("connect")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Klassik")
        }
    }

    private func connect() async {
        guard let candidate else { return }
        isConnecting = true
        error = await model.connect(candidate)
        isConnecting = false
    }
}
