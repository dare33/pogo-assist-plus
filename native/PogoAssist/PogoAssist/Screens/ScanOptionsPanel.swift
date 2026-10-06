import SwiftUI
import PogoBox
import PogoReader

/// The one summary line of the remembered options: "Full scan · 1,698 in storage · Scan Options".
struct ScanOptionsSummary: View {
    @EnvironmentObject var model: AppModel
    var onEdit: () -> Void
    @Environment(\.accent) private var accent

    private var text: String {
        if model.scanKind == .partial { return "Add and update" }
        if let n = model.storageCount { return "Full scan · \(n.formatted()) in storage" }
        return "Full scan · no count typed"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3").font(.figtree(16, .bold)).foregroundStyle(accent.ink).accessibilityHidden(true)
            Text(text).font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(accent.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onEdit) {
                Text("Scan Options").font(.figtree(13, .heavy, relativeTo: .footnote)).foregroundStyle(accent.ink)
                    .padding(.horizontal, 14).frame(minHeight: 34)
                    .background(Capsule().fill(Theme.surface))
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Scan Options")
        }
        .padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 2)
        .background(accent.tint, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// "Scan options" (frame 2b): the kind, the storage count and the eggs (or, for Add and update, how many to scan), remembered for the account. Replaces the steps while it is open.
struct ScanOptionsEditor: View {
    @EnvironmentObject var model: AppModel
    var onDone: () -> Void
    @FocusState private var countFocused: Bool
    @FocusState private var eggsFocused: Bool
    @FocusState private var partialFocused: Bool
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scan options").font(.figtree(19, .bold, relativeTo: .title3)).foregroundStyle(Theme.ink)
                Text("remembered for \(model.account ?? "this account")").font(.secondary).foregroundStyle(Theme.muted)
            }
            kindPicker
            // One short line per kind (Greg, 6 Oct 2026). The long explanation of the count, the eggs and how a scan ends is no longer shown here.
            Text(model.scanKind == .full
                 ? "Put in the number of Pokémon in your storage and scan them all."
                 : "Scan part of your storage. Nothing is removed from your box." + (model.pagedByHand ? "" : " The voice command you say sets how many."))
                .font(.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if model.scanKind == .full {
                field("Number of Pokémon in storage", prompt: "Count", text: $model.storageCountText, focus: $countFocused)
                field("Maximum Eggs", prompt: "Eggs", text: $model.eggText, focus: $eggsFocused)
                if let problem = model.storageCountProblem ?? model.eggProblem {
                    Text(problem).font(.secondary).foregroundStyle(Theme.red)
                } else {
                    Text(model.eggCount == nil
                         ? "No egg count typed: the scan allows for up to \(StorageCountRules.maxEggSlots) eggs."
                         : "Expected Pokémon: the game's count less \(model.eggCount ?? 0) eggs.")
                        .font(.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            // Paging by hand has no command to size, so the number is asked for only when a voice command will be said.
            if model.scanKind == .partial, !model.pagedByHand {
                field("How many Pokémon to scan?", prompt: "200", text: $model.partialCountText, focus: $partialFocused)
                if let problem = model.partialCountProblem {
                    Text(problem).font(.secondary).foregroundStyle(Theme.red)
                } else if (model.partialCount ?? 0) > (VoiceCommandFile.setSizes.last ?? 0) {
                    Text("The largest command covers \((VoiceCommandFile.setSizes.last ?? 0).formatted()) Pokémon.").font(.secondary).foregroundStyle(Theme.orangeInk)
                } else {
                    Text("Left empty, it scans 200.").font(.secondary).foregroundStyle(Theme.muted)
                }
            }
            PillButton("Done", style: .filled) { countFocused = false; eggsFocused = false; partialFocused = false; onDone() }
        }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Hide keyboard") { countFocused = false; eggsFocused = false; partialFocused = false } } }
    }

    private var kindPicker: some View {
        HStack(spacing: 0) {
            kindButton("Full scan", .full)
            kindButton("Add and update", .partial)
        }
        .padding(4).background(Theme.off, in: Capsule())
    }

    private func kindButton(_ title: String, _ kind: BoxStore.Kind) -> some View {
        let on = model.scanKind == kind
        return Button { model.scanKind = kind } label: {
            Text(title).font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(on ? accent.onSolid : Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(on ? accent.solid : Color.clear, in: Capsule())
                .frame(minHeight: 44).contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func field(_ title: String, prompt: String, text: Binding<String>, focus: FocusState<Bool>.Binding) -> some View {
        HStack(spacing: 12) {
            Text(title).paText(.rowTitle).foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            TextField(prompt, text: text)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .font(.figtree(20, .heavy, relativeTo: .title3)).foregroundStyle(accent.ink)
                .frame(maxWidth: 120).focused(focus)
            Image(systemName: "pencil").font(.figtree(14, .bold)).foregroundStyle(accent.ink).accessibilityHidden(true)
        }
        .padding(.horizontal, 14).frame(minHeight: 56)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
    }
}
