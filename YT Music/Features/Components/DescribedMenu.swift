import SwiftUI

/// A menu of choices with a sublabel under each, which a menu-style `Picker`
/// doesn't show.
struct DescribedMenu<Value: Hashable>: View {
    struct Choice {
        var value: Value
        var title: String
        var detail: String
        var isDisabled = false
    }

    @Binding var selection: Value
    let choices: [Choice]

    var body: some View {
        Menu {
            ForEach(choices, id: \.value) { choice in
                Toggle(isOn: Binding(
                    get: { selection == choice.value },
                    set: { if $0 { selection = choice.value } }
                )) {
                    Text(choice.title)
                    Text(choice.detail)
                }
                .disabled(choice.isDisabled)
            }
        } label: {
            Text(choices.first { $0.value == selection }?.title ?? "")
        }
        .fixedSize()
    }
}
