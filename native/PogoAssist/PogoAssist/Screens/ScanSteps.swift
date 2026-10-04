import SwiftUI
import PogoBox
import PogoReader

/// What the person is told to say or do in the game, from what the app really knows (the count, the paging choice).
enum ScanWords: Equatable {
    /// Full scan with a usable count: the smallest command that covers it.
    case size(Int)
    /// Full scan of a storage larger than the largest command.
    case aboveLargest(Int)
    /// Add and update: the person picks the size.
    case anySize
    /// Full scan, no usable count yet.
    case needsCount
    /// Paging by hand: no command.
    case byHand

    @MainActor static func current(_ model: AppModel) -> ScanWords {
        if model.pagedByHand { return .byHand }
        if model.scanKind == .partial { return .anySize }
        if let size = model.commandSize { return .size(size) }
        if model.countAboveLargest { return .aboveLargest(VoiceCommandFile.setSizes.last!) }
        return .needsCount
    }

    /// The command to say, when there is one.
    var command: String? {
        switch self {
        case .size(let n), .aboveLargest(let n): return "Pogo scan \(n)"
        default: return nil
        }
    }

    /// The one-line form of step 3 of the walkthrough.
    var walkTitle: String {
        switch self {
        case .size(let n), .aboveLargest(let n): return "Say \"Wake up\", then \"Pogo scan \(n)\""
        case .anySize: return "Say \"Wake up\", then \"Pogo scan\" and a size"
        case .needsCount: return "Say \"Wake up\", then the \"Pogo scan\" command"
        case .byHand: return "Page through your Pokémon by hand"
        }
    }
    var walkBody: String {
        switch self {
        case .byHand: return "You swipe from one Pokémon to the next yourself. Stop the broadcast from the red bar when the last Pokémon has been read."
        default: return "Then leave the phone alone."
        }
    }
}

/// The three steps shown before each scan, and which of them the person has hidden ("Don't show this step again").
/// Stored in AppStorage as the hidden step numbers, comma separated.
enum ScanSteps {
    static let key = "scan.hiddenSteps"
    static let count = 3
    static func hidden(_ raw: String) -> Set<Int> { Set(raw.split(separator: ",").compactMap { Int($0) }) }
    static func raw(_ set: Set<Int>) -> String { set.sorted().map(String.init).joined(separator: ",") }
    /// The steps to show: all of them on the Guide me level, otherwise those not hidden.
    static func visible(raw: String, help: HelpLevel) -> [Int] {
        let h = hidden(raw)
        return (0..<count).filter { help == .guide || !h.contains($0) }
    }
}

/// "Before each scan · step n of 3": a full-screen cover with one step at a time.
struct ScanWalkthrough: View {
    let steps: [Int]
    let words: ScanWords
    @Binding var hiddenRaw: String
    let trigger: BroadcastTrigger
    var onClose: () -> Void
    @Environment(\.helpLevel) private var help
    @Environment(\.accent) private var accent
    @State private var position = 0

    private var step: Int { steps[min(position, steps.count - 1)] }
    private var isLast: Bool { position >= steps.count - 1 }

    private var title: String {
        switch step {
        case 0: return "Open your first Pokémon's appraisal"
        case 1: return "Tap the button, then Start Broadcast"
        default: return words.walkTitle
        }
    }
    private var body_: String {
        switch step {
        case 0: return "The scan reads from this screen and moves through your storage in the order it's sorted."
        // The design's line ends "We'll take you back to the game"; this build does not open the game, so it says what is true.
        case 1: return "Pick \"Pogo Broadcast\" if asked. Now switch to Pokémon GO."
        default: return words.walkBody
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Close", action: onClose).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.muted).frame(minWidth: 44, minHeight: 44, alignment: .leading)
                Spacer()
                Text("Step \(position + 1) of \(steps.count)").font(.secondary).foregroundStyle(Theme.muted)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    illustration
                        .frame(maxWidth: .infinity, minHeight: 260)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.figtree(28, .heavy, relativeTo: .title)).tracking(-0.02 * 28).foregroundStyle(Theme.ink)
                        Text(body_).font(.figtree(16, .regular, relativeTo: .body)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 6)
                }
                .padding(.horizontal, 24).padding(.top, 8)
            }
            VStack(spacing: 14) {
                if help != .guide { hideToggle }
                nextButton
            }
            .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 8)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    @ViewBuilder private var illustration: some View {
        switch step {
        case 0:
            Image(systemName: "list.bullet.rectangle.portrait").font(.system(size: 96, weight: .light)).foregroundStyle(accent.solid)
        case 1:
            ScanMark().frame(width: 124, height: 124).foregroundStyle(accent.onSolid)
                .frame(width: 150, height: 150).background(Circle().fill(accent.solid))
        default:
            if words == .byHand {
                Image(systemName: "hand.draw").font(.system(size: 96, weight: .light)).foregroundStyle(accent.solid)
            } else {
                VStack(spacing: 10) {
                    Text("\"Wake up\"").font(.figtree(24, .heavy, relativeTo: .title2)).foregroundStyle(accent.ink)
                        .padding(.horizontal, 18).padding(.vertical, 10).background(accent.tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Image(systemName: "arrow.down").font(.figtree(18, .bold)).foregroundStyle(Theme.faint)
                    Text(words.command.map { "\"\($0)\"" } ?? "\"Pogo scan\"").font(.figtree(24, .heavy, relativeTo: .title2)).foregroundStyle(accent.onSolid)
                        .padding(.horizontal, 18).padding(.vertical, 10).background(accent.solid, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .padding(.vertical, 20)
            }
        }
    }

    private var hideToggle: some View {
        let on = hiddenRaw.isEmpty ? false : ScanSteps.hidden(hiddenRaw).contains(step)
        return Button {
            var h = ScanSteps.hidden(hiddenRaw)
            if on { h.remove(step) } else { h.insert(step) }
            hiddenRaw = ScanSteps.raw(h)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: on ? "checkmark.square.fill" : "square").font(.figtree(20, .semibold)).foregroundStyle(on ? accent.solid : Theme.faint)
                Text("Don't show this step again").font(.figtree(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    @ViewBuilder private var nextButton: some View {
        if isLast {
            // The last step starts the scan: the whole button is the system broadcast picker (see BroadcastTrigger).
            Text("Start scanning").font(.figtree(17, .bold)).foregroundStyle(accent.onSolid)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(accent.solid, in: Capsule())
                .broadcastPicker(trigger: trigger, label: "Start scanning", shape: Capsule())
        } else {
            Button { position += 1 } label: {
                Text("Next").font(.figtree(17, .bold)).foregroundStyle(accent.onSolid)
                    .frame(maxWidth: .infinity, minHeight: 56).background(accent.solid, in: Capsule()).contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
        }
    }
}
