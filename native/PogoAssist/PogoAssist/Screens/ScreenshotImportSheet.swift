import SwiftUI
import PhotosUI
import PogoBox
import PogoImport

/// "Import screenshots": choose screenshots from Photos (the system picker, no access to the library), watch them being read, see what each gave, and go on to the usual review.
/// The same sheet shows what the share extension queued. Plain Form styling, like Settings.
struct ScreenshotImportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [PhotosPickerItem] = []
    @State private var discarding: String?

    private var imports: ImportModel { model.screenshots }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose screenshots of a Pokémon's appraisal screen in Pokémon GO. The IVs are read from the three appraisal bars, so each screenshot must show them, finished filling. Use whole, uncropped screenshots, not photos of another screen.")
                    Text("Pokémon in the screenshots are added to the box or updated. Nothing else in the box changes, and nothing is saved until you have looked at the result. The pictures stay on this phone.")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                Section {
                    PhotosPicker(selection: $picked, maxSelectionCount: ImportQueue.maxImagesPerBatch, matching: .images, photoLibrary: .shared()) {
                        Label("Choose screenshots", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(!imports.available || imports.staging != nil || model.accounts.isEmpty)
                    .accessibilityIdentifier("import-choose")
                    if let s = imports.staging {
                        HStack { ProgressView(); Text("Copying \(min(s.done + 1, s.total)) of \(s.total)…").padding(.leading, 8) }
                        Button("Cancel", role: .cancel) { imports.cancel() }
                    }
                } footer: {
                    Text(imports.available ? "You can also share screenshots from Photos to Pogo Assist+. They wait here until you open the app." : "The shared storage the app group needs is not available, so screenshots cannot be imported on this build.")
                }
                if let notice = imports.notice {
                    Section { Text(notice).font(.footnote).accessibilityIdentifier("import-notice") }
                }
                ForEach(imports.batches) { batch in BatchSection(batch: batch, discarding: $discarding) }
                if !imports.damaged.isEmpty {
                    Section {
                        Text("\(imports.damaged.count) batch\(imports.damaged.count == 1 ? "" : "es") of screenshots on this phone could not be opened. They have not been deleted; an update of the app may open them.")
                    }.font(.footnote)
                }
            }
            .navigationTitle("Import screenshots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                imports.stage(items)
                picked = []
            }
            .onAppear { imports.refresh(); imports.shown() }
            .confirmationDialog("Discard these screenshots?", isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } }), titleVisibility: .visible) {
                Button("Discard screenshots", role: .destructive) { if let id = discarding { imports.discard(batch: id) }; discarding = nil }
            } message: { Text("Nothing will be added to the box. The pictures in Photos are not touched.") }
        }
    }
}

private struct BatchSection: View {
    @EnvironmentObject var model: AppModel
    let batch: ImportManifest
    @Binding var discarding: String?

    private var imports: ImportModel { model.screenshots }
    private var owner: ScreenshotImporter.Owner { imports.owners[batch.batchId] ?? .unknown }
    private var working: Bool { imports.reading?.batch == batch.batchId }

