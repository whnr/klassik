import SwiftUI

/// The licence text of each face that the app bundles.
struct LicencesView: View {
    var body: some View {
        PageList {
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
        .navigationTitle("Licences")
        .miniPlayerInset()
    }
}
