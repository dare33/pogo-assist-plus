import SwiftUI
import PogoBox
import PogoReader

/// What the person is told to say or do in the game, from what the app really knows (the count, the paging choice).
enum ScanWords: Equatable {
    /// The smallest command that covers the Full scan's count, or the Add and update number (a Re-scan puts its number there).
    case size(Int)
    /// A count or number larger than the largest command.
    case aboveLargest(Int)
    /// Add and update with no number typed: the command for the default of 200.
    case defaultSize(Int)
    /// Full scan, no usable count yet.
    case needsCount
    /// Paging by hand: no command.
    case byHand

    @MainActor static func current(_ model: AppModel) -> ScanWords {
        if model.pagedByHand { return .byHand }
        if model.scanKind == .partial {
            guard let n = model.partialCount else { return .defaultSize(VoiceCommandFile.setSize(covering: AppModel.defaultPartialCount) ?? AppModel.defaultPartialCount) }
            if let size = VoiceCommandFile.setSize(covering: n) { return .size(size) }
            return .aboveLargest(VoiceCommandFile.setSizes.last!)
        }
        if let size = model.commandSize { return .size(size) }
        if model.countAboveLargest { return .aboveLargest(VoiceCommandFile.setSizes.last!) }
        return .needsCount
    }

    /// The command size for a re-scan of `n` Pokémon to check: the smallest that covers n plus a margin, since the game's search shows a few extra matches.
    static func rescanSize(toCheck n: Int) -> Int? { VoiceCommandFile.setSize(covering: n + max(2, n / 10)) }

    /// The command to say, when there is one.
    var command: String? {
        switch self {
        case .size(let n), .aboveLargest(let n), .defaultSize(let n): return "Pogo scan \(n)"
        default: return nil
        }
    }

    /// The command as the steps show it: 200 only when nothing is known.
    var spoken: String { command ?? "Pogo scan \(AppModel.defaultPartialCount)" }
}

/// The three steps of the guide, and which of them the person has hidden ("Don't show this step again").
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

/// The guide, "Step n of 3": a full-screen cover with one step at a time.
struct ScanWalkthrough: View {
    let steps: [Int]
    let words: ScanWords
    /// Whether to say the game will be opened for the person (false once opening it has failed).
    let takesBack: Bool
    @Binding var hiddenRaw: String
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
        default: return words == .byHand ? "Page through your Pokémon by hand" : "Say \"\(words.spoken)\"."
        }
    }
    private var body_: String {
        switch step {
        case 0: return "The scan reads from this screen and moves through your storage in the order it's sorted."
        // "We'll take you back to the game" is true only while opening the game works (`GameOpener`); otherwise the person is told to switch.
        case 1: return "Pick \"Pogo Broadcast\" if asked. " + (takesBack ? "We'll take you back to the game." : GameOpener.fallbackLine)
        default: return words == .byHand ? "You swipe from one Pokémon to the next yourself. Stop the broadcast from the red bar when the last Pokémon has been read." : "Then leave the phone alone until the scan is done!"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Step \(position + 1) of \(steps.count)").font(.secondary).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    illustration
                        .frame(maxWidth: .infinity, minHeight: 260)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        if step == 2, words != .byHand {
                            // The command and the sentence run on as one big text; the note about the number sits under it in the body style (Greg, 7 Oct 2026): the number is the one the chosen scan needs.
                            Text(title + " " + body_).font(.figtree(28, .heavy, relativeTo: .title)).tracking(-0.02 * 28).foregroundStyle(Theme.ink)
                            Text("Note- the number will change depending on your chosen scan!").font(.figtree(16, .regular, relativeTo: .body)).foregroundStyle(Theme.muted)
                        } else {
                            Text(title).font(.figtree(28, .heavy, relativeTo: .title)).tracking(-0.02 * 28).foregroundStyle(Theme.ink)
                            Text(body_).font(.figtree(16, .regular, relativeTo: .body)).foregroundStyle(Theme.muted)
                        }
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
            ScanMark().frame(width: 124, height: 124).foregroundStyle(accent.markInk)
                .frame(width: 150, height: 150).background(Circle().fill(accent.solid))
        default:
            if words == .byHand {
                Image(systemName: "hand.draw").font(.system(size: 96, weight: .light)).foregroundStyle(accent.solid)
            } else {
                VStack(spacing: 10) {
                    Text("\"Wake up\"").font(.figtree(24, .heavy, relativeTo: .title2)).foregroundStyle(accent.ink)
                        .padding(.horizontal, 18).padding(.vertical, 10).background(accent.tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Image(systemName: "arrow.down").font(.figtree(18, .bold)).foregroundStyle(Theme.faint)
                    Text("\"\(words.spoken)\"").font(.figtree(24, .heavy, relativeTo: .title2)).foregroundStyle(accent.onSolid)
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
            // The guide only explains: the scan is started from the Scan screen's button.
            Button(action: onClose) {
                Text("OK, I've got it. Let's scan!").font(.figtree(17, .bold)).foregroundStyle(accent.onSolid)
                    .frame(maxWidth: .infinity, minHeight: 56).background(accent.solid, in: Capsule()).contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
        } else {
            Button { position += 1 } label: {
                Text("Next").font(.figtree(17, .bold)).foregroundStyle(accent.onSolid)
                    .frame(maxWidth: .infinity, minHeight: 56).background(accent.solid, in: Capsule()).contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
        }
    }
}
