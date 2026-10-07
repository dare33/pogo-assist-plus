import SwiftUI
import PogoBox
import PogoReader

/// One step, one screen (design handoff, Setup §2c): "Step N of 6", the instruction as the title, then a short numbered list (steps 3 to 5) or one line of text, the picture of the exact setting (behind
/// "See where it is" on steps 3 and 4), the Siri line where it is true, and a confirm button that names what is done. The same template for all six; step 4 holds three ticks. Steps 1 and 3 to 6 also have an
/// "Open Settings" button that tries a list of Settings links in order, and always says in words which page to go to, because the app cannot tell where Settings really opened.
struct SetupStepView: View {
    let step: Int
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase

    var body: some View {
        SetupStepBody(step: step, setup: model.setup, finish: { dismiss() }, openSettings: {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        })
        .navigationTitle("Step \(step) of \(SetupProgress.count)")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .onAppear { model.setup.refresh() }
        .onChange(of: phase) { _, p in if p == .active { model.setup.refresh() } }
    }
}

private struct SetupStepBody: View {
    let step: Int
    @ObservedObject var setup: SetupProgress
    var finish: () -> Void
    var openSettings: () -> Void
    @EnvironmentObject var model: AppModel
    @Environment(\.accent) private var accent
    @State private var moreOpen = false
    @State private var pictureOpen = false

