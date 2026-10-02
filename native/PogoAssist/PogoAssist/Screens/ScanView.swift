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
                     ? "Scans the whole storage. Pokémon in your box that the scan does not see are offered as gone, and you choose whether to save that."
                     : "Scans part of the storage, such as your newest Pokémon. Nothing is removed from the box.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Before you start") {
                Label("The Voice Control command is installed", systemImage: "1.circle")
                Label("Voice Control's Show Confirmation and Show Hints are off", systemImage: "2.circle")
                Label("Pokémon GO is open on the first Pokémon with the appraisal showing", systemImage: "3.circle")
                Label("Say the command, or swipe through the Pokémon by hand", systemImage: "4.circle")
            }
            Section {
                HStack {
                    Text("Pokémon in storage")
                    Spacer()
                    TextField("Optional", text: $model.storageCountText).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 120).focused($countFocused)
                }
            } footer: { Text("Saved with the scan, and used to size the Voice Control command below.") }
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
            } footer: { Text("Choose Pogo Assist in the list, start the broadcast, then switch to Pokémon GO within the three-second countdown. Stop it from the red bar when the last Pokémon has been read.") }
        }
        .navigationTitle("Scan Pokémon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { countFocused = false } } }
    }

    // MARK: - the Voice Control command

    /// The pace and count the last command made were built for differ from what is chosen now.
    private var choiceChanged: Bool {
        guard let last = model.voiceLast else { return false }
        return last.pace != model.pace || (model.storageCount != nil && last.storageCount != model.storageCount)
    }

    private var commandSection: some View {
        Section {
            stepTitle("1. Choose how to page")
            ForEach(VoiceCommandFile.Pace.allCases) { p in paceRow(p) }
            if let c = model.storageCount {
                let size = VoiceCommandFile.sizing(storageCount: c, pace: model.pace)
                Text("About \(minutes(size.estimatedSeconds)) for \(c.formatted()) Pokémon. The file makes \(size.covers.formatted()) page steps (\(size.repeats) x \(size.batch)).").font(.footnote)
            }
            if model.pace.isTap {
                Text("Taps stay at the right edge, away from Power up and Evolve. Taps past the end close the appraisal and then do nothing (tested on the 440 x 956 iPhone only).").font(.footnote).foregroundStyle(.secondary)
            }
            if !model.tapAvailable {
                Text("Tap paging is only available on screens it has been checked on.").font(.footnote).foregroundStyle(.secondary)
            }
            if let last = model.voiceLast {
                Text("Last made: \(last.pace.spokenTitle), for \(last.storageCount.formatted()) Pokémon (\(Fmt.day(last.date))).").font(.footnote.weight(.medium))
                if choiceChanged {
                    Label("Your choice has changed. Get the command again and import it, or Voice Control will play the old one.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                } else if let c = model.storageCount, VoiceCommandFile.steps(storageCount: c) > last.covers {
                    Label("Your count is higher than that command covers. Get the command again.", systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                }
            } else {
                Text("No command made yet.").font(.footnote).foregroundStyle(.secondary)
            }
            stepTitle("2. Get the command for this choice")
            Button { Task { await model.getCommand() } } label: { Label("Get the \(model.pace.spokenTitle) command", systemImage: "square.and.arrow.up") }
                .disabled(model.storageCount == nil)
            Text("Each speed is its own file. Importing a new one replaces the old command.").font(.footnote).foregroundStyle(.secondary)
            stepTitle("3. Import it in Voice Control")
            VStack(alignment: .leading, spacing: 4) {
                Text("a. Choose Save to Files or AirDrop in the sheet that opens.").font(.footnote)
                Text("b. Settings > Accessibility > Voice Control > Commands > Import Custom Commands, then pick the file.").font(.footnote)
                Text("c. Do this again whenever you choose a different speed or count.").font(.footnote)
            }
            .foregroundStyle(.secondary)
            stepTitle("4. Say \"Pogo scan\"")
            Text("With the first Pokémon's appraisal open.").font(.footnote).foregroundStyle(.secondary)
        } header: { Text("Voice Control command") } footer: { Text("Optional. Without it, swipe through the Pokémon by hand.") }
    }

    private func stepTitle(_ text: String) -> some View { Text(text).font(.subheadline.weight(.semibold)) }

    private func minutes(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        return m < 1 ? "under a minute" : m == 1 ? "1 minute" : "\(m) minutes"
    }

    private func paceRow(_ p: VoiceCommandFile.Pace) -> some View {
        let disabled = p.isTap && !model.tapAvailable
        return Button { model.pace = p } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title).foregroundStyle(disabled ? Color.secondary : Color.primary)
                    if !p.provenOnFullBox { Text("not yet proven on a full box").font(.footnote).foregroundStyle(Color.secondary) }
                }
                Spacer()
                if model.pace == p && !disabled { Image(systemName: "checkmark") }
            }
        }
        .disabled(disabled)
    }

    @ViewBuilder private var liveStatus: some View {
        let s = model.broadcast
        VStack(alignment: .leading, spacing: 6) {
            HStack { ProgressView(); Text("Scan in progress").font(.headline) }
            Text("\(s?.framesRead ?? 0) frames read, \(s?.rows.count ?? 0) Pokémon so far").monospacedDigit()
            Text("Stop the broadcast from the red bar when the last Pokémon has been read, then come back here.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
