#if DEBUG
import SwiftUI

/// Every UI v1 component in its states, for screenshots and review. DEBUG only: PogoAssistApp shows it when the
/// app is launched with `-ui-gallery`, and the whole file is compiled out of Release. Launch arguments
/// `-appearance dark|light|auto`, `-accent berry` and `-helpLevel guide` set the preferences (AppStorage reads them).
struct ComponentGallery: View {
    @StateObject private var model = AppModel()
    @State private var tab: AppTab = .box
    @State private var answered = false
    @AppStorage(PrefKey.accent) private var accentRaw = Accent.blue.rawValue

    private let drizzile = QuestionCompare(
        readNow: CompareSide(name: "Drizzile", line: "CP 1060 · HP 105", ivs: "IVs 13/13/14"),
        inBox: CompareSide(name: "Sobble", line: "CP 609 · HP 90", ivs: "IVs 13/13/14"))

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.panelGap) {
                    header
                    heading("Type roles")
                    typeRoles
                    heading("Figtree weights")
                    weights
                    heading("Accents")
                    accents
                    heading("Colour tokens")
                    tokens
                    heading("Scan mark")
                    scanMarks
                    heading("Buttons and chips")
                    buttons
                    heading("Panels and rows")
                    panels
                    heading("Questions")
                    questions
                    heading("Bars")
                    bars
                    heading("Accounts")
                    accounts
                    heading("Floating tab bar")
                    Text("Shown over this screen; the Scan button is live.").paText(.secondary).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.bottom, FloatingTabBar.clearance + 20)
            }
            .accessibilityIdentifier("gallery-scroll")
            VStack { Spacer(); FloatingTabBar(selection: $tab) {} }
        }
        .environmentObject(model)
        .themeRoot()
    }

    private func heading(_ t: String) -> some View {
        Text(t).paText(.screenTitle).foregroundStyle(Theme.ink).padding(.top, 18).padding(.horizontal, 6)
            .accessibilityAddTraits(.isHeader)
    }

    // The Box header, as the Box implementer will compose it.
    private var header: some View {
        HStack { AccountPill(); Spacer(); MoreButton() }.padding(.top, 8)
    }

    private var typeRoles: some View {
        Panel {
            ForEach(PAFont.allCases, id: \.name) { role in
                VStack(alignment: .leading, spacing: 2) {
                    Text(role.name).font(.figtree(11, .medium)).foregroundStyle(Theme.faint)
                    Text(sample(role)).paText(role).foregroundStyle(role == .secondary ? Theme.muted : Theme.ink)
                }
            }
        }
    }
    private func sample(_ r: PAFont) -> String {
        switch r {
        case .heroFigure: return "1,698"
        case .screenTitle: return "Box at 15,000"
        case .questionTitle, .questionTitleGuide: return "Is this Drizzile your Sobble, evolved?"
        case .rowTitle: return "Check in the game"
        case .button: return "Yes, duplicate · ignore it"
        case .secondary: return "Scan finished at the end of your list"
        case .chipLabel: return "TO CHECK 6"
        }
    }

    private var weights: some View {
        Panel(spacing: 6) {
            ForEach([(400, Font.Weight.regular), (500, .medium), (600, .semibold), (700, .bold), (800, .heavy)], id: \.0) { w, weight in
                Text("\(w)  Wake up, Pogo scan 2000 – 1,698")
                    .font(.figtree(20, weight)).foregroundStyle(Theme.ink)
            }
        }
    }

    private var accents: some View {
        Panel {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 16) {
                ForEach(Accent.allCases) { a in
                    Button { accentRaw = a.rawValue } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle().fill(a.solid).frame(width: 52, height: 52)
                                Text("Aa").font(.figtree(15, .bold)).foregroundStyle(a.onSolid)
                                HStack(spacing: 0) { Rectangle().fill(a.ink); Rectangle().fill(a.tint) }
                                    .frame(width: 26, height: 8).clipShape(Capsule()).offset(y: 16)
                            }
                            Text(a.name).font(.chipLabel).foregroundStyle(Theme.muted)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var tokens: some View {
        let items: [(String, Color)] = [("bg", Theme.bg), ("surface", Theme.surface), ("surface2", Theme.surface2), ("ink", Theme.ink), ("muted", Theme.muted), ("faint", Theme.faint), ("line", Theme.line), ("off", Theme.off), ("orange", Theme.orange), ("orangeInk", Theme.orangeInk), ("orangeTint", Theme.orangeTint), ("green", Theme.green), ("greenInk", Theme.greenInk), ("greenTint", Theme.greenTint), ("red", Theme.red), ("match", Theme.match), ("matchInk", Theme.matchInk), ("matchTint", Theme.matchTint), ("change", Theme.change), ("changeInk", Theme.changeInk), ("changeTint", Theme.changeTint), ("copies", Theme.copies), ("copiesInk", Theme.copiesInk), ("copiesTint", Theme.copiesTint)]
        return Panel {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                ForEach(items, id: \.0) { n, c in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 10).fill(c).frame(height: 34).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                        Text(n).font(.figtree(10, .semibold)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
        }
    }

    private var scanMarks: some View {
        Panel {
            HStack(spacing: 20) {
                ScanMark().frame(width: 96, height: 96).foregroundStyle(Theme.ink)
                ScanMark().frame(width: 48, height: 48).foregroundStyle(Theme.orange)
                ScanMark().frame(width: 24, height: 24).foregroundStyle(Theme.green)
                ScanMark().frame(width: 20, height: 20).foregroundStyle(Theme.muted)
                // The default is two-tone (gold stars); this is the monochrome option the tab bar uses.
                ScanMark(monochrome: true).frame(width: 48, height: 48).foregroundStyle(Theme.ink)
            }
        }
    }

    private var buttons: some View {
        Panel {
            PillButton("Save to box", style: .filled) {}
            PillButton("Add new", systemImage: "plus", style: .tint) {}
            PillButton("Not included", style: .plain) {}
            PillButton("Discard", isDestructive: true) {}
            PillButton("6 to go", style: .filled) {}.disabled(true)
            HStack(spacing: 14) {
                IconButton(systemImage: "checkmark", kind: .done, label: "Duplicate, ignore it") {}
                IconButton(systemImage: "plus", kind: .add, label: "Add it") {}
                IconButton(systemImage: "arrow.clockwise", kind: .neutral, label: "Refresh") {}
                IconButton(systemImage: "xmark", kind: .floating, label: "Close") {}
            }
            HStack(spacing: 8) {
                Chip(text: "Tier S", tone: .green)
                Chip(text: "Raids", tone: .accent)
                Chip(text: "Check", tone: .orange, caps: true)
                Chip(text: "Match", tone: .match)
                Chip(text: "Evolved", tone: .change)
                Chip(text: "Twin", tone: .copies)
            }
            HStack(spacing: 8) {
                Chip(text: "All", shape: .pill, isSelected: true)
                Chip(text: "To check 6", tone: .orange, shape: .pill)
                Chip(text: "Not seen 12", tone: .neutral, shape: .pill)
            }
        }
    }

    private var panels: some View {
        VStack(spacing: Theme.Space.panelGap) {
            Panel(tint: .accent) { Text("Scan finished at the end of your list").paText(.rowTitle).foregroundStyle(Theme.ink); Text("1,698").paText(.heroFigure).foregroundStyle(Theme.ink) }
            Panel(tint: .green) { Text("Saved to Darentas").paText(.rowTitle).foregroundStyle(Theme.greenInk) }
            Panel(tint: .orange) { Text("These values are right").paText(.rowTitle).foregroundStyle(Theme.orangeInk) }
            Panel(padding: 0, spacing: 0) {
                InsetRow(title: "Check in the game", icon: "magnifyingglass", iconBackground: Theme.orangeTint, iconInk: Theme.orangeInk, value: "6", showsChevron: true) {}
                InsetRow(title: "Not seen in this scan", sub: "12 kept, search the game", icon: "eye.slash", value: "12", showsChevron: true) {}
                InsetRow(title: "Notes, nothing to do", sub: "Nidoran sex chosen from stats", icon: "note.text", value: "25", separator: false)
            }
            Panel(padding: 0, spacing: 0) {
                InsetRow(title: "Help level", sub: "Standard", showsChevron: true) {}
                InsetRow(title: "Appearance", sub: "Auto", showsChevron: true, separator: false) {}
            }
        }
    }

    private var questions: some View {
        VStack(spacing: Theme.Space.panelGap) {
            QuestionCard(kind: .change, title: "Is this Drizzile your Sobble, evolved?", short: "Drizzile, CP 1060", compare: drizzile,
                         note: "The game shows a few extra matches.", answered: answered ? "Evolved: saved Sobble becomes Drizzile" : nil, onChange: { answered = false }) {
                PillButton("Yes, it evolved", systemImage: "checkmark", style: .filled, height: 48) { answered = true }
                PillButton("Add new", systemImage: "plus") {}
                PillButton("Don't include", systemImage: "minus") {}
            } search: {
                SearchStrip(text: "sobble,drizzile&cp609,cp1060")
            }
            QuestionCard(kind: .match, title: "Is this the Tympole in your box?",
                         compare: QuestionCompare(readNow: CompareSide(name: "Tympole", line: "CP 623 · HP 108", ivs: "IVs 5/10/13"), inBox: CompareSide(name: "Tympole", line: "CP 623 · HP 108", ivs: "IVs 6/11/14"))) {
                PillButton("It's this one", style: .filled) {}
                PillButton("Add new") {}
            } search: { SearchStrip(text: "tympole&cp623") }
            QuestionCard(kind: .copies, title: "The scan saw two identical Kakuna. Do you have two?", large: false) {
                PillButton("Yes, add one", style: .filled) {}
                PillButton("No, don't include") {}
            }
            QuestionCard(kind: .match, title: "Is this Moltres a duplicate?", short: "Moltres, CP 901", answered: "Matched", onChange: {}) {}
            Panel {
                Text("Are these duplicates of Pokémon in your box?").paText(.questionTitle).foregroundStyle(Theme.ink)
                ForEach([("Staraptor", "CP 951 · HP 140"), ("Moltres", "CP 901 · HP 129"), ("Charizard", "CP 607 · HP 118")], id: \.0) { n, l in
                    HStack {
                        VStack(alignment: .leading) { Text(n).paText(.rowTitle).foregroundStyle(Theme.ink); Text(l).paText(.secondary).foregroundStyle(Theme.muted) }
                        Spacer()
                        IconButton(systemImage: "checkmark", kind: .done, label: "Duplicate, ignore \(n)") {}
                        IconButton(systemImage: "plus", kind: .add, label: "Add \(n)") {}
                    }
                }
                SearchStrip(text: "staraptor,moltres,charizard&hp140,hp129,hp118")
            }
            SearchStrip(text: "rayquaza&cp4262", prominent: true)
        }
    }

    private var bars: some View {
        VStack(spacing: Theme.Space.panelGap) {
            Panel {
                HStack(alignment: .firstTextBaseline) {
                    Text("IVs").font(.chipLabel).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("98%").font(.figtree(26, .heavy)).monospacedDigit().foregroundStyle(Theme.greenInk)
                }
                BarsView(15, 15, 14)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach([("Pidgey", 312, (12, 9, 14)), ("Charmander", 455, (8, 15, 11)), ("Eevee", 590, (15, 15, 10)), ("Meltan", 421, (3, 7, 12))], id: \.0) { n, cp, iv in
                    VStack(alignment: .leading, spacing: 5) {
                        (Text("CP ").font(.figtree(10, .bold)).foregroundStyle(Theme.muted) + Text("\(cp)").font(.figtree(18, .heavy)).foregroundStyle(Theme.ink)).monospacedDigit()
                        Text(n).font(.figtree(11, .bold)).foregroundStyle(Theme.muted).lineLimit(1)
                        BarsView(iv.0, iv.1, iv.2, mini: true)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }

    private var accounts: some View {
        Panel {
            HStack(spacing: 14) {
                ForEach(["Darentas", "Kestrel21", "MossyBank", "AsterLeaf", "Greg main"], id: \.self) { AccountMonogram(name: $0, size: 40) }
            }
        }
    }
}
#endif
