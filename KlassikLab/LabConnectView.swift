import SwiftUI

/// The server address and the login of the Lab server.
struct LabConnectView: View {
    @Bindable var model: LabModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Address", text: $model.address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("User", text: $model.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $model.password)
                }
                if let error = model.error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button("Connect") { model.connect() }
                }
            }
            .navigationTitle("Klassik Playback Lab")
        }
    }
}
