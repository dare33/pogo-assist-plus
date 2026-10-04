import Foundation
import PogoReader

/// Cards that were on screen and never read, found from the timing alone. Under command paging every card stays about one period, so a stretch of readings with no name, no CP
/// text and no HP text that lasts a whole number of periods is that many cards the reader could not read (a Pokémon stationed at a Power Spot shows a card with no CP and no HP).
/// No row exists for them, so without this the saved entries they stand for are listed "Not seen" with nothing to say they were on screen.
///
/// What is not counted: the readings before the first row and after the last (the app, the list opening, the end of the list: no card on both sides); a stretch that touches a pause (the
/// extension waited there on purpose); a stretch with the same row on both sides of it (a menu or notification open on one Pokémon, which is not another card); and a stretch shorter than
/// 0.8 of a period.
public enum BlankCards {
    public static let reason = "blank-card"
    /// A stretch counts as one card from this fraction of a period (a reading step is 0.2 s of a 1.2 s period, and the first and last readings of a card are often missing).
    public static let minimumPeriods = 0.8
    /// The step between blank readings (0.2 s on the device: a blank frame is read twice as often as a card; run23's stretches).
    public static let blankReadingStep = 0.2

    public static func find(readings: [FrameReading], rows: [ScanRow], paging: PagingHint?) -> [Unmatched] {
        guard let hint = paging, hint.pagedByCommand, let period = hint.expectedPeriod, period > 0 else { return [] }
        let spans = ScanPace.spans(of: rows)
        guard spans.allSatisfy({ $0 != nil }), !rows.isEmpty else { return [] }
        let rowSpans = spans.compactMap { $0 }
        func blank(_ r: FrameReading) -> Bool { r.nameText.isEmpty && r.cpText.isEmpty && r.hpText.isEmpty }
        let timed = readings.filter { $0.time != nil }.sorted { $0.time! < $1.time! }
        var out = [Unmatched]()
        var i = 0
        while i < timed.count {
            guard blank(timed[i]) else { i += 1; continue }
            var j = i
            while j + 1 < timed.count, blank(timed[j + 1]) { j += 1 }
            defer { i = j + 1 }
            // a card reading on both sides
            guard i > 0, j + 1 < timed.count else { continue }
            let (first, last) = (timed[i].time!, timed[j].time!)
            let after = timed[j + 1].time!, before = timed[i - 1].time!
            // How long the blank readings cover: first to last, plus half the gap to the reading on each side (the change between cards falls midway), the half-gap capped at one blank step. Time with NO reading
            // beside the stretch (dropped frames) therefore counts for at most one step either side, so a gap with one blank reading in it is not a card and a stretch with dropped readings inside it still is.
            let duration = (last - first) + min(blankReadingStep, (first - before) / 2) + min(blankReadingStep, (after - last) / 2)
            let count = Int((duration / period + (1 - minimumPeriods)).rounded(.down))
            guard count >= 1 else { continue }
            if hint.pauses.contains(where: { $0.lowerBound <= after && $0.upperBound >= before }) { continue }
            // between two different rows: the row before has ended, the row after has not begun
            guard let b = rowSpans.lastIndex(where: { $0.last <= first }), b + 1 < rowSpans.count, rowSpans[b + 1].first >= last, rowSpans[b + 1].first > first else { continue }
            out.append(Unmatched(frame: timed[i].frame, cp: nil, name: nil, nameText: nil, hp: nil, ivs: nil, cpOptions: nil, frames: j - i + 1, reason: reason, into: nil, clip: nil,
                                 count: count, cpBefore: rows[b].cp, cpAfter: rows[b + 1].cp))
        }
        return out
    }

    /// The order the scanned rows come in, read from the rows themselves: nearly every neighbouring pair falls (a list sorted by CP, highest first) or rises. A misread or a card
    /// folded in breaks a few pairs, so 95% of the pairs that differ must agree. Nil when neither does (a list sorted by anything else): the bounds of a stretch then mean nothing.
    public enum Order { case descending, ascending }
    public static let orderAgreement = 0.95
    public static func cpOrder(_ rows: [ScanRow]) -> Order? {
        let cps = rows.map(\.cp).filter { $0 > 0 }
        var down = 0, up = 0
        for (a, b) in zip(cps, cps.dropFirst()) { if b < a { down += 1 } else if b > a { up += 1 } }
        let total = down + up
        guard total >= 20 else { return nil }
        if Double(down) >= orderAgreement * Double(total) { return .descending }
        if Double(up) >= orderAgreement * Double(total) { return .ascending }
        return nil
    }
}
