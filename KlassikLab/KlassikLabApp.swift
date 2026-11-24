import SwiftUI

@main
struct KlassikLabApp: App {
    @State private var model = LabModel()

    var body: some Scene {
        WindowGroup {
            switch model.phase {
            case .connect: LabConnectView(model: model)
            case .loading: ProgressView("Loading the test cases")
            case .ready(let player, let cases): LabPlayerView(model: model, player: player, cases: cases)
            }
        }
    }
}
