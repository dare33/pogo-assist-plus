import SwiftUI
import PogoBox
import PogoReader

/// The Scan screen (design handoff, "Magic scan", Scan §3m): the reminder, the 240 pt mark button and a bottom panel with the options summary
/// and the two steps. Edit swaps the steps for the options. If the app is opened while a broadcast runs, the same button is the progress ring.
/// Everything the old screen held that has no place here is in "Get ready to scan" (`SetupChecklistView`) and "More about scanning" (`ScanMoreView`).
struct ScanView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.helpLevel) private var help
    @Environment(\.accent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @ScaledMetric(relativeTo: .subheadline) private var badgeSize: CGFloat = 36
    @AppStorage(ScanSteps.key) private var hiddenRaw = ""
    /// Editing the options replaces the steps. Decided once on appearing: the first scan for an account (nothing to confirm yet) opens in Edit.
    @State private var editing = false
    @State private var decidedEditing = false
    @State private var walkSteps: [Int]?
    /// "Get ready to scan" is open (`jump`: at the next unfinished step), and the gentle sheet that comes before a scan while setup is not done.
    @State private var setupPage: SetupPage?
    @State private var showSetupSheet = false
    /// "Scan anyway" was pressed: the start (the walkthrough, or the system picker) waits until the sheet has gone, since iOS can refuse to present during a dismissal.
    @State private var startAfterSheet = false
    /// The screen showed no scan running since it appeared: only then is a broadcast that goes live one this screen started (see `GameOpener`).
    @State private var sawNoScan = false
    /// The steps were shown by themselves the first time this screen was opened (Greg, 6 Oct 2026); afterwards they come when a scan is started, or from the "?" button.
    @AppStorage("scan.firstWalkShown") private var firstWalkShown = false
    enum SetupPage: Hashable { case checklist, nextStep }
    /// UI tests start from a clean install on every launch (`-uitest-reset`) and would meet the steps each time: there they come by themselves only with `-first-walk`.
    private static var firstWalkAllowed: Bool {
        #if DEBUG
        let args = CommandLine.arguments
        return !args.contains("-uitest-reset") || args.contains("-first-walk")
        #else
        return true
        #endif
    }
    @StateObject private var markTrigger = BroadcastTrigger()
    @StateObject private var walkTrigger = BroadcastTrigger()

    private var words: ScanWords { ScanWords.current(model) }
    private var visibleSteps: [Int] { ScanSteps.visible(raw: hiddenRaw, help: help) }
    /// The button can start a scan: not while editing, and a Full scan needs its count first.
    private var canStart: Bool { !editing && !model.fullScanNeedsCount }
    /// Setup is not done and the scan is paged by voice: the mark button asks first (paging by hand skips it).
    private var asksAboutSetup: Bool { !model.setup.isDone && !model.pagedByHand }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    if !SharedStore.containerAvailable {
                        Panel(tint: .orange) { Text("The app group is not available, so a scan cannot reach the app. Check Signing and Capabilities on both targets.").font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.red) }
                    }
                    if model.live {
                        markButton.padding(.top, 24)
                        liveStatus
                        Spacer(minLength: 0)
                    } else if model.scanDonePending {
                        // A scan has ended and is waiting for the person: its Done state, not the start screen.
                        ScanDoneView()
                    } else {
                        SetupBanner { setupPage = .checklist }
                        // With the options open the panel is long: no spare space around the button then.
                        if !editing { Spacer(minLength: 0) }
                        // About voice paging, like the sheet: not shown when paging by hand is selected.
                        if !editing, asksAboutSetup { SetupLeftLine(left: model.setup.stepsLeft) { setupPage = .checklist } }
                        markButton
                        if !editing { Spacer(minLength: 0) }
                        bottomPanel
                    }
                }
                .padding(.horizontal, Theme.Space.screen).padding(.top, 8).padding(.bottom, 14)
                .frame(minHeight: geo.size.height)
                .id("top")
            }
            // Leaving Edit would otherwise keep the scroll position the long options panel and the keyboard left behind.
            .onChange(of: editing) { _, _ in withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("top", anchor: .top) } }
            }
        }
        #if DEBUG
        // UI tests only: what `GameOpener` was asked to open, as "count url,url". Nothing on screen.
        .overlay(alignment: .topLeading) {
            Color.clear.frame(width: 4, height: 4).accessibilityElement(children: .ignore)
                .accessibilityLabel("\(model.game.requests.count) " + model.game.requests.map(\.absoluteString).joined(separator: ",")).accessibilityIdentifier("game-open-log")
        }
        #endif
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Scan Pokémon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { AccountPill(locksWhileReviewing: true) }
            ToolbarItem(placement: .topBarTrailing) {
                if !model.scanDonePending {
                    Button { hiddenRaw = ""; if !model.live { walkSteps = Array(0..<ScanSteps.count) } } label: {
                        Image(systemName: "questionmark").font(.figtree(16, .bold)).foregroundStyle(Theme.muted)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Show the steps again")
                }
            }
        }
        .navigationDestination(item: $setupPage) { page in SetupChecklistView(jumpToNext: page == .nextStep) }
        .sheet(isPresented: $showSetupSheet, onDismiss: { if startAfterSheet { startAfterSheet = false; startScan() } }) {
            SetupSheet(openSetup: { showSetupSheet = false; setupPage = .nextStep },
                       scanAnyway: { startAfterSheet = true; showSetupSheet = false })
                .environment(\.accent, accent)
        }
        .fullScreenCover(isPresented: Binding(get: { walkSteps != nil }, set: { if !$0 { walkSteps = nil } })) {
            if let steps = walkSteps {
                ScanWalkthrough(steps: steps, words: words, takesBack: !model.game.failed, hiddenRaw: $hiddenRaw, trigger: walkTrigger) { walkSteps = nil }
                    .environment(\.accent, accent)
            }
        }
        // The broadcast has started: the steps have done their job.
        .onChange(of: model.live) { _, live in
            if live { walkSteps = nil; model.game.consider(model.broadcast, screenSawNoScan: sawNoScan) } else { sawNoScan = true }
        }
        // While the system's broadcast sheet is up the app is inactive: the game is opened when the app is active again (once per started broadcast).
        .onChange(of: phase) { _, p in
            if p == .active { model.setup.refresh(); model.game.consider(model.broadcast, screenSawNoScan: sawNoScan) }
        }
        .onChange(of: model.account) { _, _ in editing = model.fullScanNeedsCount }
        // The permission is asked when the paging choice changes or the commands are made; a phone that already has both would never be asked, so ask once here too
        // (not while a share sheet is up).
        .onAppear {
            if !decidedEditing { decidedEditing = true; editing = model.fullScanNeedsCount }
            sawNoScan = !model.live
            // A UI test's clean install counts as a first visit already made, so a later launch of the same test does not meet the steps either.
            if !Self.firstWalkAllowed { firstWalkShown = true }
            if !firstWalkShown, !model.live, !model.isReviewing, !visibleSteps.isEmpty {
                firstWalkShown = true
                let steps = visibleSteps
                DispatchQueue.main.async { walkSteps = steps }
            }
            // Only a broadcast started with this screen's own control takes the person back to the game (`GameOpener`): both pickers report their press.
            let game = model.game
            markTrigger.onPress = { game.noteStartPressed() }
            walkTrigger.onPress = { game.noteStartPressed() }
            model.setup.refresh()
            model.setup.backfillFromSavedScans(model: model)
            if !model.pagedByHand, model.commandSetMade, model.shareURLs.isEmpty { model.askForNotificationsOnce() }
            #if DEBUG
            ScanDebug.installIfAsked(startPressed: { game.noteStartPressed() })
            #endif
        }
    }

    // MARK: - ready

    @ViewBuilder private var markButton: some View {
        let live = model.live
        let paused = model.broadcast?.paused == true
        let face = ScanButtonFace(read: live ? model.broadcast?.readCount : nil, expected: expectedCount, dimmed: !live && !canStart)
        if live {
            // Only a paused scan can be ended from the app (the request is honoured at a pause); otherwise the button shows the count and is not a control.
            if paused {
                Button { model.finishPausedScanNow() } label: { face }.buttonStyle(.plain)
                    .accessibilityLabel("Finish now, \(face.spoken)")
            } else {
                face.accessibilityElement(children: .ignore).accessibilityLabel("Scanning, \(face.spoken)")
            }
        } else if !canStart {
            Button {} label: { face }.buttonStyle(.plain).disabled(true).accessibilityLabel("Start scan")
        } else if !visibleSteps.isEmpty || asksAboutSetup {
            // The walkthrough, or the setup sheet first. With every step hidden the sheet's "Scan anyway" fires the system picker, which sits invisibly behind the button.
            Button { if asksAboutSetup { showSetupSheet = true } else { startScan() } } label: { face }.buttonStyle(.plain).accessibilityLabel("Start scan")
                .broadcastPickerBehind(trigger: markTrigger)
        } else {
            // Every step hidden: the button itself starts the broadcast (the system picker, laid invisibly over it).
            face.broadcastPicker(trigger: markTrigger, shape: Circle())
        }
    }

    /// What "Start scan" does once nothing is in the way: the walkthrough, or (every step hidden) the system broadcast picker.
    private func startScan() {
        if !visibleSteps.isEmpty { walkSteps = visibleSteps } else { markTrigger.fire() }
    }

    /// What the scan is expected to read, when the count is known (the same arithmetic as the old status line).
    private var expectedCount: Int? {
        guard let s = model.broadcast, model.live, let c = s.storageCount else { return nil }
        return StorageCountRules.expected(count: c, eggs: s.eggCount) ?? c
    }

    private var bottomPanel: some View {
        Panel(spacing: 14) {
            if editing {
                ScanOptionsEditor { editing = false }
            } else {
                ScanOptionsSummary { editing = true }
                steps
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                badge("1", on: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tap the button, then Start Broadcast").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                    // "We'll take you back to the game" only while opening the game has not failed (`GameOpener`); otherwise the person is told to switch.
                    Text(model.game.failed ? GameOpener.fallbackLine : "We'll take you back to the game.").font(.figtree(13, .regular, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                }
            }
            .accessibilityElement(children: .combine)
            stepTwo
            notes
        }
    }

    private func badge(_ n: String, on: Bool) -> some View {
        Text(n).font(.figtree(14, .heavy, relativeTo: .subheadline)).foregroundStyle(on ? accent.ink : Theme.muted)
            .frame(width: badgeSize, height: badgeSize).background(on ? accent.tint : Theme.surface2, in: Circle()).accessibilityHidden(true)
    }

    @ViewBuilder private var stepTwo: some View {
        switch words {
        case .size, .aboveLargest:
            say(words.command ?? "")
        case .anySize:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) { badge("2", on: true); Text("In the game, say \"Wake up\" first, then").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink) }
                Text("\"Pogo scan\" and the size that covers the Pokémon you want to scan, counting from the one on screen. A command pages that many; if the list ends first, the scan usually ends by itself. The sizes are in More about scanning (Get ready to scan).")
                    .font(.secondary).foregroundStyle(Theme.muted)
            }
        case .needsCount:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 14) { badge("2", on: true); Text("In the game, say \"Wake up\" first, then the \"Pogo scan\" command").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink) }
                Text("Type how many Pokémon are in your storage (Edit) to see which command to say.").font(.secondary).foregroundStyle(Theme.muted)
            }
        case .byHand:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 14) { badge("2", on: true); Text("Page through the Pokémon by hand").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink) }
                Text("You swipe from one Pokémon to the next yourself. Twins are not told apart by the paging beat, and the scan does not end by itself: stop the broadcast from the red bar when the last Pokémon has been read.")
                    .font(.secondary).foregroundStyle(Theme.muted)
            }
        }
    }

    /// ② In the game, say FIRST "Wake up" THEN "Pogo scan N".
    private func say(_ command: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) { badge("2", on: true); Text("In the game, say").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { phrase("FIRST", "\"Wake up\"", solid: false); phrase("THEN", "\"\(command)\"", solid: true) }
                VStack(spacing: 8) { phrase("FIRST", "\"Wake up\"", solid: false); phrase("THEN", "\"\(command)\"", solid: true) }
            }
        }
    }

    private func phrase(_ label: String, _ text: String, solid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.figtree(11, .heavy, relativeTo: .caption2)).tracking(0.06 * 11).opacity(solid ? 0.8 : 0.75)
            Text(text).font(.figtree(18, .heavy, relativeTo: .title3)).minimumScaleFactor(0.8).lineLimit(1)
        }
        .foregroundStyle(solid ? accent.onSolid : accent.ink)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(solid ? accent.solid : accent.tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// The things that are true now and that the person needs to see before starting, in the old screen's words.
    @ViewBuilder private var notes: some View {
        if model.fullScanNeedsCount {
            Text("Type the number of Pokémon the game shows on its storage screen (Edit) before a Full scan. It needs the count to tell the end of your list from a stall.").font(.secondary).foregroundStyle(Theme.orangeInk)
        }
        if case .aboveLargest(let largest) = words {
            Text("The largest command covers \(largest.formatted()) Pokémon. Scans of a storage this large are Add and update (nothing is proposed as gone): scan the first \(largest.formatted()), then the rest with a second scan.").font(.secondary).foregroundStyle(Theme.orangeInk)
        }
        if !model.pagedByHand, let warning = model.commandWarning {
            Text(warning).font(.secondary).foregroundStyle(Theme.orangeInk)
            Text("The scan ends by itself only with the commands: get them first (Get ready to scan, step 2). Until then nothing ends the scan but you, from the red bar.").font(.secondary).foregroundStyle(Theme.muted)
        }
        if let warning = model.tapCommandWarning {
            Label(warning, systemImage: "exclamationmark.octagon.fill").font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.red)
        }
        if model.endedWithoutFinish {
            Text("The last broadcast stopped without finishing. Its readings will be offered for review.").font(.secondary).foregroundStyle(Theme.muted)
        }
    }

    // MARK: - scanning

    /// The extension saw five cards in a row with no CP (`CoveredCpDetector`): while it lasts, and once it has cleared, say so under the ring. No sound and no notification: the extension already vibrated.
    private func coveredPanel(_ s: BroadcastState) -> some View {
        let first = s.cpCoveredFirstName.flatMap { $0.isEmpty ? nil : $0 }
        let good = s.cpCoveredLastGoodName.flatMap { $0.isEmpty ? nil : $0 }
        let title: String, text: String
        if s.cpCovered {
            title = "Something may be covering the CP"
            text = (first.map { "From \($0) on, several Pokémon in a row showed no CP." } ?? "Several Pokémon in a row showed no CP.") + " A banner or an alarm is probably over the top of the screen: clear it in the game. The scan keeps going."
        } else {
            let n = s.cpCoveredStretches
            title = n > 1 ? "The CP was covered \(n) times" : "The CP was covered for a while"
            var parts = [String]()
            if let first {
                var start = (n > 1 ? "The latest time started at " : "It started at ") + first
                if let good { start += ", right after \(good)" + (s.cpCoveredLastGoodCp.map { " CP \($0)" } ?? "") }
                parts.append(start + ".")
            }
            parts.append("When the scan ends, the result shows which ones to check or read again.")
            text = parts.joined(separator: " ")
        }
        return Panel(tint: .orange, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle.fill").font(.figtree(16, .heavy, relativeTo: .body)).foregroundStyle(Theme.orangeInk)
            Text(text).font(.secondary).foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cp-covered-panel")
    }

    @ViewBuilder private var liveStatus: some View {
        let s = model.broadcast
        VStack(spacing: 10) {
            Text("Scan in progress").font(.figtree(20, .heavy, relativeTo: .title3)).foregroundStyle(Theme.ink)
            Text("\(s?.framesRead ?? 0) frames read, \(s?.readCount ?? 0) Pokémon so far" + (expectedCount.map { " of about \($0.formatted())" } ?? ""))
                .font(.secondary).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            if let s, s.cpCoveredStretches > 0 { coveredPanel(s) }
            if let s, s.paused {
                Panel(tint: .orange) {
                    Label(ScanNotification.paused(scan: s.scanId, event: s.eventSeq, read: s.readCount, storageCount: s.storageCount, eggCount: s.eggCount, lastName: s.pausedCard, lastCP: nil, sizes: VoiceCommandFile.setSizes, limitSeconds: s.pauseLimitSeconds).body, systemImage: "pause.circle.fill")
                        .font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.orangeInk)
                    PillButton("Finish now", style: .plain, isDestructive: true) { model.finishPausedScanNow() }
                }
            }
            if model.game.failed { Text(GameOpener.fallbackLine).font(.figtree(16, .bold, relativeTo: .body)).foregroundStyle(Theme.ink).accessibilityIdentifier("game-fallback") }
            Text(s?.commandPeriod != nil ? "The scan usually ends by itself when the list ends or the command runs out; if it does not, stop the broadcast from the red bar. Come back here when the broadcast stops." : "Stop the broadcast from the red bar when the last Pokémon has been read, then come back here.")
                .font(.secondary).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
    }
}

