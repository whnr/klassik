import Foundation
import UIKit

#if DEBUG
    /// UI tests pass Wikidata, Wikipedia and Commons answers in KLASSIK_PERSON_STUB, as a JSON list of
    /// `[text, body]` pairs: the first pair whose text the URL holds answers. Any other request gets a 404, so
    /// the screen walk never asks the network. The picture is drawn here, because the repository holds no
    /// picture of a real person. Release builds always ask the services.
    enum PersonLaunchStub {
        static let variable = "KLASSIK_PERSON_STUB"

        /// The fetch for facts, or nil when the launch gives no stub.
        static var fetch: MusicBrainz.Fetch? {
            guard let json = ProcessInfo.processInfo.environment[variable],
                let pairs = try? JSONDecoder().decode([[String]].self, from: Data(json.utf8))
            else { return nil }
            return { request in
                let url = request.url?.absoluteString.removingPercentEncoding ?? ""
                guard let pair = pairs.first(where: { $0.count == 2 && url.contains($0[0]) }) else {
                    return (Data(), 404)
                }
                return (Data(pair[1].utf8), 200)
            }
        }

        /// A drawn bust: a pale head and dark shoulders on a warm ground. It has no face that Vision finds, as
        /// with a painting, and it is bright enough at the top to need the scrim.
        static let picture: MusicBrainz.Fetch = { _ in
            let size = CGSize(width: 900, height: 1200)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let data = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
                let cg = context.cgContext
                let colours = [
                    UIColor(red: 0.86, green: 0.78, blue: 0.62, alpha: 1).cgColor,
                    UIColor(red: 0.45, green: 0.33, blue: 0.22, alpha: 1).cgColor,
                ]
                let space = CGColorSpaceCreateDeviceRGB()
                if let gradient = CGGradient(colorsSpace: space, colors: colours as CFArray, locations: [0, 1]) {
                    cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
                }
                UIColor(red: 0.16, green: 0.12, blue: 0.1, alpha: 1).setFill()
                cg.fillEllipse(in: CGRect(x: 120, y: 760, width: 660, height: 700))
                UIColor(red: 0.93, green: 0.82, blue: 0.7, alpha: 1).setFill()
                cg.fillEllipse(in: CGRect(x: 300, y: 260, width: 300, height: 400))
                cg.fill(CGRect(x: 400, y: 600, width: 100, height: 200))
            }
            return (data, 200)
        }
    }
#endif
