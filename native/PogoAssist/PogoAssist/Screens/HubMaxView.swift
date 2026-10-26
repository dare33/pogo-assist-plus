import SwiftUI
import PogoBox

/// The Max battles screen (design pass 2): the `Now | Coming up` lists of Max Mondays and Dynamax Trails, as Raids' Coming up is, with SUGGESTIONS · Available | Best.
/// A row opens into BRING and the squad of three (Tank, Healer, Attacker) with its picker. The roster of Dynamax copies, its tiles and its two notes are gone (D8).
struct HubMaxView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        var count: String?
        if case .ready(let a) = model.advice { count = buildsText(HubModel.count(a.builds, for: .max)) }
        let sub = (try? HubData.bundled()).flatMap { HubRaidsModel.lastDay(rows: $0.rotation, screen: .max) }.map { "Max Mondays and events to \($0)" }
        return HubTypeScreen(type: .max, sub: sub, count: count) {
            HubTimeline(screen: .max, closers: false)
            HubAdviceGate { _ in EmptyView() }
            HubScheduleLink()
        }
        .accessibilityIdentifier("hub-screen-max")
    }
}