/// The 240 pt button: the progress ring (222 pt hole, 200 pt disc) with the scan mark, or the count while scanning.
struct ScanButtonFace: View {
    /// Pokémon read so far while a scan runs; nil when no scan runs (the mark shows).
    var read: Int?
    var expected: Int?
    var dimmed = false
    @Environment(\.accent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var spoken: String { read.map { r in "\(r.formatted()) read" + (expected.map { " of about \($0.formatted())" } ?? "") } ?? "" }
    private var fraction: Double { (read != nil && (expected ?? 0) > 0) ? min(1, Double(read ?? 0) / Double(expected ?? 1)) : 0 }

    var body: some View {
        ZStack {
            Circle().strokeBorder(accent.tint, lineWidth: 9)
            Circle().inset(by: 4.5).trim(from: 0, to: fraction).stroke(accent.solid, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: fraction)
            Circle().fill(accent.solid).frame(width: 200, height: 200)
                .shadow(color: Color(red: 20 / 255, green: 30 / 255, blue: 60 / 255).opacity(0.22), radius: 15, x: 0, y: 12)
            if let read {
                VStack(spacing: 0) {
                    Text(read.formatted()).font(.figtree(48, .heavy, relativeTo: .largeTitle)).tracking(-0.03 * 48).monospacedDigit()
                        .minimumScaleFactor(0.6).lineLimit(1)
                    if let expected { Text("of about \(expected.formatted())").font(.figtree(14, .bold, relativeTo: .subheadline)).opacity(0.8).minimumScaleFactor(0.7).lineLimit(1) }
                }
                .foregroundStyle(accent.onSolid).frame(width: 170)
            } else {
                ScanMark().frame(width: 176, height: 176).foregroundStyle(accent.onSolid)
            }
        }
        .frame(width: 240, height: 240)
        .opacity(dimmed ? 0.45 : 1)
        .contentShape(Circle())
    }
}
