import SwiftUI

/// The three places the Scan screen points at "Get ready to scan": the banner at the top (always), the "N setup steps left · Finish" line above the mark button (while steps are
/// left) and the small sheet that comes before a scan when setup is not done.

/// The top banner. One Panel: the icon well, the text, a chevron. Tapping it opens the checklist.
struct SetupBanner: View {
    static let text = "Important! Before you start your scan please ensure that you have opened your first Pokémon's appraisal in Pokémon GO. For first time users, set your device up to work with Pogo Assist by tapping this banner."
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 17, weight: .bold)).frame(width: 36, height: 36)
                    .foregroundStyle(Theme.orangeInk).background(Theme.orangeTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous)).accessibilityHidden(true)
                (Text("Important! ").bold() + Text(String(Self.text.dropFirst("Important! ".count))))
                    .font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.figtree(14, .bold)).foregroundStyle(Theme.faint).accessibilityHidden(true)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)).panelShadow()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(Self.text)
        .accessibilityHint("Opens Get ready to scan")
        .accessibilityIdentifier("setup-banner")
    }
}

/// "2 setup steps left · Finish" (the design's line above the button).
struct SetupLeftLine: View {
    let left: Int
    var action: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: action) {
            Text("\(left) setup \(left == 1 ? "step" : "steps") left · Finish").font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(accent.ink)
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("setup-left")
    }
}

/// Before a scan, while setup is not done and the paging is by voice: say so once, kindly, and let the person carry on.
struct SetupSheet: View {
    var openSetup: () -> Void
    var scanAnyway: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Set your phone up first?").font(.figtree(22, .heavy, relativeTo: .title2)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Text("Scanning by voice works best once your phone has a few one-time settings. The checklist takes you through them and remembers where you are.")
                    .font(.figtree(16, .regular, relativeTo: .body)).foregroundStyle(Theme.muted)
                VStack(spacing: 10) {
                    PillButton("Open Scan setup", style: .filled, height: 52, action: openSetup).accessibilityIdentifier("setup-sheet-open")
                    PillButton("Scan anyway", style: .plain, height: 52, action: scanAnyway).accessibilityIdentifier("setup-sheet-anyway")
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .presentationDetents([.height(300), .large])
        .presentationDragIndicator(.visible)
    }
}
