import SwiftUI
import PogoBox

/// "Make scans better": what is sent, an optional note, Send or Cancel. Presented from the scan result and from Settings > History and scans > Scans.
struct MakeScansBetterSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let target: AppModel.ReportTarget
    @State private var note = ""
    @State private var shareURLs: [URL] = []
    /// A share is being prepared or its sheet is open (a second tap would replace the copies the sheet is reading); `shareNote` says what was left out.
    @State private var shareBusy = false
    @State private var shareNote: String?

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
                        Button("Share the files instead") {
                            guard !shareBusy else { return }
                            shareBusy = true; shareNote = nil
                            Task {
                                let prepared = await model.reportShareFiles(target)
                                shareNote = prepared.message; shareURLs = prepared.urls
                                if prepared.urls.isEmpty { shareBusy = false }
                            }
                        }.disabled(shareBusy)
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
            .sheet(isPresented: Binding(get: { !shareURLs.isEmpty }, set: { if !$0 { shareURLs = []; shareBusy = false } })) { ShareSheet(urls: shareURLs).presentationDetents([.medium, .large]) }
            // Straight away when no file could be shared, after the share sheet closes when some could.
            .alert("Pogo Assist+", isPresented: Binding(get: { shareNote != nil && shareURLs.isEmpty }, set: { if !$0 { shareNote = nil } })) {
                Button("OK") { shareNote = nil }
            } message: { Text(shareNote ?? "") }
        }
        .interactiveDismissDisabled(model.reportState == .sending)
    }
}
