import SwiftUI
import PogoBox
import PogoReader

struct ScanView: View {
    @EnvironmentObject var model: AppModel

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
                    TextField("Optional", text: $model.storageCountText).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 120)
                }
            } footer: { Text("Saved with the scan. Nothing uses it yet.") }
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
