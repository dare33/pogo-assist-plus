import Foundation
import PogoReader

/// Round 31c: the stationed cards of a stretch of readings with no CP and no HP (`BlankCards.find` hands the stretch over when it holds a reading flagged `stationed`).
/// A stationed Pokémon's card shows a name and the appraisal bars and nothing else the pipeline reads, so each card becomes ONE `Unmatched` item with reason `stationed`: the name
/// and species ids, the bars it settled on, no CP and no HP, the number of readings, and the CPs of the rows before and after the stretch (the same bounds a `blank-card` item has).
///
/// How a stretch is cut into cards, in this order:
/// 1. Readings with no name (the blank ones) and stationed readings are different runs. A stationed reading of another name starts another run; a single reading with a different name
///    between two readings of one name is a misread and joins them (a name at the end of the stretch is kept).
/// 2. Inside a run of one name the bars decide, as the bars of a normal card do (`Refine.splitByBars`): a state is two or more consecutive readings with exactly equal bars at or above
///    `Refine.settledBarsConfidence`, a lone reading between two states is the card changing and belongs to the part it falls in, two states with equal bars either side of a lone reading are
///    one. Two or more states are cut halfway between the last reading of one and the first of the next, with no limit on the number of states (a stationed card does not move, so there
///    is no stall that changes its bars). One state or none: one part, whose bars are the state's (none when no two readings agreed).
/// 3. A part lasts a whole number of periods: `floor(length / period + 0.2)` cards, at least one, where length is the first reading to the last plus half the gap to the reading on each
///    side, each half-gap at most `BlankCards.blankReadingStep`. Two identical cards in a row are one part of two periods, and become two items, the readings shared between them.
///
/// A run of blank readings between or beside stationed cards is counted as `blank-card` cards by the same length rule as any blank stretch.
public enum StationedCards {
    public static let reason = "stationed"

    private struct Part {
        var range: Range<Int>     // positions in the stretch
        var stationed: Bool
        var name: String?, speciesIds: [String]?
        var ivs: IVs?
    }

    private static func key(_ r: FrameReading) -> String { ((r.speciesIds ?? []).joined(separator: ",")) + "|" + (r.name ?? "") }

    static func items(timed: [FrameReading], from i: Int, to j: Int, period: Double, cpBefore: Int, cpAfter: Int) -> [Unmatched] {
        let stretch = Array(timed[i...j])
        // 1. the label of each reading: nil for a blank one, the name key for a stationed one; a single odd name between two of the same is that name
        var labels: [String?] = stretch.map { $0.isStationed ? key($0) : nil }
        for k in 1..<max(1, stretch.count - 1) where labels[k] != nil && labels[k - 1] != nil && labels[k - 1] == labels[k + 1] && labels[k] != labels[k - 1] { labels[k] = labels[k - 1] }
        var parts = [Part]()
        var start = 0
        while start < stretch.count {
            var end = start
            while end + 1 < stretch.count, labels[end + 1] == labels[start] { end += 1 }
            if labels[start] == nil {
                parts.append(Part(range: start..<(end + 1), stationed: false))
            } else {
                // 2. the bars inside the run of one name
                let first = stretch[start]
                parts += cutByBars(Array(stretch[start...end]), offset: start).map { part in
                    var p = part; p.name = first.name; p.speciesIds = first.speciesIds; return p
                }
            }
            start = end + 1
        }
        // 3. the cards of each part
        var out = [Unmatched]()
        for part in parts {
            let rs = Array(stretch[part.range])
            let a = rs.first!.time!, b = rs.last!.time!
            let before = i + part.range.lowerBound > 0 ? timed[i + part.range.lowerBound - 1].time! : a
            let after = i + part.range.upperBound < timed.count ? timed[i + part.range.upperBound].time! : b
            let length = (b - a) + min(BlankCards.blankReadingStep, (a - before) / 2) + min(BlankCards.blankReadingStep, (after - b) / 2)
            var n = Int((length / period + (1 - BlankCards.minimumPeriods)).rounded(.down))
            if part.stationed { n = max(1, n) }
            guard n >= 1 else { continue }
            for card in 0..<n {
                // the readings shared out in time order, the first cards taking the remainder
                let lo = rs.count * card / n, hi = rs.count * (card + 1) / n
                let mine = rs[lo..<max(lo, hi)]
                if part.stationed {
                    out.append(Unmatched(frame: mine.first?.frame ?? rs[0].frame, cp: nil, name: part.name, nameText: nil, hp: nil, ivs: part.ivs, cpOptions: nil, frames: mine.count, reason: reason, into: nil, clip: nil,
                                         count: 1, cpBefore: cpBefore, cpAfter: cpAfter, speciesIds: part.speciesIds))
                } else {
                    out.append(Unmatched(frame: rs[0].frame, cp: nil, name: nil, nameText: nil, hp: nil, ivs: nil, cpOptions: nil, frames: rs.count, reason: BlankCards.reason, into: nil, clip: nil,
                                         count: n, cpBefore: cpBefore, cpAfter: cpAfter))
                    break
                }
            }
        }
        return out
    }

    /// The parts of a run of stationed readings of one name, cut at the changes of settled bars (see the type's comment, 2).
    private static func cutByBars(_ rs: [FrameReading], offset: Int) -> [Part] {
        let pool = rs.indices.filter { rs[$0].ivs != nil && rs[$0].ivConfidence >= Refine.settledBarsConfidence }
        var runs = [(ivs: IVs, idx: [Int])]()
        for k in pool {
            if let last = runs.last, last.ivs == rs[k].ivs! { runs[runs.count - 1].idx.append(k) } else { runs.append((rs[k].ivs!, [k])) }
        }
        var states = [(ivs: IVs, first: Int, last: Int)]()
        for r in runs where r.idx.count >= Refine.barsStateMinReadings {
            if let s = states.last, s.ivs == r.ivs { states[states.count - 1].last = r.idx.last! } else { states.append((r.ivs, r.idx.first!, r.idx.last!)) }
        }
        guard states.count >= 2 else {
            return [Part(range: offset..<(offset + rs.count), stationed: true, ivs: states.first?.ivs)]
        }
        // the cut falls halfway (in time) between the last reading of a state and the first of the next
        let cuts = zip(states, states.dropFirst()).map { (rs[$0.last].time! + rs[$1.first].time!) / 2 }
        var parts = [Part](), from = 0
        for (n, cut) in cuts.enumerated() {
            let upTo = rs.indices.first { rs[$0].time! > cut } ?? rs.count
            parts.append(Part(range: (offset + from)..<(offset + upTo), stationed: true, ivs: states[n].ivs)); from = upTo
        }
        parts.append(Part(range: (offset + from)..<(offset + rs.count), stationed: true, ivs: states.last!.ivs))
        return parts.filter { !$0.range.isEmpty }
    }
}
