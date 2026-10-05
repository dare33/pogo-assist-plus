import SwiftUI

/// "Get ready to scan" (design handoff, Setup §2b): six steps with three kinds of tick (checked by the app, "you said done", to do), a progress bar, one main button for
/// the next step, and the "My phone is set up" switch. It remembers where the person is (`SetupProgress`), so leaving for iOS Settings and coming back is safe.
struct SetupChecklistView: View {
    /// Opens the next unfinished step straight away (the gentle sheet's "Open Scan setup").
    var jumpToNext = false
    @EnvironmentObject var model: AppModel
    @Environment(\.accent) private var accent
    @Environment(\.scenePhase) private var phase
    @State private var openStep: Int?
    @State private var showMore = false
    @State private var jumped = false

    private var setup: SetupProgress { model.setup }

    var body: some View {
        SetupChecklistBody(setup: model.setup, openStep: $openStep, showMore: $showMore)
            // The page carries its own large title (the design's), so the bar stays empty.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .hidesTabBar()
            .navigationDestination(item: $openStep) { SetupStepView(step: $0) }
            .navigationDestination(isPresented: $showMore) { ScanMoreView() }
            .onAppear {
                setup.refresh()
                if jumpToNext, !jumped {
                    jumped = true
                    // After the push of this page has finished, so the step is pushed onto it and not instead of it.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { openStep = setup.nextStep }
                }
            }
            .onChange(of: phase) { _, p in if p == .active { setup.refresh() } }
    }
}

private struct SetupChecklistBody: View {
    @ObservedObject var setup: SetupProgress
    @Binding var openStep: Int?
    @Binding var showMore: Bool
    @EnvironmentObject var model: AppModel
    @Environment(\.accent) private var accent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Get ready to scan").paText(.screenTitle).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                    progress
                }
                .padding(.horizontal, 6)
                Panel(padding: 0, spacing: 0) {
                    ForEach(1...SetupProgress.count, id: \.self) { n in row(n) }
                }
                Panel(spacing: 6) {
                    Toggle("My phone is set up", isOn: $setup.phoneSetUp)
                        .font(.figtree(16, .semibold, relativeTo: .body)).foregroundStyle(Theme.ink).tint(accent.solid)
                        .frame(minHeight: 44)
                    Text("Turn this on if you have already set the phone up. Every step then shows as done, and you can turn it off again. What the app checked stays checked.")
                        .font(.secondary).foregroundStyle(Theme.muted)
                }
                Panel(padding: 0, spacing: 0) {
                    InsetRow(title: "More about scanning", sub: "Paging by hand, the commands to say, stopping, pauses", icon: "text.book.closed", showsChevron: true, separator: false) { showMore = true }
                }
            }
            .padding(.horizontal, Theme.Space.screen).padding(.top, 8).padding(.bottom, 12)
        }
        .background(Theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let next = setup.nextStep {
                PillButton("Continue with step \(next)", style: .filled, height: 56) { openStep = next }
                    .padding(.horizontal, Theme.Space.screen).padding(.top, 8).padding(.bottom, 10)
                    .background(Theme.bg)
            }
        }
    }

    private var progress: some View {
        let done = setup.doneCount
        return VStack(alignment: .leading, spacing: 8) {
            Capsule().fill(Theme.off).frame(height: 8)
                .overlay(alignment: .leading) {
                    GeometryReader { g in Capsule().fill(accent.solid).frame(width: g.size.width * CGFloat(done) / CGFloat(SetupProgress.count)) }
                }
                .accessibilityHidden(true)
            Text("\(done) of \(SetupProgress.count) done").font(.secondary).foregroundStyle(Theme.muted)
        }
    }

    private func row(_ n: Int) -> some View {
        let state = setup.state(n)
        let info = SetupProgress.info[n - 1]
        let sub: String = {
            switch state {
            case .checked: return n == 2 ? "Checked · commands made" : "Checked"
            case .said: return "You said done"
            case .todo: return info.rowSub
            }
        }()
        return Button { openStep = n } label: {
            HStack(spacing: 12) {
                tick(n, state)
                VStack(alignment: .leading, spacing: 1) {
                    Text(info.rowTitle).paText(.rowTitle).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                    Text(sub).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(state == .checked ? Theme.greenInk : Theme.muted).multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.figtree(14, .bold)).foregroundStyle(Theme.faint).accessibilityHidden(true)
            }
            .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 60)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { if n < SetupProgress.count { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 62) } }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Step \(n), \(info.rowTitle)")
        .accessibilityValue(state == .checked ? "Checked by the app" : state == .said ? "You said done" : "To do")
        .accessibilityHint(info.rowSub)
        .accessibilityIdentifier("setup-step-\(n)")
    }

    /// Checked: solid green. You said done: accent tint with a tick. To do: the step number on a neutral well.
    @ViewBuilder private func tick(_ n: Int, _ state: SetupProgress.StepState) -> some View {
        ZStack {
            switch state {
            case .checked:
                Circle().fill(Theme.green)
                Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
            case .said:
                Circle().fill(accent.tint)
                Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(accent.ink)
            case .todo:
                Circle().fill(Theme.surface2)
                Text("\(n)").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 34, height: 34).accessibilityHidden(true)
    }
}
