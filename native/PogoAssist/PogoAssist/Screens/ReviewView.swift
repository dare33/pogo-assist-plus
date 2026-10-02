import SwiftUI
import PogoBox
import PogoReader

/// What a finished scan found and what saving it would do to the box. Nothing changes until "Save to box".
struct ReviewView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            Group {
                switch model.flow {
                case .idle: Color.clear
                case .processing(let what): processing(what)
                case .failed(let message, _): failed(message)
                case .review(let r): ResultList(review: r)
                }
            }
            .navigationTitle("Scan result")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }

    private func processing(_ what: String) -> some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(what).font(.headline)
            Text("This takes a few seconds. Nothing is saved yet.").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundStyle(.orange)
            Text("The scan could not be read").font(.title3.bold())
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Try again") { model.retryReview() }.buttonStyle(.borderedProminent)
            Button("Discard scan", role: .destructive) { model.discardReview() }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ResultList: View {
    @EnvironmentObject var model: AppModel
    let review: AppModel.Review
    @State private var confirmDiscard = false
    @State private var open: Set<String> = []

    private var plan: BoxMerge.Plan { review.plan }
    private var saved: [String: BoxEntry] { Dictionary(review.base.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private func scanned(_ i: Int) -> ScanRow { plan.scanned[i] }
    /// The scan ran at a pace unlike the command last made: probably an older command played.
    private var paceWarning: String? {
        guard let pace = review.outcome.pace else { return nil }
        return (model.pagedByHand || review.reread != nil) ? nil : PaceCheck.check(measured: pace.medianPeriod, chosen: model.pace)
    }
    private var blocker: String? { model.saveBlocker(review) }

    var body: some View {
        List {
            Section {
                countsRow
                row("Scan time", Fmt.duration(review.outcome.duration))
                row("Frames read", "\(review.outcome.readings)")
                if let pace = review.outcome.pace { row("Pace", "about \(String(format: "%.1f", pace.medianPeriod)) s per Pokémon") }
                if let warning = paceWarning { Label(warning, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange) }
                row("Box", review.account)
                if let plan = review.reread { rereadNotes(plan) }
                if review.reread == nil { Picker("Scan kind", selection: Binding(get: { review.kind }, set: { k in Task { await model.setReviewKind(k) } })) {
                    Text("Full scan").tag(BoxStore.Kind.full)
                    Text("Add and update").tag(BoxStore.Kind.partial)
                }
                .pickerStyle(.segmented) }
            }
            if !plan.unsure.isEmpty {
                Section {
                    ForEach(plan.unsure, id: \.scanned) { u in UnsureCard(unsure: u, row: scanned(u.scanned), saved: saved) }
                } header: { Text("Needs your answer (\(plan.unsure.count))") } footer: { Text("These are never guessed. Answer each one, then Save to box is available.") }
            }
            Section("What saving will do") {
                group("new", "New", plan.new.count, "plus.circle") {
                    ForEach(plan.new, id: \.self) { i in
                        if let base = plan.megaBases[i] {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(scanned(i).title), IVs \(Fmt.ivs(scanned(i).ivs))").font(.callout)
                                Text("Mega evolved when scanned. It will be saved as \((try? GameMaster.bundled().byId[base]?.name) ?? base) with no CP, HP or level, marked to check, because the Mega values are temporary.").font(.footnote).foregroundStyle(.secondary)
                            }
                        } else { Text(Fmt.brief(scanned(i))).font(.callout) }
                    }
                }
                group("updated", "Updated", plan.updated.count, "arrow.up.circle") {
                    ForEach(plan.updated, id: \.scanned) { u in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(saved[u.savedId]?.row.title ?? "Pokémon").font(.callout)
                            Text(change(u)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                group("same", "Same", plan.same.count, "equal.circle") {
                    ForEach(plan.same, id: \.scanned) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fmt.brief(scanned(p.scanned))).font(.callout)
                            if p.mega { Text("Mega evolved when scanned. The saved \(saved[p.savedId]?.row.title ?? "Pokémon") keeps its own values.").font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                }
                HStack { Label("Unsure", systemImage: "questionmark.circle"); Spacer(); Text("\(plan.unsure.count)").foregroundStyle(.secondary).monospacedDigit() }
                if review.kind == .full {
                    group("gone", "Gone", plan.gone.count, "minus.circle") {
                        ForEach(plan.gone, id: \.self) { id in
                            if let e = saved[id] { Text(Fmt.brief(e.row)).font(.callout) }
                        }
                    }
                }
            }
            if review.kind == .full && !plan.gone.isEmpty {
                Section { Text("These are in your box but the scan did not see them. If the scan stopped early, choose Add and update above so nothing is removed.").font(.footnote).foregroundStyle(.secondary) }
            }
            let flagged = review.outcome.scan.rows.indices.filter { review.outcome.scan.rows[$0].needsCheck }
            Section("To check in the game (\(flagged.count))") {
                if flagged.isEmpty { Text("Nothing needs a check.").foregroundStyle(.secondary) }
                ForEach(flagged, id: \.self) { i in
                    let r = review.outcome.scan.rows[i]
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "\(r.title), CP \(r.cp)").font(.callout.weight(.medium))
                        ForEach(r.checkFlags, id: \.self) { f in Text(FlagInfo.explain(f)).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }
            let unmatched = review.outcome.scan.unmatched
            Section("On screen but not read (\(unmatched.count))") {
                if unmatched.isEmpty { Text("Every Pokémon on screen was read.").foregroundStyle(.secondary) }
                ForEach(Array(unmatched.enumerated()), id: \.offset) { _, u in Text(Fmt.unmatched(u)).font(.callout) }
            }
            if !review.outcome.notices.isEmpty {
                Section("Notes") { ForEach(review.outcome.notices, id: \.self) { Text($0).font(.footnote) } }
            }
        }
        .safeAreaInset(edge: .bottom) { actions }
        .confirmationDialog("Discard this scan?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard scan", role: .destructive) { model.discardReview() }
        } message: { Text("Nothing will be added to the box.") }
    }

    private var actions: some View {
        VStack(spacing: 6) {
            if let blocker { Text(blocker).font(.footnote).foregroundStyle(.secondary) }
            HStack {
                Button("Discard", role: .destructive) { confirmDiscard = true }.buttonStyle(.bordered).controlSize(.large)
                Button { Task { await model.saveReview() } } label: { Text("Save to box").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(blocker != nil)
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    /// The three numbers that matter, first: how many were read, how many need a look in the game, how many need an answer here.
    private var countsRow: some View {
        let toCheck = review.outcome.scan.rows.filter(\.needsCheck).count
        return HStack(alignment: .top) {
            count("\(review.outcome.scan.rows.count)", "read")
            count("\(toCheck)", "to check")
            count("\(plan.unsure.count)", "need your answer")
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func rereadNotes(_ r: RereadPlan) -> some View {
        Text("Reading the scan from \(Fmt.date(r.scan.scanDate)) again, against the box as it was before that scan was saved. Nothing changes until you save.").font(.footnote).foregroundStyle(.secondary)
        if r.hasLaterChanges {
            Label(laterText(r), systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
        }
    }

    private func laterText(_ r: RereadPlan) -> String {
        var parts = [String]()
        if r.laterScans > 0 { parts.append("Scans saved after this one are not included; read them again too.") }
        if r.laterEdits > 0 { parts.append("Corrections made after it are not included either.") }
        return parts.joined(separator: " ") + " Saving makes a new box version from the earlier box; every earlier version stays in Settings."
    }

    private func count(_ number: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: number).font(.title.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary).monospacedDigit() }
    }

    private func change(_ u: BoxMerge.Update) -> String {
        let s = scanned(u.scanned), old = saved[u.savedId]?.row
        switch u.reason {
        case .poweredUp: return "Powered up: CP \(old?.cp ?? 0) to \(s.cp)"
        case .evolved: return "Evolved from \(old?.name ?? "?"): now \(s.title), CP \(s.cp)"
        case .ivsNowRead: return "IVs now read: \(Fmt.ivs(s.ivs))"
        case .megaToBase: return "Saved in its Mega form before; now \(s.title), CP \(s.cp)"
        case .chosen: return "Matched by you: now CP \(s.cp)"
        }
    }

    @ViewBuilder private func group<C: View>(_ key: String, _ title: String, _ count: Int, _ icon: String, @ViewBuilder content: @escaping () -> C) -> some View {
        if count == 0 {
            HStack { Label(title, systemImage: icon); Spacer(); Text("0").foregroundStyle(.secondary) }
        } else {
            DisclosureGroup(isExpanded: Binding(get: { open.contains(key) }, set: { if $0 { open.insert(key) } else { open.remove(key) } })) { content() } label: {
                HStack { Label(title, systemImage: icon); Spacer(); Text("\(count)").foregroundStyle(.secondary).monospacedDigit() }
            }
        }
    }
}

