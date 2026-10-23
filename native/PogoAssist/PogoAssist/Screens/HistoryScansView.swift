import SwiftUI
import PogoBox

/// Settings > History and scans: the box's versions and the saved scans, one tab each, narrowed to a month so a long list
/// is a short one. Everything the two inline Settings sections did is here unchanged.
struct HistoryScansView: View {
    enum Tab: Hashable { case history, scans }
    /// A month the person picked, or all of them.
    enum Choice: Hashable { case all, month(MonthKey) }

    @EnvironmentObject var model: AppModel
    @Environment(\.accent) private var accent
    @State private var tab: Tab = .history
    @State private var chosen: [Tab: Choice] = [:]
    @State private var shareURLs: [URL] = []
    @State private var restoring: BoxSnapshot.Header?

    private var historyMonths: [MonthKey] { MonthGroups.months(of: model.history, date: \.createdAt) }
    private var scanMonths: [MonthKey] { MonthGroups.months(of: model.scans, date: \.scanDate) }
    private var months: [MonthKey] { tab == .history ? historyMonths : scanMonths }

    /// The person's pick if that month still has entries; otherwise the latest month that does, or All when there are none.
    private var choice: Choice {
        if let c = chosen[tab] {
            if c == .all { return c }
            if case .month(let m) = c, months.contains(m) { return c }
        }
        return months.first.map { .month($0) } ?? .all
    }
    private var monthFilter: MonthKey? { if case .month(let m) = choice { return m } else { return nil } }

    private func dropStalePicks() {
        for (t, c) in chosen { if case .month(let m) = c, !(t == .history ? historyMonths : scanMonths).contains(m) { chosen[t] = nil } }
    }

    private var choiceBinding: Binding<Choice> { Binding(get: { choice }, set: { chosen[tab] = $0 }) }

    private func scanRow(_ scan: BoxStore.Summary) -> some View {
        let kind: String = scan.source == ScreenshotImporter.source ? "Screenshot import" : scan.kind == .full ? "Full scan" : "Add and update"
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.date(scan.scanDate)).font(.figtree(16, .semibold, relativeTo: .callout)).foregroundStyle(Theme.ink)
                Text("\(kind), \(scan.rows) Pokémon read").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                if let sent = scan.reportSentAt { Text("Sent \(Fmt.day(sent))").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted) }
                if let again = scan.lastReread { Text("Read again \(Fmt.date(again))").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted) }
            }
            Spacer()
            Menu {
                // A screenshot import has no replay log to read again, and nothing a report could carry.
                if scan.source != ScreenshotImporter.source { Button { model.rereadScan(scan) } label: { Label("Read again with the latest rules", systemImage: "arrow.triangle.2.circlepath") } }
                if model.reportsEnabled && scan.source != ScreenshotImporter.source { Button { model.reportTarget = .saved(scan.id) } label: { Label("Make scans better", systemImage: "paperplane") } }
                Button { shareURLs = model.shareFiles(for: scan) } label: { Label("Share scan files", systemImage: "square.and.arrow.up") }
            } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Scan actions")
        }
    }

    @ViewBuilder private func historyRow(_ h: BoxSnapshot.Header) -> some View {
        let isCurrent: Bool = h.seq == model.history.first?.seq
        VStack(alignment: .leading, spacing: 2) {
            Text("Version \(h.seq): \(h.note)").font(.figtree(16, .semibold, relativeTo: .callout)).foregroundStyle(Theme.ink)
            Text(Fmt.date(h.createdAt)).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
        }
        .swipeActions {
            if !isCurrent && !model.boxNeedsNewerApp { Button("Restore") { restoring = h }.tint(.blue) }
        }
    }

    private var switchRow: some View {
        VStack(spacing: 10) {
            SegmentedSwitch(
                segments: [.init(value: Tab.history, title: "History", identifier: "history-tab-history"),
                           .init(value: Tab.scans, title: "Scans", identifier: "history-tab-scans")],
                selection: $tab, label: "History or scans", identifier: "history-tabs")
            Picker("Month", selection: choiceBinding) {
                Text("All").tag(Choice.all).accessibilityIdentifier("history-month-all")
                ForEach(months, id: \.self) { Text($0.title()).tag(Choice.month($0)) }
            }
            .pickerStyle(.menu)
            .font(.figtree(16, .semibold, relativeTo: .body))
            .accessibilityIdentifier("history-month")
        }
        .padding(.vertical, 4)
    }

    var body: some View {
        List {
            Section { switchRow }
            if tab == .history {
                Section {
                    if !model.historyLoaded { Text("Loading…").foregroundStyle(Theme.muted) }
                    else if model.history.isEmpty { Text("No saved versions yet.").foregroundStyle(Theme.muted) }
                    ForEach(MonthGroups.filter(model.history, to: monthFilter, date: \.createdAt), id: \.seq) { historyRow($0) }
                } footer: { Text("Every scan and every correction is kept as a version. Swipe a version to restore it; the current box stays in the history.") }
            } else {
                Section {
                    if !model.scansLoaded { Text("Loading…").foregroundStyle(Theme.muted) }
                    else if model.scans.isEmpty { Text("No saved scans yet.").foregroundStyle(Theme.muted) }
                    ForEach(MonthGroups.filter(model.scans, to: monthFilter, date: \.scanDate), id: \.id) { scanRow($0) }
                } footer: { Text("Share a scan's replay log and result to send them for diagnosis.") }
            }
        }
        // Settings is a sheet, so the root's tint does not reach here.
        .tint(accent.solid)
        .navigationTitle("History and scans")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { model.loadScans() }
        // A pick whose month has gone (its last entry removed) is dropped, so it cannot come back if that month fills again later.
        .onChange(of: historyMonths) { _, _ in dropStalePicks() }
        .onChange(of: scanMonths) { _, _ in dropStalePicks() }
        // Presented from here: Settings is itself a sheet, and this screen is pushed inside it.
        .sheet(item: $model.reportTarget) { MakeScansBetterSheet(target: $0).environmentObject(model) }
        .sheet(isPresented: Binding(get: { !shareURLs.isEmpty }, set: { if !$0 { shareURLs = [] } })) {
            ShareSheet(urls: shareURLs).presentationDetents([.medium, .large])
        }
        .confirmationDialog("Restore version \(restoring?.seq ?? 0)?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }), titleVisibility: .visible) {
            Button("Restore this version") { if let r = restoring { Task { await model.restore(seq: r.seq) } } }
        } message: { Text("The box as it is now stays in the history.") }
    }
}
