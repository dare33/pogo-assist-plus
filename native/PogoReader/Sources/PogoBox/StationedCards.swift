import Foundation
import PogoReader

/// Round 31c: the stationed cards of a stretch of readings with no CP and no HP (`BlankCards.find` hands the stretch over when it holds a reading flagged `stationed`).
/// A stationed Pokémon's card shows a name and the appraisal bars and nothing else the pipeline reads, so each card becomes ONE `Unmatched` item with reason `stationed`: the name
/// and species ids, the bars it settled on, no CP and no HP, the number of readings, and the CPs of the rows before and after the stretch (the same bounds a `blank-card` item has).
///
/// How a stretch is cut into cards, in this order:
/// 1. Readings with no name (the blank ones) and stationed readings are different runs. A stationed reading of another name starts another run; a single reading with a different name
///    between two readings of one name is a misread and joins them (a name at the end of the stretch is kept). Round 32: blank readings between two stationed readings of the same name
///    (the reader loses the card for a reading or two, `flickerGapPeriods`) are part of that card, not a separator.
/// 2. Inside a run of one name the bars decide, as the bars of a normal card do (`Refine.splitByBars`): a state is two or more consecutive readings with exactly equal bars at or above
///    `Refine.settledBarsConfidence`, a lone reading between two states is the card changing and belongs to the part it falls in, two states with equal bars either side of a lone reading are
///    one. Two or more states are cut halfway between the last reading of one and the first of the next, with no limit on the number of states (a stationed card does not move, so there
///    is no stall that changing bars would mean). One state or none: one part, whose bars are the state's (none when no two readings agreed). Round 32: a state whose part would last under
///    0.8 of a period is not a state of its own (the first readings of a card whose bars are still moving from the previous card's settle into two equal ones); it joins the longer neighbour.
/// 3. A part lasts a whole number of periods: `floor(length / period + 0.2)` cards, where length is the first reading to the last plus half the gap to the reading on each
///    side, each half-gap at most `BlankCards.blankReadingStep`. A part under 0.8 of a period is not a card (round 32: it used to be forced to one): it joins the stationed part of the same name
///    beside it, or is nothing. Two identical cards in a row are one part of two periods, and become two items, the readings shared between them (round 32 does not change this: no evidence
///    separates two identical cards from one card that stayed, see the README, Round 32).
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

    static func items(timed: [FrameReading], from i: Int, to j: Int, period: Double, cpBefore: Int, cpAfter: Int, stretch rowBefore: Int? = nil) -> [Unmatched] {
        let stretch = Array(timed[i...j])
        // 1. the label of each reading: nil for a blank one, the name key for a stationed one; a single odd name between two of the same is that name
        var labels: [String?] = stretch.map { $0.isStationed ? key($0) : nil }
        for k in 1..<max(1, stretch.count - 1) where labels[k] != nil && labels[k - 1] != nil && labels[k - 1] == labels[k + 1] && labels[k] != labels[k - 1] { labels[k] = labels[k - 1] }
        // blank readings between two stationed readings of one name, closer together than 0.8 of a period, are that card (`S B S B S` is one card)
        var g = 1
        while g < stretch.count - 1 {
            guard labels[g] == nil, let before = labels[g - 1] else { g += 1; continue }
            var e = g
            while e + 1 < stretch.count, labels[e + 1] == nil { e += 1 }
            if e + 1 < stretch.count, labels[e + 1] == before, stretch[e + 1].time! - stretch[g - 1].time! < BlankCards.minimumPeriods * period { for x in g...e { labels[x] = before } }
            g = e + 1
        }
        // the length a range of the stretch covers: first reading to last plus half the gap to the reading on each side (at most one blank step each)
        func length(_ range: Range<Int>) -> Double {
            let a = stretch[range.lowerBound].time!, b = stretch[range.upperBound - 1].time!
            let before = i + range.lowerBound > 0 ? timed[i + range.lowerBound - 1].time! : a
            let after = i + range.upperBound < timed.count ? timed[i + range.upperBound].time! : b
            return (b - a) + min(BlankCards.blankReadingStep, (a - before) / 2) + min(BlankCards.blankReadingStep, (after - b) / 2)
        }
        let minimumLength = BlankCards.minimumPeriods * period
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
                parts += cutByBars(Array(stretch[start...end]), offset: start, minimumLength: minimumLength, length: length).map { part in
                    var p = part; p.name = first.name; p.speciesIds = first.speciesIds; return p
                }
            }
            start = end + 1
        }
        // a stationed part under 0.8 of a period is not a card: it joins the stationed part of the same name beside it (the earlier first), or is nothing
        var m = 0
        while m < parts.count {
            guard parts[m].stationed, length(parts[m].range) < minimumLength else { m += 1; continue }
            func same(_ o: Int) -> Bool { o >= 0 && o < parts.count && parts[o].stationed && parts[o].name == parts[m].name && parts[o].speciesIds == parts[m].speciesIds }
            if same(m - 1) { parts[m - 1].range = parts[m - 1].range.lowerBound..<parts[m].range.upperBound }
            else if same(m + 1) { parts[m + 1].range = parts[m].range.lowerBound..<parts[m + 1].range.upperBound }
            parts.remove(at: m)
        }
        // 3. the cards of each part
        var out = [Unmatched]()
        for part in parts {
            let rs = Array(stretch[part.range])
            let n = Int((length(part.range) / period + (1 - BlankCards.minimumPeriods)).rounded(.down))
            guard n >= 1 else { continue }
            for card in 0..<n {
                // the readings shared out in time order, the first cards taking the remainder
                let lo = rs.count * card / n, hi = rs.count * (card + 1) / n
                let mine = rs[lo..<max(lo, hi)]
                if part.stationed {
                    out.append(Unmatched(frame: mine.first?.frame ?? rs[0].frame, cp: nil, name: part.name, nameText: nil, hp: nil, ivs: part.ivs, cpOptions: nil, frames: mine.count, reason: reason, into: nil, clip: nil,
                                         count: 1, cpBefore: cpBefore, cpAfter: cpAfter, speciesIds: part.speciesIds, stretch: rowBefore))
                } else {
                    out.append(Unmatched(frame: rs[0].frame, cp: nil, name: nil, nameText: nil, hp: nil, ivs: nil, cpOptions: nil, frames: rs.count, reason: BlankCards.reason, into: nil, clip: nil,
                                         count: n, cpBefore: cpBefore, cpAfter: cpAfter, stretch: rowBefore))
                    break
                }
            }
        }
        return out
    }

    /// The parts of a run of stationed readings of one name, cut at the changes of settled bars (see the type's comment, 2). A state whose part would last under `minimumLength` is dropped
    /// first (the shortest first; its readings fall to the neighbouring state, the longer one in the middle), and two states left with equal bars are one.
    private static func cutByBars(_ rs: [FrameReading], offset: Int, minimumLength: Double, length: (Range<Int>) -> Double) -> [Part] {
        let pool = rs.indices.filter { rs[$0].ivs != nil && rs[$0].ivConfidence >= Refine.settledBarsConfidence }
        var runs = [(ivs: IVs, idx: [Int])]()
        for k in pool {
            if let last = runs.last, last.ivs == rs[k].ivs! { runs[runs.count - 1].idx.append(k) } else { runs.append((rs[k].ivs!, [k])) }
        }
        var states = [(ivs: IVs, first: Int, last: Int)]()
        for r in runs where r.idx.count >= Refine.barsStateMinReadings {
            if let s = states.last, s.ivs == r.ivs { states[states.count - 1].last = r.idx.last! } else { states.append((r.ivs, r.idx.first!, r.idx.last!)) }
        }
        // the part each state would make: the cut falls halfway (in time) between the last reading of a state and the first of the next
        func ranges(_ states: [(ivs: IVs, first: Int, last: Int)]) -> [Range<Int>] {
            let cuts = zip(states, states.dropFirst()).map { (rs[$0.last].time! + rs[$1.first].time!) / 2 }
            var out = [Range<Int>](), from = 0
            for cut in cuts {
                let upTo = rs.indices.first { rs[$0].time! > cut } ?? rs.count
                out.append((offset + from)..<(offset + upTo)); from = upTo
            }
            out.append((offset + from)..<(offset + rs.count))
            return out
        }
        while states.count >= 2 {
            let rs = ranges(states)
            let lengths = rs.map { $0.isEmpty ? 0 : length($0) }
            guard let short = lengths.indices.filter({ lengths[$0] < minimumLength }).min(by: { lengths[$0] < lengths[$1] }) else { break }
            states.remove(at: short)
            if short > 0, short < states.count, states[short - 1].ivs == states[short].ivs {
                states[short - 1].last = states[short].last; states.remove(at: short)
            }
        }
        guard states.count >= 2 else {
            return [Part(range: offset..<(offset + rs.count), stationed: true, ivs: states.first?.ivs)]
        }
        let made = ranges(states)
        return states.indices.map { Part(range: made[$0], stationed: true, ivs: states[$0].ivs) }.filter { !$0.range.isEmpty }
    }
}
