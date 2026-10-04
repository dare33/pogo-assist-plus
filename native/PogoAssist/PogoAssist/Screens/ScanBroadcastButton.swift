import SwiftUI
import ReplayKit

/// Lets a tap on any SwiftUI view start the broadcast the way the old start control did: with the system broadcast picker
/// (`RPSystemBroadcastPickerView`, the only thing iOS lets start a broadcast). The picker's own button is stretched over the
/// view and made invisible, so a real touch lands on it; `fire()` presses that button for VoiceOver's activate action, which
/// has no touch. Use `.broadcastPicker(trigger:)` on the view that should start it.
@MainActor
final class BroadcastTrigger: ObservableObject {
    fileprivate weak var picker: FullTapPicker?
    func fire() {
        for case let b as UIButton in picker?.subviews ?? [] { b.sendActions(for: .touchUpInside) }
    }
}

/// The system picker with its button filling the view and no icon of its own.
final class FullTapPicker: RPSystemBroadcastPickerView {
    override func layoutSubviews() {
        super.layoutSubviews()
        for case let b as UIButton in subviews {
            b.frame = bounds
            b.setImage(nil, for: .normal)
            b.backgroundColor = .clear
        }
    }
}

private struct PickerOverlay: UIViewRepresentable {
    let trigger: BroadcastTrigger
    func makeUIView(context: Context) -> FullTapPicker {
        let picker = FullTapPicker(frame: CGRect(x: 0, y: 0, width: 240, height: 240))
        picker.preferredExtension = Bundle.main.object(forInfoDictionaryKey: "BroadcastExtensionID") as? String
        picker.showsMicrophoneButton = false
        picker.isAccessibilityElement = false
        trigger.picker = picker
        return picker
    }
    func updateUIView(_ uiView: FullTapPicker, context: Context) { trigger.picker = uiView }
}

extension View {
    /// A tap on this view shows the system broadcast picker (Pogo Broadcast, Start Broadcast). The view gets the Start scan
    /// accessibility name unless `label` says otherwise.
    func broadcastPicker(trigger: BroadcastTrigger, label: String = "Start scan", shape: some Shape = Rectangle()) -> some View {
        self.overlay { PickerOverlay(trigger: trigger).clipShape(shape).accessibilityHidden(true) }
            .contentShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { trigger.fire() }
    }
}
