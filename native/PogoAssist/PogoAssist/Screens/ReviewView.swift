import SwiftUI
import PogoBox
import PogoReader

/// What a finished scan found and what saving it would do to the box. Nothing changes until "Save to box".
/// UI v1 (design handoff v2 section 1a): a scroll of panels on the background, the result and its questions first, a bottom bar with Discard and Save.
struct ReviewView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmDiscard = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch model.flow {
            case .idle: Color.clear
            case .processing(let what): processing(what)
            case .failed(let message, _): failed(message)
            case .review: ReviewFlowScreen()
            }
        }
        // The cover is a new presentation: it needs the theme (accent, colour scheme, toast host) of its own.
        .themeRoot()
        .interactiveDismissDisabled()
    }

    private func processing(_ what: String) -> some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(what).paText(.questionTitle).foregroundStyle(Theme.ink)
            Text("This takes a few seconds. Nothing is saved yet.").paText(.secondary).foregroundStyle(Theme.muted)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundStyle(Theme.orange)
            Text("The scan could not be read").paText(.screenTitle).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            Text(message).paText(.secondary).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            PillButton("Try again", style: .filled) { model.retryReview() }
            PillButton("Discard scan", style: .plain, isDestructive: true) { confirmDiscard = true }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The same question as the result screen's Discard.
        .confirmationDialog("Discard this scan?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard scan", role: .destructive) { model.discardReview() }
        } message: { Text("Nothing will be added to the box.") }
    }
}

/// The pages pushed from the result (`guide`: the Guide me level's one-question-per-screen flow).
enum ReviewPage: Hashable { case toCheck, notSeen, guide }

/// The result screen and the pages pushed from it (To check, Not seen). Each page reads the review live from the model, so an answer given on one shows on the others.
private struct ReviewFlowScreen: View {
    @State private var path: [ReviewPage] = []

    var body: some View {
        NavigationStack(path: $path) {
            ResultScreen(path: $path)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: ReviewPage.self) { page in
                    Group {
                        switch page {
                        case .toCheck: ToCheckScreen(close: { path.removeLast() })
                        case .notSeen: NotSeenScreen(close: { path.removeLast() })
                        case .guide: GuideScreen(close: { path.removeLast() })
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
        }
    }
}
