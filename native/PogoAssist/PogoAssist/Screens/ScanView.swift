import SwiftUI
import PogoBox
import PogoReader

struct ScanView: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var countFocused: Bool

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
                     ? "Scans the whole storage. When the scan reaches the end of your list, Pokémon in your box that it did not see are listed as \"Not seen in this scan\" and kept; you choose whether to remove any. Otherwise it is Add and update."
                     : "Scans part of the storage, such as your newest Pokémon. Nothing is removed from the box.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Before you start") {
                Label("The Pogo scan commands are installed (once per phone)", systemImage: "1.circle")
                Label("Voice Control's Show Confirmation and Show Hints are off", systemImage: "2.circle")
                Label("Pokémon GO is open on the first Pokémon with the appraisal showing", systemImage: "3.circle")
                Label("Say the command named below, or page through the Pokémon by hand", systemImage: "4.circle")
            }
            if model.scanKind == .full {
                Section {
                    HStack {
                        Text("Pokémon in storage")
                        Spacer()
                        TextField("Count", text: $model.storageCountText).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 120).focused($countFocused)
                    }
                } footer: {
                    if let problem = model.storageCountProblem { Text(problem).foregroundStyle(.red) }
                    else { Text("Remembered for this account. It picks which command to say, and is saved with the scan. Without it the scan is Add and update.") }
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
                                              : "Choose Pogo Assist in the list, start the broadcast, then switch to Pokémon GO within the three-second countdown and say the command. The scan ends by itself at the end of the list.") }
        }
        .navigationTitle("Scan Pokémon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { countFocused = false } } }
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
            Label("Once started, a command cannot be stopped: not by touching the screen, the side button, locking the phone or Siri. Stay on the Pokémon's appraisal screen in Pokémon GO until it ends. It keeps \(model.setKind == .tap ? "tapping" : "swiping") the same place whatever is on screen.",
                  systemImage: "exclamationmark.octagon.fill").font(.callout.weight(.semibold)).foregroundStyle(.red)
            if !model.pagedByHand { Text("The scan ends by itself at the end of the list (the broadcast stops and the result appears). The command keeps going until it runs out; that does nothing to your box.").font(.footnote).foregroundStyle(.secondary) }
            stepTitle("Before you start the broadcast: how will you page?")
            Picker("Paging", selection: Binding(get: { model.pagedByHand }, set: { model.choosePaging(byHand: $0) })) {
                Text("Page with the voice command").tag(false)
                Text("Page by hand").tag(true)
            }
            .pickerStyle(.segmented)
            Text(model.pagedByHand
                 ? "You swipe from one Pokémon to the next yourself. Twins are not told apart by the paging beat, and the scan does not end by itself: stop the broadcast from the red bar when the last Pokémon has been read."
                 : (model.commandSetMade ? "The scan ends by itself when the end of your Pokémon is reached."
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
        Text("Say the size that covers the Pokémon you want to scan, counting from the one on screen. A command pages that many; if the list ends first, the scan ends by itself.").font(.footnote).foregroundStyle(.secondary)
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
            Text("\(s?.framesRead ?? 0) frames read, \(s?.rows.count ?? 0) Pokémon so far").monospacedDigit()
            Text(s?.commandPeriod != nil ? "The scan ends by itself at the end of the list; come back here when the broadcast stops." : "Stop the broadcast from the red bar when the last Pokémon has been read, then come back here.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
