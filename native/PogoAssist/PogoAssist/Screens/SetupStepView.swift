import SwiftUI
import PogoBox
import PogoReader

/// One step, one screen (design handoff, Setup §2c): "Step N of 6", a picture of the exact setting, the instruction as the title, at most two lines of text, the Siri line
/// where it is true, and a confirm button that names what is done. The same template for all six; step 4 holds three ticks. Nothing here opens a private Settings page: the
/// app can open only its own page in iOS Settings, which helps only for notifications (step 1).
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

    private var info: SetupProgress.Info { SetupProgress.info[step - 1] }
    private var deviceKind: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
    private var sizesText: String { "\(VoiceCommandFile.setSizes.count) commands (\(VoiceCommandFile.setSizes.first!) to \(VoiceCommandFile.setSizes.last!) Pokémon)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                picture
                VStack(alignment: .leading, spacing: 8) {
                    Text(info.title).font(.figtree(26, .heavy, relativeTo: .title)).tracking(-0.02 * 26).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                    Text(text).font(.figtree(16, .regular, relativeTo: .body)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 6)
                extras
                if let siri = siriLine { siri }
                more
            }
            .padding(.horizontal, Theme.Space.screen).padding(.top, 8).padding(.bottom, 12)
        }
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
            default:
                Image("setup-step\(step)").resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: shape).panelShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pictureLabel)
        .accessibilityIdentifier("setup-picture")
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
        case 5: return "Settings, Focus, Do Not Disturb: the People and Apps boxes and Options"
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
        case 3: return "In Voice Control › Commands, scroll to the bottom. Tap Import Custom Commands, then pick the file you saved in step 2."
        case 4: return "Tick each one here as you switch it off."
        case 5: return "A banner over the game blocks the reading. Turn Do Not Disturb on before each scan, and let Pogo Assist through: Settings › Focus › Do Not Disturb › Apps › add Pogo Assist."
        default: return "iOS hides notification banners while the screen is shared. In Settings › Notifications › Screen Sharing, turn on Allow Notifications."
        }
    }

    /// The Siri phrase is shown only where it helps (the Voice Control settings), as words to say: a device check found it works from the Home Screen, not from inside the game.
    private var siriLine: AnyView? {
        guard step == 3 || step == 4 else { return nil }
        return AnyView(
            HStack(spacing: 12) {
                Image(systemName: "mic.fill").font(.system(size: 16, weight: .bold)).frame(width: 34, height: 34)
                    .foregroundStyle(accent.ink).background(accent.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous)).accessibilityHidden(true)
                Text("Say \"Hey Siri, open Voice Control settings\" from the Home Screen.").font(.figtree(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
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
            return ["A Focus other than Do Not Disturb works the same way: allow Pogo Assist through it.",
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

    // MARK: confirm

    private var confirmTitle: String {
        switch step {
        case 4: return "Done · \(setup.switches.count) of 3 ticked"
        case 5: return "It's set up"
        default: return setup.isVerified(step) ? "Continue" : "I've done it"
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
