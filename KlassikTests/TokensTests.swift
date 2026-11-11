import Foundation
import Testing
import UIKit

@testable import Klassik

/// The generated colour sets, text styles and the bundled face against the token files (ADR 0021).
@MainActor
struct TokensTests {
    typealias Group = [String: Any]

    /// The simulator reads the checkout of the Mac that built the tests, so the bundle needs no copy of the tokens.
    static let design = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "design")

    static let themes: [(name: String, style: UIUserInterfaceStyle, contrast: UIAccessibilityContrast)] = [
        ("light", .light, .normal),
        ("dark", .dark, .normal),
        ("lightHighContrast", .light, .high),
        ("darkHighContrast", .dark, .high),
    ]

    static func load(_ name: String) throws -> Group {
        let data = try Data(contentsOf: design.appending(path: name))
        return try #require(JSONSerialization.jsonObject(with: data) as? Group)
    }

    /// Lays `source` over `tokens`, group by group. A token replaces a token.
    static func merge(_ source: Group, into tokens: inout Group) {
        for (key, value) in source {
            if let group = value as? Group, group["$value"] == nil, var existing = tokens[key] as? Group {
                merge(group, into: &existing)
                tokens[key] = existing
            } else {
                tokens[key] = value
            }
        }
    }

    /// The tokens of one theme and one accent family: the base file, then the theme files, then the family file.
    static func tokens(theme: String, accent: String) throws -> Group {
        let resolver = try load("klassik.resolver.json")
        let modifiers = try #require(resolver["modifiers"] as? Group)
        func sources(_ modifier: String, _ context: String) throws -> [Group] {
            let contexts = try #require((modifiers[modifier] as? Group)?["contexts"] as? Group)
            return try #require(contexts[context] as? [Group])
        }
        var tokens = try load("klassik.tokens.json")
        for source in try sources("theme", theme) + sources("accent", accent) {
            let file = try #require(source["$ref"] as? String)
            merge(try load(file), into: &tokens)
        }
        return tokens
    }

    static func token(_ path: String, in tokens: Group) throws -> Group {
        var node = tokens
        for key in path.split(separator: ".") {
            node = try #require(node[String(key)] as? Group, "\(path)")
        }
        return node
    }

    /// Red, green, blue and alpha of a colour token. An alias such as "{palette.dark.tint}" leads to its target.
    static func colour(_ path: String, in tokens: Group) throws -> [Double] {
        let value = try token(path, in: tokens)["$value"]
        if let alias = value as? String {
            return try colour(String(alias.dropFirst().dropLast()), in: tokens)
        }
        let colour = try #require(value as? Group, "\(path)")
        let components = try #require(colour["components"] as? [Double], "\(path)")
        return components + [colour["alpha"] as? Double ?? 1]
    }

    /// The paths of the tokens below a group, such as "background.page".
    static func paths(_ group: Group, prefix: [String] = []) -> [String] {
        var found: [String] = []
        for (key, value) in group where !key.hasPrefix("$") {
            guard let child = value as? Group else { continue }
            if child["$value"] != nil {
                found.append((prefix + [key]).joined(separator: "."))
            } else {
                found += paths(child, prefix: prefix + [key])
            }
        }
        return found.sorted()
    }

    /// The name of the colour set of a token: "favourite-off" is "FavouriteOff".
    static func assetName(_ path: String) -> String {
        path.split { $0 == "." || $0 == "-" }.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    static func traitCollection(
        _ theme: (name: String, style: UIUserInterfaceStyle, contrast: UIAccessibilityContrast)
    ) -> UITraitCollection {
        UITraitCollection { traits in
            traits.userInterfaceStyle = theme.style
            traits.accessibilityContrast = theme.contrast
        }
    }

    /// Compares a colour set with a token in one theme. A hex value rounds each channel to 1/255.
    static func expectColour(
        _ name: String, is path: String, in tokens: Group,
        theme: (name: String, style: UIUserInterfaceStyle, contrast: UIAccessibilityContrast)
    ) throws {
        let traits = traitCollection(theme)
        let colour = try #require(
            UIColor(named: name, in: Bundle(for: BundleToken.self), compatibleWith: traits), "\(name)")
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let isRGB = colour.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(isRGB, "\(name)")
        let expected = try Self.colour(path, in: tokens)
        for (got, want) in zip([red, green, blue, alpha], expected) {
            #expect(abs(Double(got) - want) < 0.003, "\(name) in \(theme.name)")
        }
    }

    @Test(arguments: AccentFamily.allCases)
    func everyColourSetMatchesItsToken(family: AccentFamily) throws {
        for theme in Self.themes {
            let tokens = try Self.tokens(theme: theme.name, accent: String(describing: family))
            let paths = Self.paths(try Self.token("color", in: tokens))
            #expect(Set(paths.map(Self.assetName)) == Set(Palette.allCases.map(\.rawValue)))
            for path in paths {
                try Self.expectColour(
                    "\(family.rawValue)/\(Self.assetName(path))", is: "color.\(path)", in: tokens, theme: theme)
            }
        }
    }

    /// System controls take the global accent colour, so it must be the tint of the standard family.
    @Test func globalAccentIsTheStandardTint() throws {
        for theme in Self.themes {
            let tokens = try Self.tokens(theme: theme.name, accent: String(describing: AccentFamily.standard))
            try Self.expectColour("AccentColor", is: "color.tint", in: tokens, theme: theme)
        }
    }

    @Test func textStylesFollowTheRatio() throws {
        let tokens = try Self.tokens(theme: "light", accent: String(describing: AccentFamily.standard))
        let names = Self.paths(try Self.token("type", in: tokens))
        #expect(Set(names) == Set(TypeStyle.allCases.map { String(describing: $0) }))
        for style in TypeStyle.allCases {
            let token = try Self.token("type.\(style)", in: tokens)
            let klassik = try #require((token["$extensions"] as? Group)?["de.whnr.klassik"] as? Group)
            let step = try #require(klassik["step"] as? Double)
            #expect(abs(Double(style.size) - 17 * pow(4 / 3, step)) < 0.01, "\(style)")
        }
    }

    @Test func bundlesEachFaceWithItsLicence() {
        for style in TypeStyle.allCases {
            if let face = style.face {
                #expect(UIFont(name: face, size: style.size) != nil, "\(face)")
            }
        }
        #expect(!BundledFonts.licences.isEmpty)
        for licence in BundledFonts.licences {
            #expect(licence.text.contains("SIL Open Font License"), "\(licence.name)")
        }
    }
}
