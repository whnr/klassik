import SwiftUI
import TipKit

/// The system starts Klassik again for a finished background transfer. It then needs the session at launch, and
/// the handler it passes is called when the session has delivered its events.
final class KlassikAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = BackgroundDownloads.shared
        return true
    }

    func application(
        _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundDownloads.shared.attach(completion: completionHandler)
    }
}

@main
struct KlassikApp: App {
    @UIApplicationDelegateAdaptor(KlassikAppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        Self.resetSettingsForTheWalk()
        let model = AppModel()
        _model = State(initialValue: model)
        PersonSweepBackground.register(model)
        BundledFonts.register()
        // UIKit draws the large title of a navigation bar, and SwiftUI has no modifier for its font.
        let title = TypeStyle.pageTitle
        if let face = title.face, let font = UIFont(name: face, size: title.size) {
            UINavigationBar.appearance().largeTitleTextAttributes = [
                .font: UIFontMetrics(forTextStyle: .title1).scaledFont(for: font),
                .foregroundColor: Palette.textPrimary.uiColor,
            ]
        }
        Self.configureTips()
    }

    /// A test run reuses the simulator, and these switches survive a relaunch. Each run starts with their defaults.
    /// It runs before the first colour, because the first colour reads the accent.
    private static func resetSettingsForTheWalk() {
        guard ProcessInfo.processInfo.arguments.contains("-resetServer") else { return }
        for key in [TapIndicator.storageKey, AccentFamily.storageKey, Localization.fallbackKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// The UI walk starts every run from the same state. It hides the tip, except for the runs that look at it:
    /// `-showTips` shows it on every page, `-tipRules` keeps the rules of the tip, as a listener meets them.
    private static func configureTips() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetServer") {
            try? Tips.resetDatastore()
            if arguments.contains("-showTips") {
                Tips.showAllTipsForTesting()
            } else if !arguments.contains("-tipRules") {
                Tips.hideAllTipsForTesting()
            }
        }
        try? Tips.configure([.displayFrequency(.immediate)])
    }

    /// The UI walk takes the dark room with `-darkRoom`: the simulator appearance does not reach a launched app
    /// on the runner. Release builds follow the system.
    private static var launchScheme: ColorScheme? {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-darkRoom") { return .dark }
        #endif
        return nil
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(Self.launchScheme)
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
            if phase == .active {
                Task { await model.playback.synchronizeListeningData() }
                Task { await model.recordingOrder.refresh() }
                Task { await model.checkForChanges() }
            }
            if phase == .background {
                Task { await model.playback.saveQueue() }
                PersonSweepBackground.schedule()
            }
        }
        .alert(
            "Favourites",
            isPresented: Binding(
                get: { model.recordingOrder.error != nil },
                set: { if !$0 { model.recordingOrder.error = nil } }
            )
        ) {
            Button("OK") { model.recordingOrder.error = nil }
        } message: {
            Text(model.recordingOrder.error ?? "")
        }
        .onChange(of: showTaps, initial: true) { TapIndicator.shared.setEnabled(showTaps) }
        .onChange(of: Localization.shared.textLanguages) { model.textLanguagesChanged() }
        .tint(Palette.tint)
        // The tint reads the family from the environment, so the family is set outside it.
        .environment(\.accentFamily, AccentChoice.shared.family)
    }
}