    private var info: SetupProgress.Info { SetupProgress.info[step - 1] }
    private var deviceKind: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
    private var sizesText: String { "\(VoiceCommandFile.setSizes.count) commands (\(VoiceCommandFile.setSizes.first!) to \(VoiceCommandFile.setSizes.last!) Pokémon)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // The instruction comes first on every step. Steps 3 and 4 keep their picture behind "See where it is"; step 5's picture carries the answer, so it stays on the page.
                VStack(alignment: .leading, spacing: 8) {
                    Text(info.title).font(.figtree(26, .heavy, relativeTo: .title)).tracking(-0.02 * 26).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                    if keySteps == nil { sentence }
                }
                .padding(.horizontal, 6)
                if step != 3 && step != 4 { picture }
                if let keySteps { numbered(keySteps) }
                if step == 4 || step == 5 { sentence.padding(.horizontal, 6) }
                if step == 3 || step == 4 { seeWhere }
                extras
                more
                if let links = Self.settingsLinks[step], !(step == 1 && setup.notifications == .denied) { settingsRow(links) }
                if let siri = siriLine { siri }
            }
            .padding(.horizontal, Theme.Space.screen).padding(.top, 8).padding(.bottom, 12)
        }
        .sheet(isPresented: $pictureOpen) { pictureSheet }
        .background(Theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PillButton(confirmTitle, style: .filled, height: 56, action: confirm)
                .disabled(!canConfirm)
                .accessibilityIdentifier("setup-confirm")
                .padding(.horizontal, Theme.Space.screen).padding(.top, 8).padding(.bottom, 10)
                .background(Theme.bg)
        }
    }

    // MARK: the picture

    @ViewBuilder private var picture: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
        Group {
            switch step {
            case 1: symbol("bell.badge")
            case 2: symbol("square.and.arrow.up")
            default: settingsImage.padding(14)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: shape).panelShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pictureLabel)
        .accessibilityIdentifier("setup-picture")
    }

    /// The Settings picture. On step 5 a ring in the accent colour sits on the Apps box; its position is measured in the 700 x 286 asset and kept as fractions of the image,
    /// so it stays on Apps at any size.
    private var settingsImage: some View {
        Image("setup-step\(step)").resizable().scaledToFit()
            .overlay {
                if step == 5 {
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 0.1 * g.size.height, style: .continuous).stroke(accent.solid, lineWidth: 4)
                            .frame(width: 0.47 * g.size.width, height: 0.52 * g.size.height)
                            .position(x: 0.75 * g.size.width, y: 0.34 * g.size.height)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var sentence: some View { Text(text).font(.figtree(16, .regular, relativeTo: .body)).foregroundStyle(Theme.muted) }

    /// Steps 3 and 4: the picture opens large in a sheet, so the page leads with what to do.
    private var seeWhere: some View {
        Button { pictureOpen = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "photo").font(.system(size: 16, weight: .bold)).frame(width: 34, height: 34)
                    .foregroundStyle(accent.ink).background(accent.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous)).accessibilityHidden(true)
                Text("See where it is").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(accent.ink).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.figtree(14, .bold)).foregroundStyle(Theme.faint).accessibilityHidden(true)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 56)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous)).panelShadow()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("setup-see")
    }

    private var pictureSheet: some View {
        NavigationStack {
            ScrollView {
                settingsImage.padding(Theme.Space.screen)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(pictureLabel)
                    .accessibilityIdentifier("setup-picture")
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Where it is").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { pictureOpen = false }.accessibilityIdentifier("setup-picture-done") } }
        }
        .presentationDetents([.large])
    }

    /// The key steps, one line each, with number wells like the Scan screen's steps.
    private func numbered(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("\(i + 1)").font(.figtree(14, .heavy, relativeTo: .subheadline)).foregroundStyle(accent.ink)
                        .frame(width: 28, height: 28).background(accent.tint, in: Circle()).accessibilityHidden(true)
                    Text(line).font(.figtree(16, .semibold, relativeTo: .body)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 6)
        .accessibilityIdentifier("setup-steps")
    }

    /// Steps 3 to 5 say what to do as a short list; the other steps keep their one line of text.
    private var keySteps: [String]? {
        switch step {
        case 3: return ["Open Settings › Accessibility › Voice Control › Commands", "Scroll to the bottom, tap Import Custom Commands", "Pick the file you saved in step 2"]
        case 4: return ["Open Settings › Accessibility › Voice Control", "Switch off Show Confirmation and Show Hints", "Scroll down, switch off Attention Aware"]
        case 5: return ["Open Settings › Focus › Do Not Disturb", "Tap Apps, then add Pogo Assist", "Turn Do Not Disturb on before each scan"]
        default: return nil
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 64, weight: .light)).foregroundStyle(accent.solid)
            .frame(maxWidth: .infinity, minHeight: 150)
    }

    private var pictureLabel: String {
        switch step {
        case 1: return "A bell with a badge: the notification permission"
        case 2: return "The share icon: the commands file is shared to Files"
        case 3: return "Settings, Voice Control, Commands, at the bottom: Import Custom Commands, Export Custom Commands and Delete All Custom Commands"
        case 4: return "Settings, Voice Control: Show Confirmation, Play Sound and Show Hints, then Attention Aware, all switched off"
        case 5: return "Settings, Focus, Do Not Disturb: the People and Apps boxes and Options, with a ring round Apps"
        default: return "Settings, Notifications: Screen Sharing, Notifications On, and below it Screen Sharing's Allow Notifications switched on"
        }
    }

    // MARK: words

    /// At most two lines of text: what to do, from what the app really knows.
    private var text: String {
        switch step {
        case 1: return "Pogo Assist sends a notification, with a sound, when a scan pauses or ends by itself. It stays on your phone: nothing is sent."
        case 2:
            return model.setKind == .tap
                ? "One file holds all the commands. Choose Save to Files on THIS \(deviceKind): its taps are placed for this screen only."
                : "One file holds all the commands. Choose Save to Files on this \(deviceKind)."
        case 3: return ""
        case 4: return "Tick each one here as you switch it off."
        case 5: return "Alarms and timers still ring through Do Not Disturb, so check none is due during a scan."
        default: return "iOS hides notification banners while the screen is shared. In Settings › Notifications › Screen Sharing, turn on Allow Notifications."
        }
    }

    /// The Siri phrase is shown only where it helps (the Voice Control settings), as words to say.
    private var siriLine: AnyView? {
        guard step == 3 || step == 4 else { return nil }
        return AnyView(
            HStack(spacing: 12) {
                Image(systemName: "mic.fill").font(.system(size: 16, weight: .bold)).frame(width: 34, height: 34)
                    .foregroundStyle(accent.ink).background(accent.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous)).accessibilityHidden(true)
                Text("Say \"Hey Siri, open Voice Control settings\".").font(.figtree(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 56)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous)).panelShadow()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("setup-siri"))
    }

    // MARK: what is special to a step

    @ViewBuilder private var extras: some View {
        switch step {
        case 1: notificationAction
        case 2: commandAction
        case 4: switchesPanel
        default: EmptyView()
        }
    }

    @ViewBuilder private var notificationAction: some View {
        switch setup.notifications {
        case .authorised:
            Label("Notifications are on for Pogo Assist.", systemImage: "checkmark.circle.fill").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.greenInk)
        case .denied:
            Text("Notifications are off for Pogo Assist. Turn them on in Settings, then come back here.").font(.secondary).foregroundStyle(Theme.orangeInk)
            PillButton("Open Settings", systemImage: "gearshape", style: .tint, action: openSettings)
        case .notAsked, .unknown:
            PillButton("Allow notifications", systemImage: "bell", style: .tint) { setup.askForNotifications() }
        }
    }

    @ViewBuilder private var commandAction: some View {
        if let warning = model.tapCommandWarning {
            Label(warning, systemImage: "exclamationmark.octagon.fill").font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.red)
        }
        PillButton(model.setRecord == nil ? "Get the commands" : "Get the commands again", systemImage: "square.and.arrow.up", style: model.setRecord == nil ? .tint : .plain) { Task { await model.getCommandSet() } }
        if let warning = model.commandWarning {
            Label(warning, systemImage: "exclamationmark.triangle.fill").font(.secondary).foregroundStyle(Theme.orangeInk)
        }
    }

    private static let switchNames: [(name: String, sub: String)] = [
        ("Show Confirmation", "Switch it to Off · Voice Control"),
        ("Show Hints", "Switch it to Off · Voice Control"),
        ("Attention Aware", "Switch it to Off · Voice Control"),
    ]

    /// One tick per switch.
    private var switchesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Panel(padding: 0, spacing: 0) {
                ForEach(Array(Self.switchNames.enumerated()), id: \.offset) { i, item in
                    let on = setup.switches.contains(i)
                    Button { setup.toggleSwitch(i) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.figtree(24, .semibold)).foregroundStyle(on ? Theme.green : Theme.faint).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).paText(.rowTitle).foregroundStyle(Theme.ink)
                                Text(item.sub).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 60).contentShape(Rectangle())
                        .overlay(alignment: .bottom) { if i < 2 { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 52) } }
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(item.name)
                    .accessibilityValue(on ? "Ticked" : "Not ticked")
                    .accessibilityHint(item.sub)
                    .accessibilityAddTraits(.isToggle)
                    .accessibilityIdentifier("setup-switch-\(i)")
                }
            }
            Text("The commands are made for this phone's language (\(AppModel.voiceLocale)). Voice Control's own language must be the same.")
                .font(.secondary).foregroundStyle(Theme.muted).padding(.horizontal, 6)
        }
    }

    // MARK: more about this step

    /// What the old "Scan setup" page said about this step and the two lines of text have no room for.
    private var moreParagraphs: [String] {
        switch step {
        case 1:
            return ["Pogo Assist asks once, so you know without opening the app when a scan ends by itself. Without it the scan still ends and the result waits here.",
                    "A paused scan is only signalled by its notification, so Pogo Assist must also be allowed through Do Not Disturb (step 5)."]
        case 2:
            return [model.setKind == .tap
                    ? "One file holds all \(sizesText). They page by tapping the next-Pokémon arrow, \(model.pace.secondsText). Taps stay at the right edge, away from Power up and Evolve. Do not send the file to another device."
                    : "Tap paging has not been checked on this screen size, so the commands swipe instead (\(model.pace.secondsText)). One file holds all \(sizesText).",
                    "You make the file once per phone. Importing it again replaces its own commands and nothing else."]
        case 3:
            return ["First delete any earlier single commands in Settings › Accessibility › Voice Control › Commands: \"Pogo scan\", \"Pogo fast scan\", \"Pogo swipe\" and \"Pogo slow swipe\". They run at a different pace, the scan ending by itself assumes this set's pace, and \"Pogo scan\" is the start of every phrase here.",
                    "The commands are made for this phone's language (\(AppModel.voiceLocale)). Voice Control's own language must be the same."]
        case 4:
            return ["With Attention Aware on, Voice Control goes to sleep when you look away, which stops a command at the end of its batch.",
                    "Show Confirmation and Show Hints are in Voice Control's Command Feedback section; Attention Aware is lower on the same page."]
        case 5:
            return ["A banner over the game blocks the reading.",
                    "A Focus other than Do Not Disturb works the same way: allow Pogo Assist through it.",
                    "Allowing Pogo Assist through means you hear when a scan pauses or stops."]
        default:
            return ["Without it, a pause or a stop only goes quietly to Notification Centre."]
        }
    }

    private var more: some View {
        DisclosureGroup(isExpanded: $moreOpen) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(moreParagraphs, id: \.self) { Text($0).font(.secondary).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .padding(.top, 8)
        } label: {
            Text("More about this step").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(accent.ink).frame(minHeight: 44, alignment: .leading)
        }
        .tint(accent.ink)
        .padding(.horizontal, 6)
        .accessibilityIdentifier("setup-more")
    }

    // MARK: open the Settings page

    /// The Settings links each step tries, in order. The `prefs:` and `App-Prefs:` schemes and `settings-navigation://` are private: Greg chose to use them on 6 Oct 2026 and accepts that an iOS update may change or
    /// block them. iOS 18 broke most `App-Prefs:` forms and every `&path=` sub-path, and iOS 26 sends some unsupported ones to the Apps list, so each step lists several and the words under the button say where to go
    /// if none lands. Step 1 is this app's own notification page, which the documented API reaches. `App-Prefs:root=NOTIFICATIONS_ID` is left out of step 6: it is known to land on the Apps list on iOS 26.
    /// Step 2 has no Settings page. The last resort is always `openSettingsURLString`, this app's own page.
    static let settingsLinks: [Int: [String]] = [
        1: [UIApplication.openNotificationSettingsURLString],
        3: voiceControlLinks,
        4: voiceControlLinks,
        5: ["prefs:root=DO_NOT_DISTURB", "App-Prefs:root=DO_NOT_DISTURB", "settings-navigation://com.apple.Settings.Focus"],
        6: ["settings-navigation://com.apple.Settings.Notifications", "prefs:root=NOTIFICATIONS_ID", "App-Prefs:NOTIFICATIONS_ID"],
    ]
    private static let voiceControlLinks = ["prefs:root=ACCESSIBILITY&path=CommandAndControlTitle", "App-Prefs:root=ACCESSIBILITY&path=CommandAndControlTitle",
                                            "settings-navigation://com.apple.Settings.Accessibility", "App-Prefs:root=ACCESSIBILITY"]

    /// A private link can report that it opened and still land on the wrong page (step 6 did, on the Apps list), so this line is shown whatever happened.
    private var settingsWords: String {
        switch step {
        case 1: return "If Settings opens on another page, go to Apps › Pogo Assist+ › Notifications."
        case 3: return "If Settings opens on another page, go to Accessibility › Voice Control."
        case 4: return "If Settings opens on another page, go to Accessibility › Voice Control; the three switches are on that page."
        case 5: return "If Settings opens on another page, go to Focus."
        default: return "If Settings opens on another page, go to Notifications › Screen Sharing."
        }
    }

    /// No `canOpenURL` for the private schemes (it would need declared schemes): just try each, and move on when iOS says no.
    private func openSettingsPage(_ links: [String]) {
        var rest = links.compactMap { URL(string: $0) }[...]
        func next() {
            guard let url = rest.popFirst() else {
                if let own = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(own) }
                return
            }
            UIApplication.shared.open(url, options: [:]) { opened in if !opened { next() } }
        }
        next()
    }

    private func settingsRow(_ links: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PillButton("Open Settings", systemImage: "gearshape", style: .tint) { openSettingsPage(links) }
                .accessibilityIdentifier("setup-open-settings")
            Text(settingsWords).font(.secondary).foregroundStyle(Theme.muted).padding(.horizontal, 6)
                .accessibilityIdentifier("setup-settings-fallback")
        }
    }

    // MARK: confirm

    private var confirmTitle: String {
        switch step {
        case 4: return "Done · \(setup.switches.count) of 3 ticked"
        case 5: return "It's set up"
        default: return setup.isVerified(step) ? "Continue" : "I've done it!"
        }
    }
    private var canConfirm: Bool {
        switch step {
        case 2: return setup.isVerified(2)   // the commands must have been made: the app's own record says so
        case 4: return setup.switches.count == 3
        default: return true
        }
    }
    private func confirm() { setup.confirm(step); finish() }
}
