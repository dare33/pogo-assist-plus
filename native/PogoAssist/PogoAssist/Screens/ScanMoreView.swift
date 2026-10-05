import SwiftUI
import PogoBox
import PogoReader

/// "More about scanning": what the old "Scan setup" page held that no step of "Get ready to scan" owns. The choice between paging by voice and by hand, what to say (the
/// size list of Add and update), how a command is stopped, what a pause is, how the broadcast is started and ended, and the app group warning. Reached from the checklist.
struct ScanMoreView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accent) private var accent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("More about scanning").paText(.screenTitle).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader).padding(.horizontal, 6)
                if !SharedStore.containerAvailable {
                    Panel(tint: .orange) { Text("The app group is not available, so a scan cannot reach the app. Check Signing and Capabilities on both targets.").font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.red) }
                }
                if let warning = model.tapCommandWarning {
                    Panel(tint: .orange) { Label(warning, systemImage: "exclamationmark.octagon.fill").font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.red) }
                }
                paging
                before
                say
                stopping
                ending
                broadcast
            }
            .padding(.horizontal, Theme.Space.screen).padding(.top, 8).padding(.bottom, 20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
    }

    private func heading(_ text: String) -> some View { Text(text).font(.figtree(17, .heavy, relativeTo: .headline)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader) }
    private func body_(_ text: String) -> some View { Text(text).font(.secondary).foregroundStyle(Theme.muted) }

    // MARK: how will you page?

    private var paging: some View {
        Panel(spacing: 12) {
            heading("Before you start the broadcast: how will you page?")
            HStack(spacing: 0) { pagingButton("Page with the voice command", byHand: false); pagingButton("Page by hand", byHand: true) }
                .padding(4).background(Theme.off, in: Capsule())
            body_(model.pagedByHand
                  ? "You swipe from one Pokémon to the next yourself. Twins are not told apart by the paging beat, and the scan does not end by itself: stop the broadcast from the red bar when the last Pokémon has been read."
                  : (model.commandSetMade ? "The scan usually ends by itself when the list ends or the command runs out. If it does not, stop the broadcast from the red bar."
                                          : "The scan ends by itself only with the commands: get them first (Get ready to scan, step 2). Until then nothing ends the scan but you, from the red bar."))
            body_("The voice commands are optional. Without them, swipe through the Pokémon by hand.")
        }
    }

    private func pagingButton(_ title: String, byHand: Bool) -> some View {
        let on = model.pagedByHand == byHand
        return Button { model.choosePaging(byHand: byHand) } label: {
            Text(title).font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(on ? accent.onSolid : Theme.muted)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 40)
                .background(on ? accent.solid : Color.clear, in: Capsule())
                .frame(minHeight: 44).contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: before you start

    private var before: some View {
        Panel(spacing: 8) {
            heading("Before you start")
            body_("Pokémon GO is open on the first Pokémon with the appraisal showing.")
            body_("Turn on Do Not Disturb (or a Focus) before scanning: a banner over the game blocks the reading. Say the command named below, or page through the Pokémon by hand.")
        }
    }

    // MARK: say the command

    private var say: some View {
        Panel(spacing: 10) {
            heading("For each scan: say the command")
            if model.scanKind == .full { fullScanCommand } else { partScanCommands }
        }
    }

    @ViewBuilder private var fullScanCommand: some View {
        if let size = model.commandSize {
            Text(verbatim: "Say: Pogo scan \(size)").font(.figtree(20, .heavy, relativeTo: .title3)).foregroundStyle(Theme.ink)
            body_("Covers up to \(size.formatted()) Pokémon; about \(minutes(Double(model.estimatedMinutes(size: size)) * 60)).")
        } else if model.countAboveLargest {
            Text(verbatim: "Say: Pogo scan \(VoiceCommandFile.setSizes.last!)").font(.figtree(20, .heavy, relativeTo: .title3)).foregroundStyle(Theme.ink)
            Text("The largest command covers \(VoiceCommandFile.setSizes.last!.formatted()) Pokémon. Scans of a storage this large are Add and update (nothing is proposed as gone): scan the first \(VoiceCommandFile.setSizes.last!.formatted()), then the rest with a second scan.").font(.secondary).foregroundStyle(Theme.orangeInk)
        } else {
            body_("Type how many Pokémon are in your storage (Edit, on the Scan screen) to see which command to say.")
        }
    }

    @ViewBuilder private var partScanCommands: some View {
        body_("Say the size that covers the Pokémon you want to scan, counting from the one on screen. A command pages that many; if the list ends first, the scan usually ends by itself.")
        ForEach(VoiceCommandFile.setSizes, id: \.self) { size in
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "Pogo scan \(size)").font(.figtree(15, .semibold, relativeTo: .callout)).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Text("\(size.formatted()) Pokémon, about \(minutes(Double(model.estimatedMinutes(size: size)) * 60))").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: stopping, pauses, endings

    private var stopping: some View {
        Panel(tint: .orange, spacing: 8) {
            Label("To stop a command, say \"Go to sleep\". It stops when the batch that is playing ends, \(model.setKind.stopDelayText). Then say \"Wake up\". Touching the screen, the side button or locking the phone does not stop it. Stay on the Pokémon's appraisal screen in Pokémon GO until it ends: it keeps \(model.setKind == .tap ? "tapping" : "swiping") the same place whatever is on screen.",
                  systemImage: "exclamationmark.octagon.fill").font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.red)
        }
    }

    @ViewBuilder private var ending: some View {
        if !model.pagedByHand {
            Panel(spacing: 10) {
                heading("How a scan ends")
                if model.scanKind == .full {
                    body_("When the scan stops seeing new Pokémon it either finishes (you reached your storage count) or PAUSES and sends a notification: reopen the Pokémon's appraisal and paging carries on in the same scan, or say the command again. The notification is the only signal while it is paused, so Pogo Assist must be allowed through Do Not Disturb. If no new Pokémon is read for \(ScanNotification.pauseLimitText) it finishes by itself (reopening the same Pokémon's appraisal after it had closed starts the \(ScanNotification.pauseLimitText) over but does not carry the scan on, and a pause never lasts longer than \(Int(ScanEndDecision.pauseCapSeconds / 60)) minutes in all), and \"Finish now\" ends it at once.")
                }
                body_("The scan usually ends by itself when the list ends or the command runs out (the broadcast stops and the result appears); if the last Pokémon cannot be read it does not, and you stop the broadcast from the red bar. The command keeps going until it runs out; that does nothing to your box.")
            }
        }
    }

    private var broadcast: some View {
        Panel(spacing: 8) {
            heading("Starting the broadcast")
            body_(model.pagedByHand
                  ? "Choose Pogo Broadcast in the list, start the broadcast, then switch to Pokémon GO within the three-second countdown. Stop it from the red bar when the last Pokémon has been read."
                  : "Choose Pogo Broadcast in the list, start the broadcast, then switch to Pokémon GO within the three-second countdown and say the command. The scan usually ends by itself when the list ends or the command runs out. If it does not, stop the broadcast from the red bar.")
        }
    }

    private func minutes(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        return m < 1 ? "under a minute" : m == 1 ? "1 minute" : "\(m) minutes"
    }
}
