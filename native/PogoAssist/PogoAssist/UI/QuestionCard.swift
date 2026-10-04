import SwiftUI

// QuestionCard and SearchStrip (design handoff components 6 and 7).

enum QuestionKind {
    case match, change, copies
    var icon: String {
        switch self { case .match: return "link"; case .change: return "sparkles"; case .copies: return "doc.on.doc" }
    }
    var well: Color {
        switch self { case .match: return Theme.matchTint; case .change: return Theme.changeTint; case .copies: return Theme.copiesTint }
    }
    var ink: Color {
        switch self { case .match: return Theme.matchInk; case .change: return Theme.changeInk; case .copies: return Theme.copiesInk }
    }
}

/// One side of the compare pair. The left side ("READ NOW") shows its name in orange ink.
struct CompareSide: Equatable {
    var name: String
    var line: String
    var ivs: String? = nil
}

struct QuestionCompare: Equatable {
    var readNow: CompareSide
    var inBox: CompareSide
}

/// A question: a 40 pt icon well in the kind colour, the question, an optional READ NOW / IN YOUR BOX pair, the
/// answers (a slot; usually PillButtons, the first `.filled`), an optional SearchStrip slot and a one-line note.
/// With `answered` set it collapses to one row: a green tick, `short`, the answer and "Change".
struct QuestionCard<Answers: View, Search: View>: View {
    let kind: QuestionKind
    let title: String
    var short: String = ""
    var compare: QuestionCompare? = nil
    var note: String? = nil
    /// Non-nil collapses the card to its answered row.
    var answered: String? = nil
    var onChange: () -> Void = {}
    /// Guide me shows the title larger.
    var large = false
    @ViewBuilder var answers: Answers
    @ViewBuilder var search: Search
    @Environment(\.accent) private var accent

    var body: some View {
        if let answered { answeredRow(answered) } else { open }
    }

    private var open: some View {
        Panel(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: kind.icon).font(.figtree(20, .bold))
                    .foregroundStyle(kind.ink)
                    .frame(width: 40, height: 40)
                    .background(kind.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
                Text(title).paText(large ? .questionTitleGuide : .questionTitle).foregroundStyle(Theme.ink)
                    .padding(.top, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }
            if let compare {
                HStack(alignment: .top, spacing: 8) {
                    box("READ NOW", compare.readNow, nameInk: Theme.orangeInk)
                    box("IN YOUR BOX", compare.inBox, nameInk: Theme.ink)
                }
            }
            VStack(spacing: 8) { answers }
            search
            if let note { Text(note).paText(.secondary).foregroundStyle(Theme.muted) }
        }
    }

    private func box(_ heading: String, _ side: CompareSide, nameInk: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(heading).font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.muted)
            Text(side.name).paText(.rowTitle).fontWeight(.bold).foregroundStyle(nameInk)
            Text(side.line).font(.figtree(14, .regular, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.ink)
            if let ivs = side.ivs { Text(ivs).font(.figtree(14, .regular, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.muted) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.Radius.insetRow, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func answeredRow(_ answer: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark").font(.figtree(15, .bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(Circle().fill(Theme.green))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(short.isEmpty ? title : short).paText(.button).foregroundStyle(Theme.ink)
                Text(answer).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Change", action: onChange)
                .font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(accent.ink)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .panelShadow()
    }
}

extension QuestionCard where Search == EmptyView {
    init(kind: QuestionKind, title: String, short: String = "", compare: QuestionCompare? = nil, note: String? = nil, answered: String? = nil, onChange: @escaping () -> Void = {}, large: Bool = false, @ViewBuilder answers: () -> Answers) {
        self.init(kind: kind, title: title, short: short, compare: compare, note: note, answered: answered, onChange: onChange, large: large, answers: answers, search: { EmptyView() })
    }
}

/// The orange search strip: the search to paste into the game, and Copy. Tapping anywhere copies it to the
/// pasteboard and shows the "Copied" toast. `prominent` gives the filled Copy pill (detail screens); the default
/// is the plain "Copy" word used inside question cards.
struct SearchStrip: View {
    let text: String
    var toast = "Copied"
    var prominent = false
    @Environment(\.showToast) private var showToast

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.figtree(16, .bold)).foregroundStyle(Theme.orangeInk).accessibilityHidden(true)
                Text(text)
                    .font(.figtree(prominent ? 15 : 14, prominent ? .heavy : .bold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.orangeInk)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if prominent {
                    Text("Copy").font(.figtree(14, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.surface)
                        .padding(.horizontal, 14).frame(minHeight: 36)
                        .background(Theme.orangeInk, in: Capsule())
                } else {
                    Text("Copy").font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.orangeInk)
                }
            }
            .padding(.leading, prominent ? 16 : 12).padding(.trailing, prominent ? 10 : 12).padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Theme.orangeTint, in: RoundedRectangle(cornerRadius: prominent ? 20 : Theme.Radius.insetRow, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Copy search")
        .accessibilityValue(text)
    }

    private func copy() {
        UIPasteboard.general.string = text
        showToast(toast)
    }
}
