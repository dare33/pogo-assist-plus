import SwiftUI
import PogoBox

struct NotSeenScreen: View {
    let close: () -> Void
    var body: some View { ReviewTopBar(title: "Not seen", onBack: close) }
}
