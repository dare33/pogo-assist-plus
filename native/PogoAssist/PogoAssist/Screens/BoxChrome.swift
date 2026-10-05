import SwiftUI
import UIKit
import PogoBox

// Pieces shared by the Box, species list and detail screens: the header's text button, the delete confirmation and
// the swipe-back gesture for screens that hide the navigation bar.

/// A 40 pt pill on the surface colour with a word in it ("Select", "Cancel", "All 24"), with a 44 pt hit area.
struct HeaderTextButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.figtree(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Capsule().fill(Theme.surface))
                .panelShadow()
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// "CP 2819": the small CP label and the figure.
struct CPFigure: View {
    let cp: Int
    var body: some View {
        if cp > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("CP").font(.figtree(11, .heavy, relativeTo: .caption2)).tracking(0.02 * 11).foregroundStyle(Theme.muted)
                Text(verbatim: String(cp)).font(.figtree(16, .heavy)).monospacedDigit().foregroundStyle(Theme.ink)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("CP not known").font(.figtree(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.muted)
        }
    }
}

/// The small "Mega" tag on a row of a Pokémon that has a Mega form (it is one Pokémon; the row's figures are its normal form's).
struct MegaMarker: View {
    @Environment(\.accent) private var accent
    var body: some View {
        Text("Mega").font(.figtree(11, .heavy, relativeTo: .caption2)).foregroundStyle(accent.ink)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(accent.tint, in: Capsule())
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// A Pokémon the person asked to delete, held while the confirmation is up.
struct DeleteTarget: Identifiable, Equatable {
    var id: String
    var title: String
    var cp: Int
}

/// The confirmation the Box list had before the redesign, word for word.
private struct ConfirmDelete: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Binding var target: DeleteTarget?
    var onDeleted: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(target.map { "Delete \($0.title), CP \($0.cp)?" } ?? "Delete this Pokémon?", isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } }), titleVisibility: .visible) {
            Button("Delete from box", role: .destructive) {
                if let t = target { Task { await model.deleteEntry(t.id); onDeleted() } }
                target = nil
            }
        } message: { Text("It is removed from the box only, not from the game. The box keeps an earlier version that still has it, which Settings can restore.") }
    }
}

extension View {
    func confirmDelete(_ target: Binding<DeleteTarget?>, onDeleted: @escaping () -> Void = {}) -> some View {
        modifier(ConfirmDelete(target: target, onDeleted: onDeleted))
    }
}

// Hiding the navigation bar (the Box screens draw their own header) turns off the edge swipe back; this turns it on again.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { viewControllers.count > 1 }
}
