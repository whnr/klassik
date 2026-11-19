import SwiftUI

extension EnvironmentValues {
    /// Colours that replace those of the asset catalog for the views below, such as the player wash.
    @Entry var paletteOverrides: [Palette: Color.Resolved] = [:]
}
