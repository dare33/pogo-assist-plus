import SwiftUI
import PogoBox

/// The kinds of Special scan, as one choice. Each kind is its own run and its own save. Lucky, Shiny and Background are listed after them, tagged "Coming soon" and not
/// choosable until a scan is built for each (Greg, 31 Oct 2026).
struct PassPicker: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Which search?").font(.secondary).foregroundStyle(Theme.muted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(ScanPass.allCases, id: \.self) { pass in
                    let on = model.scanPass == pass
                    Button { model.scanPass = pass } label: {
                        Text(pass.title).font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(on ? accent.onSolid : Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(on ? accent.solid : Theme.off, in: Capsule())
                            .frame(minHeight: 44).contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("pass-kind-\(pass.rawValue)")
                }
                ForEach(ScanPass.comingSoon, id: \.self) { name in
                    VStack(spacing: 0) {
                        Text(name).font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.faint)
                        Text("Coming soon").font(.figtree(11, .semibold, relativeTo: .caption2)).foregroundStyle(Theme.faint)
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Theme.off.opacity(0.5), in: Capsule())
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(name), coming soon")
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityIdentifier("pass-soon-\(name.lowercased())")
                }
            }
        }
    }
}

/// The search word and "Copy search": the player pastes it into the game's storage search themselves. Nothing here reaches the game.
struct CopySearchRow: View {
    let pass: ScanPass
    @Environment(\.accent) private var accent
    @Environment(\.showToast) private var showToast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.figtree(16, .bold)).foregroundStyle(accent.ink).accessibilityHidden(true)
            Text(pass.searchWord).font(.figtree(18, .heavy, relativeTo: .body)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("scan-search-word")
            Button {
                UIPasteboard.general.string = pass.searchWord
                showToast("Copied")
            } label: {
                HStack(spacing: 6) { Image(systemName: "doc.on.doc"); Text("Copy search") }
                    .font(.figtree(14, .heavy, relativeTo: .subheadline)).foregroundStyle(accent.ink)
                    .padding(.horizontal, 14).frame(minHeight: 36).background(accent.tint, in: Capsule())
                    .frame(minHeight: 44).contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Copy search, \(pass.searchWord)")
            .accessibilityIdentifier("scan-copy-search")
        }
        .padding(.leading, 14).padding(.trailing, 4).frame(minHeight: 48)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
