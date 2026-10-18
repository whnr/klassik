import SwiftUI

/// The listener picks which action sits on which swipe edge of a row.
struct SwipeSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var swipes = model.swipes
        Form {
            Section {
                ForEach(0..<SwipeSettings.slots, id: \.self) { slot in
                    picker(slot, in: $swipes.leading)
                }
            } header: {
                Text("Swipe Right")
            } footer: {
                Text("Rows of recordings and albums. A row that cannot do an action leaves it out.")
            }

            Section("Swipe Left") {
                ForEach(0..<SwipeSettings.slots, id: \.self) { slot in
                    picker(slot, in: $swipes.trailing)
                }
            }

            Section {
                Button("Restore Defaults") { swipes.reset() }
            }
        }
        .navigationTitle("Swipe Actions")
        .miniPlayerInset()
    }

    private func picker(_ slot: Int, in actions: Binding<[SwipeAction?]>) -> some View {
        Picker(
            slot == 0 ? "First Action" : "Second Action",
            selection: Binding(
                get: { slot < actions.wrappedValue.count ? actions.wrappedValue[slot] : nil },
                set: { action in
                    var slots = actions.wrappedValue
                    while slots.count <= slot { slots.append(nil) }
                    slots[slot] = action
                    actions.wrappedValue = slots
                })
        ) {
            Text("None").tag(SwipeAction?.none)
            ForEach(SwipeAction.allCases) { Text($0.title).tag(SwipeAction?.some($0)) }
        }
    }
}
