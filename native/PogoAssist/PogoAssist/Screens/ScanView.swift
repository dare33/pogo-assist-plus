import SwiftUI
import PogoBox
import PogoReader

struct ScanView: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var countFocused: Bool
    @FocusState private var eggsFocused: Bool

    var body: some View {
        List {
            if !SharedStore.containerAvailable {
                Section { Text("The app group is not available, so a scan cannot reach the app. Check Signing and Capabilities on both targets.").font(.callout.bold()).foregroundStyle(.red) }
            }
            Section {
                Picker("Scan kind", selection: $model.scanKind) {
                    Text("Full scan").tag(BoxStore.Kind.full)
                    Text("Add and update").tag(BoxStore.Kind.partial)
                }
                .pickerStyle(.segmented)
                Text(model.scanKind == .full
                     ? "Scans the whole storage. When the scan ends at the end of your list, Pokémon in your box that it did not see are listed as \"Not seen in this scan\" and kept; you choose whether to remove any. Otherwise it is Add and update."
                     : "Scans part of the storage, such as your newest Pokémon. Nothing is removed from the box.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Before you start") {
                Label("The Pogo scan commands are installed (once per phone)", systemImage: "1.circle")
                Label("Voice Control's Show Confirmation, Show Hints and Attention Aware are off (with Attention Aware on, Voice Control goes to sleep when you look away, which stops a command at the end of its batch)", systemImage: "2.circle")
                Label("Turn on Do Not Disturb (or a Focus) before scanning: a banner over the game blocks the reading. Allow Pogo Assist through it (Settings > Focus > Do Not Disturb > Apps), so you hear when a scan pauses or stops", systemImage: "3.circle")
                Label("Pokémon GO is open on the first Pokémon with the appraisal showing", systemImage: "4.circle")
                Label("Say the command named below, or page through the Pokémon by hand", systemImage: "5.circle")
            }
            if model.scanKind == .full {
                Section {
                    HStack {
                        Text("Pokémon in storage, as shown in the game")
                        Spacer()
                        TextField("Count", text: $model.storageCountText).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 120).focused($countFocused)
                    }
                    HStack {
                        Text("Eggs you have")
                        Spacer()
                        TextField("Eggs", text: $model.eggText).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 120).focused($eggsFocused)
                    }
                } footer: {
                    if let problem = model.storageCountProblem ?? model.eggProblem { Text(problem).foregroundStyle(.red) }
                    else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Type the number the game shows on its storage screen (it includes eggs). Remembered for this account. A full scan uses it to pick the command and is saved with it; without it a full scan is Add and update. It also tells the scan when it has read everything: it finishes at once when the Pokémon read reach your count less your eggs, and otherwise pauses (and tells you) when it stops seeing new Pokémon. An Add and update scan has no count and no pause: it ends by itself when it stops seeing new Pokémon.")
                            Text(model.eggCount == nil
                                 ? "No egg count typed: the scan allows for up to \(StorageCountRules.maxEggSlots) eggs. Type your eggs (0 to \(StorageCountRules.maxEggSlots)) for a tighter check."
                                 : "Expected Pokémon: the game's count less \(model.eggCount ?? 0) eggs.")
                        }
                    }
                }
            }
            commandSection
            Section {
                if model.live { liveStatus } else {
                    HStack {
                        Text("Start the broadcast")
                        Spacer()
                        BroadcastPicker().frame(width: 64, height: 64)
                    }
                    if model.endedWithoutFinish {
                        Text("The last broadcast stopped without finishing. Its readings will be offered for review.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } footer: { Text(model.pagedByHand ? "Choose Pogo Assist in the list, start the broadcast, then switch to Pokémon GO within the three-second countdown. Stop it from the red bar when the last Pokémon has been read."
                                              : "Choose Pogo Assist in the list, start the broadcast, then switch to Pokémon GO within the three-second countdown and say the command. The scan usually ends by itself when the list ends or the command runs out. If it does not, stop the broadcast from the red bar.") }
        }
        // The permission is asked when the paging choice changes or the commands are made; a phone that already has both would never be asked, so ask once here too
        // (not while a share sheet is up).
        .onAppear { if !model.pagedByHand, model.commandSetMade, model.shareURLs.isEmpty { model.askForNotificationsOnce() } }
        .navigationTitle("Scan Pokémon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { countFocused = false; eggsFocused = false } } }
    }

    // MARK: - the Voice Control command

    private var commandSection: some View {
        Section {
            if let warning = model.tapCommandWarning {
                Label(warning, systemImage: "exclamationmark.octagon.fill").font(.callout.weight(.semibold)).foregroundStyle(.red)
            }
            stepTitle("Once per phone: get the commands")
            Text(model.setKind == .tap
                 ? "One file holds all 13 commands (\(VoiceCommandFile.setSizes.first!) to \(VoiceCommandFile.setSizes.last!) Pokémon). They page by tapping the next-Pokémon arrow, \(model.pace.secondsText). Taps stay at the right edge, away from Power up and Evolve."
                 : "Tap paging has not been checked on this screen size, so the commands swipe instead (\(model.pace.secondsText)). One file holds all 13 commands (\(VoiceCommandFile.setSizes.first!) to \(VoiceCommandFile.setSizes.last!) Pokémon).")
                .font(.footnote).foregroundStyle(.secondary)
            Button { Task { await model.getCommandSet() } } label: { Label(model.setRecord == nil ? "Get the commands" : "Get the commands again", systemImage: "square.and.arrow.up") }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.setKind == .tap ? "a. Choose Save to Files on THIS \(deviceKind) and import it here. Do not send it to another device: its taps are placed for this screen only."
                                           : "a. Choose Save to Files on this \(deviceKind) and import it here.").font(.footnote)
                Text("b. Settings > Accessibility > Voice Control > Commands > Import Custom Commands, then pick the file.").font(.footnote)
                Text("c. First delete any earlier single commands in Settings > Accessibility > Voice Control > Commands: \"Pogo scan\", \"Pogo fast scan\", \"Pogo swipe\" and \"Pogo slow swipe\". They run at a different pace, the scan ending by itself assumes this set's pace, and \"Pogo scan\" is the start of every phrase here. Importing this set again replaces its own commands and nothing else.").font(.footnote)
                Text("d. The commands are made for this phone's language (\(AppModel.voiceLocale)). Voice Control's own language must be the same.").font(.footnote)
            }
            .foregroundStyle(.secondary)
            if let warning = model.commandWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
            }
            stepTitle("For each scan: say the command")
            if model.scanKind == .full { fullScanCommand } else { partScanCommands }
            Label("To stop a command, say \"Go to sleep\". It stops when the batch that is playing ends, \(model.setKind.stopDelayText). Then say \"Wake up\". Touching the screen, the side button or locking the phone does not stop it. Stay on the Pokémon's appraisal screen in Pokémon GO until it ends: it keeps \(model.setKind == .tap ? "tapping" : "swiping") the same place whatever is on screen.",
                  systemImage: "exclamationmark.octagon.fill").font(.callout.weight(.semibold)).foregroundStyle(.red)
            if !model.pagedByHand { Text("When the scan stops seeing new Pokémon it either finishes (you reached your storage count) or PAUSES and sends a notification: reopen the Pokémon's appraisal and paging carries on in the same scan, or say the command again. The notification is the only signal while it is paused, so Pogo Assist must be allowed through Do Not Disturb. If no new Pokémon is read for \(ScanNotification.pauseLimitText) it finishes by itself (reopening the same Pokémon's appraisal starts the \(ScanNotification.pauseLimitText) over but does not carry the scan on), and \"Finish now\" ends it at once.").font(.footnote).foregroundStyle(.secondary) }
            if !model.pagedByHand { Text("The scan usually ends by itself when the list ends or the command runs out (the broadcast stops and the result appears); if the last Pokémon cannot be read it does not, and you stop the broadcast from the red bar. The command keeps going until it runs out; that does nothing to your box.").font(.footnote).foregroundStyle(.secondary) }
            Text("Pogo Assist asks once to send a notification with a sound when a scan ends by itself, so you know without opening the app. It stays on your phone: nothing is sent. Without it the scan still ends and the result waits here.")
                .font(.footnote).foregroundStyle(.secondary)
            stepTitle("Before you start the broadcast: how will you page?")
            Picker("Paging", selection: Binding(get: { model.pagedByHand }, set: { model.choosePaging(byHand: $0) })) {
                Text("Page with the voice command").tag(false)
                Text("Page by hand").tag(true)
            }
            .pickerStyle(.segmented)
            Text(model.pagedByHand
                 ? "You swipe from one Pokémon to the next yourself. Twins are not told apart by the paging beat, and the scan does not end by itself: stop the broadcast from the red bar when the last Pokémon has been read."
                 : (model.commandSetMade ? "The scan usually ends by itself when the list ends or the command runs out. If it does not, stop the broadcast from the red bar."
                                         : "The scan ends by itself only with the commands: get them first (above). Until then nothing ends the scan but you, from the red bar."))
                .font(.footnote).foregroundStyle(.secondary)
        } header: { Text("Voice Control commands") } footer: { Text("Optional. Without them, swipe through the Pokémon by hand.") }
    }

    @ViewBuilder private var fullScanCommand: some View {
        if let size = model.commandSize {
            Text(verbatim: "Say: Pogo scan \(size)").font(.title3.weight(.semibold))
            Text("Covers up to \(size.formatted()) Pokémon; about \(minutes(Double(model.estimatedMinutes(size: size)) * 60)).").font(.footnote)
        } else if model.countAboveLargest {
            Text(verbatim: "Say: Pogo scan \(VoiceCommandFile.setSizes.last!)").font(.title3.weight(.semibold))
            Text("The largest command covers \(VoiceCommandFile.setSizes.last!.formatted()) Pokémon. Scans of a storage this large are Add and update (nothing is proposed as gone): scan the first \(VoiceCommandFile.setSizes.last!.formatted()), then the rest with a second scan.").font(.footnote).foregroundStyle(.orange)
        } else {
            Text("Type how many Pokémon are in your storage above to see which command to say.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var partScanCommands: some View {
        Text("Say the size that covers the Pokémon you want to scan, counting from the one on screen. A command pages that many; if the list ends first, the scan usually ends by itself.").font(.footnote).foregroundStyle(.secondary)
        ForEach(VoiceCommandFile.setSizes, id: \.self) { size in
            HStack {
                Text(verbatim: "Pogo scan \(size)").font(.callout.weight(.medium))
                Spacer()
                Text("\(size.formatted()) Pokémon, about \(minutes(Double(model.estimatedMinutes(size: size)) * 60))").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var deviceKind: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }

    private func stepTitle(_ text: String) -> some View { Text(text).font(.subheadline.weight(.semibold)) }

    private func minutes(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        return m < 1 ? "under a minute" : m == 1 ? "1 minute" : "\(m) minutes"
    }

    @ViewBuilder private var liveStatus: some View {
        let s = model.broadcast
        VStack(alignment: .leading, spacing: 6) {
            HStack { ProgressView(); Text("Scan in progress").font(.headline) }
            Text("\(s?.framesRead ?? 0) frames read, \(s?.rows.count ?? 0) Pokémon so far" + (s?.storageCount.map { " of about \((StorageCountRules.expected(count: $0, eggs: s?.eggCount) ?? $0).formatted())" } ?? "")).monospacedDigit()
            if let s, s.paused {
                Label(ScanNotification.paused(scan: s.scanId, event: s.eventSeq, read: s.readCount, storageCount: s.storageCount, eggCount: s.eggCount, lastName: s.pausedCard, lastCP: nil, sizes: VoiceCommandFile.setSizes).body, systemImage: "pause.circle.fill").font(.callout.weight(.semibold)).foregroundStyle(.orange)
                Button("Finish now", role: .destructive) { model.finishPausedScanNow() }
            }
            Text(s?.commandPeriod != nil ? "The scan usually ends by itself when the list ends or the command runs out; if it does not, stop the broadcast from the red bar. Come back here when the broadcast stops." : "Stop the broadcast from the red bar when the last Pokémon has been read, then come back here.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
