import SwiftUI
import PogoBox
import PogoReader

/// The Scan screen (design handoff, "Magic scan", Scan §3m): the reminder, the 240 pt mark button and a bottom panel with the options summary
/// and the six steps. Scan Options swaps the steps for the options; the steps can be folded away (Show less). If the app is opened while a broadcast runs, the same button is the progress ring.
/// Everything the old screen held that has no place here is in "Get ready to scan" (`SetupChecklistView`) and "More about scanning" (`ScanMoreView`).
struct ScanView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.helpLevel) private var help
    @Environment(\.accent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @ScaledMetric(relativeTo: .subheadline) private var badgeSize: CGFloat = 36
    @AppStorage(ScanSteps.key) private var hiddenRaw = ""
    /// Editing the options replaces the steps. Decided once on appearing: the options card is always the first view of the start screen (Greg, 7 Oct 2026); "Done" then shows the steps.
    @State private var editing = false
    @State private var decidedEditing = false
    @State private var walkSteps: [Int]?
    /// The picture of the game's appraisal screen, opened from the word in step 1.
    @State private var showAppraisal = false
    /// "Show less" folds the six steps away and keeps the options row and the warnings; remembered on the device. A UI test's clean install clears it with the rest of the defaults.
    @AppStorage("scan.stepsCollapsed") private var stepsCollapsed = false
    /// "Get ready to scan" is open (`jump`: at the next unfinished step), and the gentle sheet that comes before a scan while setup is not done.
    @State private var setupPage: SetupPage?
    @State private var showSetupSheet = false
    /// "Scan anyway" was pressed: the start (the system picker) waits until the sheet has gone, since iOS can refuse to present during a dismissal.
    @State private var startAfterSheet = false
    /// The screen showed no scan running since it appeared: only then is a broadcast that goes live one this screen started (see `GameOpener`).
    @State private var sawNoScan = false
    /// The guide opens by itself the first time this screen is opened (Greg, 6 Oct 2026); afterwards only from the "?" button. Starting a scan never opens it.
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
    /// Heights of the banner, the setup line and the panel (`FixedHeights`): what the mark button has left to share, so it can shrink on a short phone instead of pushing "Show less" off the screen.
    @State private var fixedHeights: CGFloat = 0

    /// The least free height above and below the mark button, and the sizes it may take.
    private static let markGap: CGFloat = 12
    private static let markMax: CGFloat = 240, markMin: CGFloat = 200
    private var words: ScanWords { ScanWords.current(model) }
    private var visibleSteps: [Int] { ScanSteps.visible(raw: hiddenRaw, help: help) }
    /// The button can start a scan: not while editing, and a Full scan needs its count first.
    private var canStart: Bool { !editing && !model.fullScanNeedsCount }
    /// Setup is not done and the scan is paged by voice: the mark button asks first (paging by hand skips it).
    private var asksAboutSetup: Bool { !model.setup.isDone && !model.pagedByHand }

    var body: some View {
        GeometryReader { geo in
            // 240 pt when the card fits under it; down to 200 pt only when the screen is too short for the card (Greg, 7 Oct 2026: "Show less" fully visible).
            let markSize = max(Self.markMin, min(Self.markMax, geo.size.height - fixedHeights - 8 - 14 - 2 * Self.markGap))
            ScrollViewReader { proxy in
            ScrollView {
                // No automatic gaps: the start screen's spacers share the free height, and their minimum is the gap, so a full card costs no more than it must.
                VStack(spacing: 0) {
                    if !SharedStore.containerAvailable {
                        Panel(tint: .orange) { Text("The app group is not available, so a scan cannot reach the app. Check Signing and Capabilities on both targets.")
.font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.red) }.padding(.bottom, 20)
                    }
                    if model.live {
                        markButton(size: Self.markMax).padding(.top, 24).padding(.bottom, 20)
                        liveStatus
                        Spacer(minLength: 0)
                    } else if model.scanDonePending {
                        // A scan has ended and is waiting for the person: its Done state, not the start screen.
                        ScanDoneView()
                    } else {
                        SetupBanner { setupPage = .checklist }.measured()
                        // The same two spacers with the options open or not: the card always ends at the bottom and the button sits centred in what is left, so changing view moves as little as possible.
                        Spacer(minLength: Self.markGap)
                        // About voice paging, like the sheet: not shown when paging by hand is selected.
                        if !editing, asksAboutSetup { SetupLeftLine(left: model.setup.stepsLeft) { setupPage = .checklist }.padding(.bottom, 12).measured() }
                        markButton(size: markSize)
                        Spacer(minLength: Self.markGap)
                        bottomPanel.measured()
                    }
                }
                .padding(.horizontal, Theme.Space.screen).padding(.top, 8).padding(.bottom, 14)
                // Top-aligned: with the default centre, content shorter than the screen (the options first) floated down and left a gap under the card.
                .frame(minHeight: geo.size.height, alignment: .top)
                .onPreferenceChange(FixedHeights.self) { fixedHeights = $0 }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: editing)
                .id("top")
            }
            // Leaving the options would otherwise keep the scroll position the long options panel and the keyboard left behind.
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
                    // The pages the person has hidden stay hidden; with all of them hidden the "?" shows them all again.
                    Button {
                        if hiddenRaw != "", visibleSteps.isEmpty { hiddenRaw = "" }
                        if !model.live { walkSteps = visibleSteps }
                    } label: {
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
        .sheet(isPresented: $showAppraisal) {
            AppraisalSheet { showAppraisal = false }
                .presentationDetents([.large]).presentationCornerRadius(Theme.Radius.sheet).presentationDragIndicator(.visible)
                .environment(\.accent, accent)
        }
        .fullScreenCover(isPresented: Binding(get: { walkSteps != nil }, set: { if !$0 { walkSteps = nil } })) {
            if let steps = walkSteps {
                ScanWalkthrough(steps: steps, words: words, takesBack: !model.game.failed, hiddenRaw: $hiddenRaw) { walkSteps = nil }
                    .environment(\.accent, accent)
            }
        }
        // The broadcast has started: the guide, if it was open, has done its job.
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
            sawNoScan = !model.live
            // A UI test's clean install counts as a first visit already made, so a later launch of the same test does not meet the guide either.
            if !Self.firstWalkAllowed { firstWalkShown = true }
            let firstVisit = !firstWalkShown && !model.live && !model.isReviewing
            // The start screen always opens on the options (behind the guide, on a first visit): Done shows the steps. Pushed fresh each time, so this is every open.
            if !decidedEditing { decidedEditing = true; editing = (!model.live && !model.scanDonePending) || model.fullScanNeedsCount }
            if firstVisit {
                firstWalkShown = true
                let steps = visibleSteps
                if !steps.isEmpty { DispatchQueue.main.async { walkSteps = steps } }
            }
            // Only a broadcast started with this screen's own control takes the person back to the game (`GameOpener`): the mark button's picker reports its press (a touch, or `fire()` from "Scan anyway").
            let game = model.game
            markTrigger.onPress = { game.noteStartPressed() }
            model.setup.refresh()
            model.setup.backfillFromSavedScans(model: model)
            if !model.pagedByHand, model.commandSetMade, model.shareURLs.isEmpty { model.askForNotificationsOnce() }
            #if DEBUG
            ScanDebug.installIfAsked(startPressed: { game.noteStartPressed() })
            #endif
        }
    }

    // MARK: - ready

    @ViewBuilder private func markButton(size: CGFloat) -> some View {
        let live = model.live
        let paused = model.broadcast?.paused == true
        let face = ScanButtonFace(size: size, read: live ? model.broadcast?.readCount : nil, expected: expectedCount, dimmed: !live && !canStart)
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
        } else if asksAboutSetup {
            // The setup sheet first: its "Scan anyway" fires the system picker, which sits invisibly behind the button.
            Button { showSetupSheet = true } label: { face }.buttonStyle(.plain).accessibilityLabel("Start scan")
                .broadcastPickerBehind(trigger: markTrigger)
        } else {
            // The button itself starts the broadcast (the system picker, laid invisibly over it).
            face.broadcastPicker(trigger: markTrigger, shape: Circle())
        }
    }

    /// What "Start scan" does once nothing is in the way: the system broadcast picker.
    private func startScan() { markTrigger.fire() }

    /// What the scan is expected to read, when the count is known (the same arithmetic as the old status line).
    private var expectedCount: Int? {
        guard let s = model.broadcast, model.live, let c = s.storageCount else { return nil }
        return StorageCountRules.expected(count: c, eggs: s.eggCount) ?? c
    }

    private var bottomPanel: some View {
        Panel(spacing: 10) {
            if editing {
                // The options open first, so the re-scan line must not be left behind them; its own identifier, as only one copy is on screen at a time.
                rescanLine("rescan-line-editing")
                ScanOptionsEditor { editing = false }
            } else {
                ScanOptionsSummary { model.rescanCount = nil; editing = true }
                rescanLine("rescan-line")
                if !stepsCollapsed { steps }
                // The warnings explain a dimmed button, so they stay when the steps are folded away.
                notes
                stepsToggle
            }
        }
    }

    @ViewBuilder private func rescanLine(_ id: String) -> some View {
        if let n = model.rescanCount {
            Text("Re-scan of \(n.formatted()) to check: paste the search into the game's storage, open the first one's appraisal, then start.")
                .font(.secondary).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(id)
        }
    }

    /// Folds the steps away. The two spacers around the mark button share the height this frees, so the button moves down with the card's top edge.
    private var stepsToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { stepsCollapsed.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(stepsCollapsed ? "Show more" : "Show less")
                Image(systemName: stepsCollapsed ? "chevron.down" : "chevron.up").font(.figtree(12, .bold)).accessibilityHidden(true)
            }
            .font(.figtree(14, .semibold, relativeTo: .subheadline)).foregroundStyle(accent.ink)
            .frame(maxWidth: .infinity, minHeight: 40).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        // The panel's own bottom padding stands in for the row's spare height, so "Show less" is fully on screen on the tallest phone without scrolling (Greg, 7 Oct 2026).
        .padding(.bottom, -10)
        .accessibilityLabel(stepsCollapsed ? "Show more" : "Show less")
        .accessibilityIdentifier("scan-steps-toggle")
    }

    /// Step 1's "appraisal": a link to nowhere outside the app (`openURL` below keeps it in), bold and in the accent colour.
    private var step1Text: Text {
        var s = (try? AttributedString(markdown: "In Pokémon Go, open the [appraisal](pogoassist://appraisal) of the Pokémon you want to start at.")) ?? AttributedString("In Pokémon Go, open the appraisal of the Pokémon you want to start at.")
        if let r = s.runs.first(where: { $0.link != nil })?.range {
            s[r].font = .figtree(15, .heavy, relativeTo: .subheadline)
            s[r].foregroundColor = accent.ink
            s[r].underlineStyle = .single
        }
        return Text(s)
    }

    /// The six steps (Greg, 6 Oct 2026). Paging by hand leaves out the Voice Control step and swipes itself.
    private var steps: some View {
        let byHand = words == .byHand
        return VStack(alignment: .leading, spacing: 10) {
            step("1", step1Text)
                .accessibilityAction(named: "Show the appraisal screen") { showAppraisal = true }
                .accessibilityIdentifier("scan-step-1")
            if !byHand { step("2", Text("Make sure Voice Control is on. Not sure? Say \"Wake up\".")) }
            step("3", Text("Choose your scan options above."))
            // "We'll take you back to the game" only while opening the game has not failed (`GameOpener`); otherwise the person is told to switch. One text, in the step's own font (Greg, 7 Oct 2026).
            step("4", Text("Tap the Pogo Assist button, then Start Broadcast, then close that sheet. " + (model.game.failed ? GameOpener.fallbackLine : "We'll take you back to the game.")))
            if byHand {
                step("5", Text("Back in the game, swipe from one Pokémon to the next yourself."), small: "The scan does not end by itself: stop the broadcast from the red bar when the last one has been read.")
            } else {
                step("5", Text("Back in the game, say ") + Text("\"\(words.spoken)\"").bold().foregroundStyle(accent.ink) + Text("."))
            }
            step("6", Text("When the scan ends, come back to Pogo Assist to meet your new Pokémon or export your collection."))
        }
        // Nothing is opened outside the app: the only link is step 1's.
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "pogoassist", url.host == "appraisal" { showAppraisal = true }
            return .handled
        })
    }

    private func step(_ n: String, _ text: Text, small: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 14) {
            badge(n, on: false)
            VStack(alignment: .leading, spacing: 2) {
                text.font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if let small { Text(small).font(.figtree(13, .regular, relativeTo: .footnote)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func badge(_ n: String, on: Bool) -> some View {
        Text(n).font(.figtree(14, .heavy, relativeTo: .subheadline)).foregroundStyle(on ? accent.ink : Theme.muted)
            .frame(width: badgeSize, height: badgeSize).background(on ? accent.tint : Theme.surface2, in: Circle()).accessibilityHidden(true)
    }

    /// The things that are true now and that the person needs to see before starting, in the old screen's words.
    @ViewBuilder private var notes: some View {
        if model.fullScanNeedsCount {
            Text("Type the number of Pokémon the game shows on its storage screen (Scan Options) before a Full scan. It needs the count to tell the end of your list from a stall.").font(.secondary).foregroundStyle(Theme.orangeInk)
        }
        if case .aboveLargest(let largest) = words {
            Text(model.scanKind == .partial
                 ? "The largest command covers \(largest.formatted()) Pokémon. Scan the first \(largest.formatted()), then the rest with a second scan."
                 : "The largest command covers \(largest.formatted()) Pokémon. Scans of a storage this large are Add and update (nothing is proposed as gone): scan the first \(largest.formatted()), then the rest with a second scan.")
                .font(.secondary).foregroundStyle(Theme.orangeInk)
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
    /// 240 pt unless the Scan screen is short of room (never below 200).
    var size: CGFloat = 240
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
        .scaleEffect(size / 240)
        .frame(width: size, height: size)
        .opacity(dimmed ? 0.45 : 1)
        .contentShape(Circle())
    }
}

/// The game's appraisal screen, so the person knows what to open before starting (step 1). The picture is the owner's own screenshot, cropped to the game's screen.
struct AppraisalSheet: View {
    var onDone: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The appraisal screen").paText(.screenTitle).foregroundStyle(Theme.ink)
                    Text("Have this screen open in Pokémon GO before you start: open the Pokémon in your storage, tap the menu at the bottom right, then Appraise.")
                        .font(.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    Image("scan-appraisal").resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                        // Whole picture in view without scrolling on a large sheet (the scroll is for the largest text sizes).
                        .frame(maxWidth: .infinity, maxHeight: 560)
                        .accessibilityLabel("The appraisal screen in Pokémon GO, shown for a Cinderace")
                }
                .padding(.horizontal, Theme.Space.screen).padding(.top, 28)
            }
            PillButton("Done", style: .filled, action: onDone).padding(.horizontal, Theme.Space.screen).padding(.bottom, 14)
        }
        .background(Theme.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("appraisal-sheet")
    }
}

/// The heights of the views that do not flex on the start screen, added up (`ScanView.fixedHeights`).
private struct FixedHeights: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

private extension View {
    func measured() -> some View {
        background(GeometryReader { Color.clear.preference(key: FixedHeights.self, value: $0.size.height) })
    }
}