    var body: some View {
        Section {
            if batch.pendingSave != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Finishing the last save…", systemImage: "hourglass").foregroundStyle(.secondary).accessibilityIdentifier("import-finishing")
                    Text("The Pokémon from the last save are already in your box. If this stays, you can discard these screenshots.").font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                accountRow
            }
            if working, let r = imports.reading {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(r.done), total: Double(max(r.total, 1)))
                    Text("Reading \(min(r.done + 1, r.total)) of \(r.total)").font(.footnote).foregroundStyle(.secondary)
                }
                Button("Stop reading", role: .cancel) { imports.cancel() }
            } else if !batch.isRead {
                HStack {
                    Text("\(batch.pending.count) waiting to be read").foregroundStyle(.secondary)
                    Spacer()
                    Button("Read now") { imports.startReading() }
                }
            }
            ForEach(Array(batch.items.enumerated()), id: \.element.id) { n, item in ItemRow(batch: batch, item: item, number: n + 1) }
            actions
        } header: {
            Text(batch.origin == .shareExtension ? "Shared from Photos" : "Chosen screenshots")
        } footer: {
            Text(summary)
        }
    }

    // MARK: account

    @ViewBuilder private var accountRow: some View {
        HStack {
            switch owner {
            case .account(let name):
                Label { Text("Will be added to the box of **\(name)**") } icon: { Image(systemName: "person.crop.circle") }
            case .unassigned:
                Label("Choose whose box these are for", systemImage: "person.crop.circle.badge.questionmark").foregroundStyle(.orange)
            case .gone(let name):
                Label("The account \(name) is no longer on this phone", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            case .ambiguous(let old, let now):
                Label("These were for \(old), which is now called \(now); another account is called \(old) now. Choose which box.", systemImage: "person.crop.circle.badge.questionmark").foregroundStyle(.orange)
            case .unconfirmed(_, let why):
                Label(why, systemImage: "person.crop.circle.badge.questionmark").foregroundStyle(.orange)
            case .unknown:
                Label("The accounts could not be listed", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Spacer()
            if model.accounts.count > 1 || { if case .account = owner { return false } else { return true } }() {
                Menu {
                    ForEach(model.accounts, id: \.self) { name in
                        Button { imports.assign(batch: batch.batchId, to: name) } label: {
                            if owner == .account(name) { Label(name, systemImage: "checkmark") } else { Text(name) }
                        }
                    }
                } label: { Text("Change") }
                .accessibilityIdentifier("import-account-menu")
            }
        }
    }

    // MARK: summary and actions

    private var summary: String {
        guard batch.isRead else { return "\(batch.items.count) screenshots." }
        let added = batch.included.count
        let copies = batch.duplicates.count
        let held = batch.heldBack.count
        let noIVs = batch.items.filter { $0.state == .ivsMissing }.count
        let other = batch.items.filter { $0.state == .unsupported || $0.state == .unreadable || $0.state == .failed }.count
        var parts = ["\(ReviewFormat.count(added, "screenshot", "screenshots")) ready to review"]
        if held > 0 { parts.append("\(held) held back for your say") }
        if copies > 0 { parts.append("\(copies) the same screenshot as another") }
        if noIVs > 0 { parts.append("\(noIVs) without IVs") }
        if other > 0 { parts.append("\(other) could not be used") }
        var text = parts.joined(separator: ", ") + "."
        if noIVs > 0 { text += " IVs need all three appraisal bars on screen, finished filling." }
        return text
    }

    @ViewBuilder private var actions: some View {
        let ready = batch.isRead && !working && imports.preparing == nil && batch.pendingSave == nil
        if ready, batch.items.contains(where: \.canRetry) {
            Button("Try the failed ones again") { imports.retry(batch: batch.batchId) }
        }
        let n = batch.included.count
        Button {
            imports.openReview(batch: batch.batchId)
        } label: {
            Label(n == 0 ? "Nothing to review" : "Review \(ReviewFormat.count(n, "screenshot", "screenshots"))", systemImage: "checklist")
        }
        .disabled(!ready || n == 0 || { if case .account = owner { return false } else { return true } }())
        .accessibilityIdentifier("import-review")
        Button("Discard these screenshots", role: .destructive) { discarding = batch.batchId }
            .disabled(working)
    }
}

private struct ItemRow: View {
    @EnvironmentObject var model: AppModel
    let batch: ImportManifest
    let item: ImportItem
    let number: Int

    private var imports: ImportModel { model.screenshots }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: icon.name).foregroundStyle(icon.colour).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screenshot \(number)").font(.callout)
                    Text(status).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if item.canRetry { Button("Try again") { imports.retry(batch: batch.batchId, item: item.id) }.buttonStyle(.borderless) }
            }
            if item.hasHold {
                Toggle(item.repeatOf != nil ? "This is a different Pokémon" : "Import it again", isOn: Binding(get: { item.includeAnyway == true }, set: { imports.setIncluded(batch: batch.batchId, item: item.id, $0) }))
                    .font(.footnote)
                Button("Discard this screenshot", role: .destructive) { imports.discardItem(batch: batch.batchId, item: item.id) }.font(.footnote).buttonStyle(.borderless)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: (name: String, colour: Color) {
        if item.duplicateOf != nil { return ("doc.on.doc", .secondary) }
        switch item.state {
        case .pending: return ("clock", .secondary)
        case .read: return item.heldBack ? ("questionmark.circle.fill", .orange) : ("checkmark.circle.fill", .green)
        case .ivsMissing: return ("chart.bar.xaxis", .orange)
        case .unsupported, .unreadable, .failed: return ("exclamationmark.triangle.fill", .orange)
        }
    }

    private var status: String {
        if item.duplicateOf != nil { return "The same screenshot as another one, so it is used once." }
        switch item.state {
        case .pending: return "Waiting to be read."
        case .read:
            let title = StillImport.title(of: item) ?? "Read"
            if item.includeAnyway == true { return "\(title). Will be included." }
            if let earlier = item.repeatOf, let at = batch.items.firstIndex(where: { $0.id == earlier }) {
                return "\(title). Looks like the Pokémon in screenshot \(at + 1): a second screenshot of it, or another Pokémon with the same species and IVs. Held back until you say."
            }
            if let when = item.alreadyImported { return "\(title). This screenshot was imported on \(when.formatted(date: .abbreviated, time: .omitted)), so it is held back." }
            return "\(title). Will be added, or matched to a Pokémon already in the box and left unchanged."
        case .ivsMissing:
            return [StillImport.title(of: item), item.detail].compactMap { $0 }.joined(separator: ": ") + " Not added, because the IVs are what make a Pokémon known."
        case .unsupported, .unreadable, .failed: return (item.detail ?? "Could not be used.") + " Nothing was added from it."
        }
    }
}
