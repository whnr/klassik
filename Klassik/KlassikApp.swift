import SwiftUI
import TipKit

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
        // The bar shows no title (ADR 0023). Only the colour of the small title goes: VoiceOver and the back
        // button of the next page still read it.
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: UIColor.clear]
        Self.configureTips()
    }

    /// The UI walk starts every run from the same state. It hides the tip, except for the run that looks at it.
    private static func configureTips() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetServer") {
            try? Tips.resetDatastore()
            if arguments.contains("-showTips") { Tips.showAllTipsForTesting() } else { Tips.hideAllTipsForTesting() }
        }
        try? Tips.configure([.displayFrequency(.immediate)])
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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(TapIndicator.storageKey) private var showTaps = false

    var body: some View {
        Group {
            if model.credentials == nil {
                ConnectView()
            } else {
                PlacesView()
                    .task { await model.start() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Task { await model.playback.saveQueue() } }
        }
        .onChange(of: showTaps, initial: true) { TapIndicator.shared.setEnabled(showTaps) }
    }
}
