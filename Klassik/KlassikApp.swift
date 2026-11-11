import SwiftUI

@main
struct KlassikApp: App {
    @State private var model = AppModel()

    init() {
        BundledFonts.register()
        // UIKit draws the large title of a navigation bar, and SwiftUI has no modifier for its font.
        let title = TypeStyle.pageTitle
        if let face = title.face, let font = UIFont(name: face, size: title.size) {
            UINavigationBar.appearance().largeTitleTextAttributes = [
                .font: UIFontMetrics(forTextStyle: .title1).scaledFont(for: font),
                .foregroundColor: Palette.textPrimary.uiColor,
            ]
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Palette.tint)
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
