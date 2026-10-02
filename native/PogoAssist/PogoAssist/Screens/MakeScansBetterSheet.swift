import SwiftUI
import PogoBox

/// "Make scans better": what is sent, an optional note, Send or Cancel. Presented from the scan result and from Settings > Scans.
struct MakeScansBetterSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let target: AppModel.ReportTarget
    @State private var note = ""
    @State private var shareURLs: [URL] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This sends this scan's reading log and results to the developer so the reader can be improved. It includes the Pokémon read, any nicknames on screen, your answers when you reviewed the scan, later corrections to those Pokémon, the date and time of the scan, the storage count, how the scan was paged and timed, later removals of its Pokémon, the app version, your phone model, iOS version, screen size and language, and whatever you type in the note below. The review lines can name Pokémon already in your box that came from other scans (species and values only). The report has no account-name field and no device identifier, so your account name appears only if it is a nickname on screen or you type it in the note.")
                    Text("Nothing is sent unless you tap Send.").font(.footnote).foregroundStyle(.secondary)
                }
                switch model.reportState {
                case .idle, .sending:
                    Section("What went wrong? (optional)") {
                        TextField("What went wrong? (optional)", text: $note, axis: .vertical).lineLimit(2...6)
                    }
                case .sent:
                    Section { Label("Sent. Thank you.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                case .failed(let why):
                    Section {
                        Label(why, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Button("Share the files instead") { shareURLs = model.reportShareFiles(target) }
                    }
                    Section("What went wrong? (optional)") { TextField("What went wrong? (optional)", text: $note, axis: .vertical).lineLimit(2...6) }
                }
            }
            .navigationTitle("Make scans better")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(model.reportState == .sent ? "Done" : "Cancel") { dismiss() } }
                if model.reportState != .sent {
                    ToolbarItem(placement: .confirmationAction) {
                        if model.reportState == .sending { ProgressView() } else { Button("Send") { Task { await model.sendReport(target, note: note) } } }
                    }
                }
            }
            .sheet(isPresented: Binding(get: { !shareURLs.isEmpty }, set: { if !$0 { shareURLs = [] } })) { ShareSheet(urls: shareURLs).presentationDetents([.medium, .large]) }
        }
        .interactiveDismissDisabled(model.reportState == .sending)
    }
}
