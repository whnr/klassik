import SwiftUI
import Testing
import UIKit

@testable import Klassik

@MainActor
struct DisclosureRowTests {
    /// The frames that the row reports while a window lays it out.
    @MainActor private final class Frames {
        var title = CGRect.null
        var value = CGRect.null
    }

    private func layOut(title: String, width: CGFloat) async throws -> Frames {
        let frames = Frames()
        let row = DisclosureRow {
            LabeledContent {
                Text("12").onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    frames.value = $0
                }
            } label: {
                Text(title).onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    frames.title = $0
                }
            }
        }
        .frame(width: width)
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 400)
        window.rootViewController = UIHostingController(rootView: row)
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<100 where frames.value.isNull || frames.title.isNull {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        return frames
    }

    @Test func theCountStaysAtTheTrailingEdgeWhenTheTitleWraps() async throws {
        let short = try await layOut(title: "Carl Fixture", width: 320)
        let long = try await layOut(
            title: "Sine Wave Chamber Orchestra and the Testing Philharmonic Choir of the Fixture Library", width: 320)
        #expect(!short.value.isNull && !long.value.isNull)
        #expect(long.title.height > short.title.height, "The long title does not wrap")
        #expect(abs(long.value.maxX - short.value.maxX) < 0.5)
        // The title takes the width up to the count, so only the count and the caret sit after it.
        #expect(short.title.maxX <= short.value.minX)
        #expect(long.value.minX - long.title.maxX < short.value.minX - short.title.maxX)
    }
}
