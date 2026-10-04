import SwiftUI
import PogoBox
import PogoReader

/// The Scan screen (design handoff, "Magic scan", Scan §3m): the reminder, the 240 pt mark button and a bottom panel with the options summary
/// and the two steps. Edit swaps the steps for the options. If the app is opened while a broadcast runs, the same button is the progress ring.
/// Everything the old screen held that has no place here is in `ScanSetupView` ("Scan setup").
struct ScanView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.helpLevel) private var help
    @Environment(\.accent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var badgeSize: CGFloat = 36
    @AppStorage(ScanSteps.key) private var hiddenRaw = ""
    /// Editing the options replaces the steps. Decided once on appearing: the first scan for an account (nothing to confirm yet) opens in Edit.
    @State private var editing = false
    @State private var decidedEditing = false
    @State private var walkSteps: [Int]?
    @StateObject private var markTrigger = BroadcastTrigger()
    @StateObject private var walkTrigger = BroadcastTrigger()

    private var words: ScanWords { ScanWords.current(model) }
    private var visibleSteps: [Int] { ScanSteps.visible(raw: hiddenRaw, help: help) }
    /// The button can start a scan: not while editing, and a Full scan needs its count first.
    private var canStart: Bool { !editing && !model.fullScanNeedsCount }

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
                    } else {
                        reminder
                        // With the options open the panel is long: no spare space around the button then.
                        if !editing { Spacer(minLength: 0) }
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
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Scan Pokémon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { AccountPill() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { hiddenRaw = ""; if !model.live { walkSteps = Array(0..<ScanSteps.count) } } label: {
                    Image(systemName: "questionmark").font(.figtree(16, .bold)).foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Show the steps again")
            }
        }
        .fullScreenCover(isPresented: Binding(get: { walkSteps != nil }, set: { if !$0 { walkSteps = nil } })) {
            if let steps = walkSteps {
                ScanWalkthrough(steps: steps, words: words, hiddenRaw: $hiddenRaw, trigger: walkTrigger) { walkSteps = nil }
                    .environment(\.accent, accent)
            }
        }
        // The broadcast has started: the steps have done their job.
        .onChange(of: model.live) { _, live in if live { walkSteps = nil } }
        .onChange(of: model.account) { _, _ in editing = model.fullScanNeedsCount }
        // The permission is asked when the paging choice changes or the commands are made; a phone that already has both would never be asked, so ask once here too
        // (not while a share sheet is up).
        .onAppear {
            if !decidedEditing { decidedEditing = true; editing = model.fullScanNeedsCount }
            if !model.pagedByHand, model.commandSetMade, model.shareURLs.isEmpty { model.askForNotificationsOnce() }
            #if DEBUG
            ScanDebug.installIfAsked()
            #endif
        }
    }

    // MARK: - ready

    private var reminder: some View {
        HStack(spacing: 12) {
            Image(systemName: "gamecontroller.fill").font(.figtree(17, .bold)).frame(width: 36, height: 36)
                .foregroundStyle(Theme.orangeInk).background(Theme.orangeTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous)).accessibilityHidden(true)
            Text("In Pokémon GO, open your first Pokémon's **appraisal** before you start.")
                .font(.figtree(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous)).panelShadow()
    }

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
        } else if !visibleSteps.isEmpty {
            Button { walkSteps = visibleSteps } label: { face }.buttonStyle(.plain).accessibilityLabel("Start scan")
        } else {
            // Every step hidden: the button itself starts the broadcast (the system picker, laid invisibly over it).
            face.broadcastPicker(trigger: markTrigger, shape: Circle())
        }
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
                    // The design says "We'll take you back to the game"; this build does not open the game.
                    Text("Now switch to Pokémon GO.").font(.figtree(13, .regular, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                }
            }
            .accessibilityElement(children: .combine)
            stepTwo
            notes
            NavigationLink { ScanSetupView() } label: {
                HStack(spacing: 6) {
                    Text("Scan setup").font(.figtree(14, .bold, relativeTo: .subheadline))
                    Image(systemName: "chevron.right").font(.figtree(12, .bold)).accessibilityHidden(true)
                }
                .foregroundStyle(accent.ink).frame(minHeight: 44).contentShape(Rectangle())
            }
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
                Text("\"Pogo scan\" and the size that covers the Pokémon you want to scan, counting from the one on screen. A command pages that many; if the list ends first, the scan usually ends by itself. The sizes are in Scan setup.")
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
            Text("The scan ends by itself only with the commands: get them first (Scan setup). Until then nothing ends the scan but you, from the red bar.").font(.secondary).foregroundStyle(Theme.muted)
        }
        if let warning = model.tapCommandWarning {
            Label(warning, systemImage: "exclamationmark.octagon.fill").font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.red)
        }
        if model.endedWithoutFinish {
            Text("The last broadcast stopped without finishing. Its readings will be offered for review.").font(.secondary).foregroundStyle(Theme.muted)
        }
    }

    // MARK: - scanning

    @ViewBuilder private var liveStatus: some View {
        let s = model.broadcast
        VStack(spacing: 10) {
            Text("Scan in progress").font(.figtree(20, .heavy, relativeTo: .title3)).foregroundStyle(Theme.ink)
            Text("\(s?.framesRead ?? 0) frames read, \(s?.readCount ?? 0) Pokémon so far" + (expectedCount.map { " of about \($0.formatted())" } ?? ""))
                .font(.secondary).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            if let s, s.paused {
                Panel(tint: .orange) {
                    Label(ScanNotification.paused(scan: s.scanId, event: s.eventSeq, read: s.readCount, storageCount: s.storageCount, eggCount: s.eggCount, lastName: s.pausedCard, lastCP: nil, sizes: VoiceCommandFile.setSizes, limitSeconds: s.pauseLimitSeconds).body, systemImage: "pause.circle.fill")
                        .font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.orangeInk)
                    PillButton("Finish now", style: .plain, isDestructive: true) { model.finishPausedScanNow() }
                }
            }
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
