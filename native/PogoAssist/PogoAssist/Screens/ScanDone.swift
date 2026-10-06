import SwiftUI
import PogoBox
import PogoReader

/// What the Done screen says, from the finished scan's real numbers and ending (design handoff, Scan §3m frame 4 and its note: the headline follows the outcome and
/// the button names only what needs doing). Kept apart from the view so the wording can be tested.
struct ScanDoneWords: Equatable {
    var read: Int
    var readIn: String
    var headline: String
    /// The questions the review will ask, and the rows it will ask to check in the game (before any answer).
    var questions: Int
    var toCheck: Int

    @MainActor init(_ ctx: ReviewContext) {
        let review = ctx.review
        read = review.outcome.scan.rows.count
        readIn = ReviewFormat.readIn(review.outcome.duration)
        questions = ctx.total
        toCheck = ctx.toCheck.count
        // "Your whole box" is only said for a scan that reached the end of the list and that the app judged sound as a Full scan (`ScanKindAdvice`).
        let whole = ctx.ending == .listEnd && review.kind == .full && review.advice?.fullIsSound == true
        switch ctx.ending {
        case _ where whole: headline = "That's your whole box."
        case .longPause: headline = "Stopped after a long pause."
        case .byPerson: headline = "You stopped at \(read.formatted())."
        // The end of the list was reached but the scan is not a sound Full scan: say only that.
        case .listEnd: headline = "Scan finished at the end of your list."
        case .unknown: headline = "Scan finished."
        }
    }

    /// The one button names what needs doing: the questions, or "Review and save" when there are none (it opens the review; nothing is saved by this button).
    var buttonTitle: String { questions > 0 ? ReviewFormat.count(questions, "quick question", "quick questions") : "Review and save" }

    /// Under the button: what comes next and that the rows to check in the game can wait. Each clause is left out when it would not be true.
    var subline: String? {
        let check = toCheck > 0 ? "\(toCheck.formatted()) to check in the game can wait" : nil
        if questions > 0 { return check.map { "then save · \($0)" } ?? "then save" }
        return check
    }
}

/// The Scan screen once a scan has ended and the person is back in the app: the ring complete and green with what was read, how it ended, one button into the
/// review and the sleep reminder. While the scan is still being read it says so in place of the button. The sound the design asks for is not made (the owner's call).
struct ScanDoneView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turned = false

    var body: some View {
        switch model.flow {
        case .processing(let what): processing(what)
        case .review(let review): done(ScanDoneWords(ReviewContext(review)))
        // Reading failed or the flow ended: the model has already cleared the pending state, so the Scan screen is on its way back to normal.
        default: Color.clear.frame(height: 1)
        }
    }

    private func processing(_ what: String) -> some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(what).paText(.questionTitle).foregroundStyle(Theme.ink)
            Text("This takes a few seconds. Nothing is saved yet.").paText(.secondary).foregroundStyle(Theme.muted)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity).padding(.vertical, 60)
        .accessibilityElement(children: .combine)
    }

    private func done(_ words: ScanDoneWords) -> some View {
        // Spread over the height with spacers (no fixed positions): the ring, then the headline, then the button and its line, the reminder last. At a large text size the
        // spacers shrink to their minimum and the Scan screen's scroll view takes over.
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            DoneRing(read: words.read, readIn: words.readIn, turned: turned)
            Spacer(minLength: 28)
            Text(words.headline).font(.figtree(26, .heavy, relativeTo: .title)).tracking(-0.015 * 26).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 36)
            VStack(spacing: 10) {
                openButton(words)
                if let sub = words.subline {
                    Text(sub).font(.figtree(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
            }
            Spacer(minLength: 36)
            sleepReminder
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The ring turns green as the screen comes up; with Reduce Motion it is green at once.
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { turned = true } }
    }

    private func openButton(_ words: ScanDoneWords) -> some View {
        Button { model.openReview() } label: {
            HStack(spacing: 8) {
                Text(words.buttonTitle).font(.figtree(18, .heavy, relativeTo: .title3)).multilineTextAlignment(.center)
                Image(systemName: "arrow.right").font(.figtree(16, .bold)).accessibilityHidden(true)
            }
            .foregroundStyle(accent.onSolid)
            .padding(.horizontal, 20).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(accent.solid, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("scan-done-open")
    }

    /// Shown whenever the scan has ended: the app cannot tell whether the voice command is still tapping, so it always reminds.
    private var sleepReminder: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.fill").font(.figtree(15, .bold)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            Text("Finished scanning? Say \"Go to sleep\" to turn Voice Control off.").font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 40)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous)).panelShadow()
        .accessibilityElement(children: .combine)
    }
}

/// The 240 pt mark button's ring when the scan is done: complete and green, the green disc with what was read inside. It is not a control.
private struct DoneRing: View {
    let read: Int
    let readIn: String
    let turned: Bool
    /// White on the light green, the dark ink on the lighter dark-mode green.
    private let ink = Theme.pair(0xFFFFFF, 0x0E1118)

    var body: some View {
        ZStack {
            Circle().strokeBorder(Theme.greenTint, lineWidth: 9)
            Circle().inset(by: 4.5).trim(from: 0, to: turned ? 1 : 0).stroke(Theme.green, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
            Circle().fill(turned ? Theme.green : Theme.greenTint).frame(width: 200, height: 200)
                .shadow(color: Color(red: 20 / 255, green: 30 / 255, blue: 60 / 255).opacity(0.22), radius: 15, x: 0, y: 12)
            VStack(spacing: 0) {
                Text(read.formatted()).font(.figtree(48, .heavy, relativeTo: .largeTitle)).tracking(-0.03 * 48).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                Text("read · \(readIn)").font(.figtree(15, .bold, relativeTo: .subheadline)).minimumScaleFactor(0.7).lineLimit(1)
            }
            .foregroundStyle(ink).frame(width: 170)
        }
        .frame(width: 240, height: 240)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(read.formatted()) read in \(readIn)")
    }
}

/// Over the Box and Next screens while a finished scan waits on its Done screen and the person has left it (back): one tap returns to it, so a scan is never left
/// without a way into its review.
struct ScanDonePill: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accent) private var accent
    let open: () -> Void

    private var text: String {
        if case .review(let r) = model.flow {
            let q = r.plan.unsure.count
            return q > 0 ? "Scan finished · \(ReviewFormat.count(q, "quick question", "quick questions"))" : "Scan finished · ready to save"
        }
        return "Reading the scan"
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Text(text).font(.figtree(15, .bold, relativeTo: .subheadline))
                Image(systemName: "arrow.right").font(.figtree(14, .bold)).accessibilityHidden(true)
            }
            .foregroundStyle(accent.onSolid)
            .padding(.horizontal, 18).padding(.vertical, 8).frame(minHeight: 44)
            .background(accent.solid, in: Capsule())
            .shadow(color: Color(red: 20 / 255, green: 30 / 255, blue: 60 / 255).opacity(0.22), radius: 10, x: 0, y: 6)
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .padding(.horizontal, Theme.Space.screen)
        .accessibilityIdentifier("scan-done-pill")
    }
}
