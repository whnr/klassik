import SwiftUI

/// The licence text of each face that the app bundles.
struct LicencesView: View {
    var body: some View {
        GroupedPageList {
            ForEach(BundledFonts.licences) { licence in
                Section(licence.name) {
                    Text(licence.text)
                        .typeStyle(.footnote)
                        .ink()
                        .textSelection(.enabled)
                        .accessibilityIdentifier("licence-text")
                }
            }
        }
        .pageTitle("Licences")
    }
}
