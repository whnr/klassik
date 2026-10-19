import SwiftUI

@main
struct KlassikApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(TapIndicator.storageKey) private var showTaps = false

    var body: some View {
        Group {
            if model.credentials == nil {
                ConnectView()
            } else {
                HomeView()
                    .task { await model.start() }
            }
        }
        .onChange(of: showTaps, initial: true) { TapIndicator.shared.setEnabled(showTaps) }
    }
}
