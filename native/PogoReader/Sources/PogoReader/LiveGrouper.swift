import Foundation

/// One Pokémon as the phone shows it: what the live list displays and the extension writes out.
public struct LiveRow: Codable, Equatable {
    public var index: Int
    public var name: String
    public var cp: Int?
    public var hp: Int?
    public var ivs: IVs?
    public var frames: Int
    public var flags: [String]
    /// Where the Pokémon was on screen: first and last frame label and time (seconds), for the
    /// timeline report and for matching rows to on-screen segments.
    public var firstFrame: String?
    public var lastFrame: String?
    public var firstTime: Double?
    public var lastTime: Double?
}

/// A streaming grouper for the phone: consecutive readings of one Pokémon become one row. It keeps
/// the same rules as the JS merge (src/extract/merge.js): same name, a CP that is `cpSimilar`,
/// agreeing HP, compatible settled bars; unreadable frames do not break a run; within a run CP, HP
/// and bars are voted. Memory is bounded: the current run's tallies plus finished rows (small
/// structs), never the readings themselves.
///
/// What it leaves to the JS `finish()` (not in this proof): the CP solver (a small check against
/// HP and bars stands in for it), absorbing one-frame strays into a neighbour, and the whole-clip
/// weak-name placement (here a weak name is held back until the next confident Pokémon decides).
public struct LiveGrouper {
    private struct Tally { var n = 0; var first = 0; var last = 0 }

    private struct Run {
        var weak: Bool
        var name: String
        var speciesIds: [String]
        var frames = 0
        var lastCp = 0
        var hp: HP?                 // first HP read: what later frames must agree with
        var ivs: IVs?               // first settled bars
        var cpTally = [Int: Tally]()
        var hpTally = [Int: Tally]()
        var ivTally = [IVs: Tally]()    // settled reads only
        var lastIvs: IVs?               // latest read of any kind
        var lastIvConfidence = 0.0
        var stamp = 0
        var startedAfterSwipe = false
        var firstFrame: String?, lastFrame: String?, firstTime: Double?, lastTime: Double?

        init(_ r: FrameReading, weak: Bool) {
            self.weak = weak
            firstFrame = r.frame; firstTime = r.time
            name = r.name ?? ""
            speciesIds = r.speciesIds ?? []
            add(r)
        }

        private static func bump<K: Hashable>(_ t: inout [K: Tally], _ stamp: inout Int, _ k: K, cap: Int) {
            stamp += 1
            var e = t[k] ?? Tally(n: 0, first: stamp, last: 0)
            e.n += 1; e.last = stamp
            t[k] = e
            if t.count > cap, let drop = t.min(by: { ($0.value.n, $0.value.last) < ($1.value.n, $1.value.last) })?.key { t[drop] = nil }
        }

        mutating func add(_ r: FrameReading) {
            frames += 1
            lastFrame = r.frame; lastTime = r.time
            if hp == nil, let h = r.hp { hp = h }
            if let h = r.hp { Run.bump(&hpTally, &stamp, h.max, cap: 8) }
            if let v = r.ivs {
                lastIvs = v; lastIvConfidence = r.ivConfidence
                if r.ivConfidence >= SETTLED { if ivs == nil { ivs = v }; Run.bump(&ivTally, &stamp, v, cap: 12) }
            }
            for c in r.cpReads ?? (r.cp.map { [$0] } ?? []) { Run.bump(&cpTally, &stamp, c, cap: 16) }
            if let c = r.cp { lastCp = c }
            // A Nidoran whose symbol was read narrows the species; keep the latest narrowing.
            if name == "Nidoran", let ids = r.speciesIds, ids.count == 1 { speciesIds = ids }
        }

        /// The most-read CP, ties to the first seen (JS `joins`).
        var topCp: Int { cpTally.max(by: { ($0.value.n, -$0.value.first) < ($1.value.n, -$1.value.first) })?.key ?? lastCp }

        /// Whether a reading could be this run's Pokémon (merge.js `joins`).
        func joins(_ r: FrameReading) -> Bool {
            guard r.name == name, let cp = r.cp else { return false }
            if let a = hp, let b = r.hp, a.max != b.max { return false }
            let top = topCp
            let reads = r.cpReads ?? [cp]
            // Contradictory settled bars split the run only when the CP read also differs: with the
            // same CP a mid-animation read can look settled by chance, but a different CP and
            // different bars is another Pokémon (adjacent hatched Meltan at CP 150 and 151, say).
            if let a = ivs, let b = r.ivs, r.ivConfidence >= SETTLED, !ivsCompatible(a, b), !reads.contains(top) { return false }
            if reads.contains(where: { cpRelated($0, lastCp) || cpRelated($0, top) }) { return true }
            // A badly garbled CP read on a frame whose HP and settled bars match the run exactly is
            // still the same Pokémon.
            if let a = hp, let b = r.hp, let x = ivs, let y = r.ivs, r.ivConfidence >= SETTLED, a.max == b.max, x == y { return true }
            return false
        }

        /// Values ranked by count, ties to the later one (merge.js `ranked`).
        func ranked<K: Hashable>(_ t: [K: Tally]) -> [K] {
            t.sorted { ($0.value.n, $0.value.last) > ($1.value.n, $1.value.last) }.map(\.key)
        }
    }

    private struct Unnamed {
        var cps = [Int: Int]()
        var lastCp: Int
        var frames = 0
        var firstFrame: String?, lastFrame: String?, firstTime: Double?, lastTime: Double?
        var topCp: Int { cps.max(by: { $0.value < $1.value })?.key ?? lastCp }
    }

    /// A Pokémon on screen with a name but no CP at all (the model covered it).
    private struct Hidden {
        var name: String
        var speciesIds: [String]
        var hp: Int?
        var frames = 0
        var ivTally = [IVs: Tally]()
        var stamp = 0
        var prevBeside: Bool        // sits right beside the run before it
        var firstFrame: String?, lastFrame: String?, firstTime: Double?, lastTime: Double?
        func settledIvs() -> IVs? { ivTally.max(by: { ($0.value.n, $0.value.last) < ($1.value.n, $1.value.last) })?.key }
    }

    private let table: SpeciesTable?
    private var finished = [LiveRow]()
    private var current: Run?
    private var hidden: Hidden?
    private var weakPending: Run?
    /// Frames with a CP but no species name (a nickname, a card with no HP bar): a stretch of several
    /// related CPs is listed as an unnamed row so the Pokémon is not silently missing.
    private var unnamed: Unnamed?
    /// An unreadable frame (no name) lies between the last Pokémon frame and now.
    private var gap = false
    /// Consecutive frames with neither a CP nor an HP read; `swipe` says this many came right before the
    /// reading being consumed (a swipe happened: the next card is a new Pokémon).
    private var sepRun = 0
    private var swipe = false

    public init(species: SpeciesTable?) { table = species }

    /// Finished rows plus the one in progress.
    public var rows: [LiveRow] {
        var out = finished
        if let c = current { out.append(makeRow(c, index: finished.count + 1)) }
        return out
    }

    /// Feed one reading. Returns true when `rows` changed.
    @discardableResult
    public mutating func add(_ r: FrameReading) -> Bool {
        let before = current.map { makeRow($0, index: finished.count + 1) }
        let finishedBefore = finished.count
        consume(r)
        let after = current.map { makeRow($0, index: finished.count + 1) }
        return before != after || finished.count != finishedBefore
    }

    /// End of the stream: settle what is pending and close the last run. Returns true when rows changed.
    @discardableResult
    public mutating func finish() -> Bool {
        let before = rows
        resolveHidden(next: nil, gapAfter: true, swipe: true)
        if let w = weakPending {
            // JS keeps weak-only rows only when the clip has no confident row at all.
            if finished.isEmpty && current == nil { finished.append(makeRow(w, index: finished.count + 1)) }
            weakPending = nil
        }
        var none: Run? = nil
        closeCurrent(next: &none)
        flushUnnamed()
        return rows != before
    }

    // MARK: - one reading

    private mutating func consume(_ r: FrameReading) {
        let isCard = r.cp != nil || r.hp != nil
        swipe = sepRun >= Tuning.swipeSeparatorFrames
        if isCard { sepRun = 0 } else { sepRun += 1 }
        guard let name = r.name else {
            if let cp = r.cp { addUnnamed(r, cp: cp) } else { gap = true }   // mid-swipe, cut off
            return
        }
        if r.cp == nil {
            if r.nameWeak == true { gap = true } else { addHidden(r) }
            return
        }
        // "Nidoran" with a letter stuck to it, next to a Nidorina or Nidorino, is that Pokémon's name
        // misread by a letter: unreadable, so it cannot split the run.
        if name == "Nidoran", r.nameAttached == true, let c = current, c.name == "Nidorina" || c.name == "Nidorino" { gap = true; return }
        if r.nameWeak == true { addWeak(r); return }
        addStrong(r)
    }

    private mutating func addStrong(_ r: FrameReading) {
        if var c = current, !swipe, c.joins(r) {
            resolveHidden(next: c, gapAfter: gap, swipe: false)
            // A weak frame of another name inside this Pokémon's time on screen is set aside.
            weakPending = nil
            c.add(r)
            current = c
            gap = false
            return
        }
        var fresh = Run(r, weak: false)
        fresh.startedAfterSwipe = swipe
        closeCurrent(next: &fresh)
        flushUnnamed()
        let prevName = finished.last?.name
        resolveHidden(next: fresh, gapAfter: gap, swipe: swipe)
        if let w = weakPending {
            // A weak read between two Pokémon is dropped when it has the name of either (it may be
            // that Pokémon's first or last frame); otherwise nothing confident accounts for it.
            if !finished.isEmpty, w.name != prevName.map(Self.plainName), w.name != fresh.name { finished.append(makeRow(w, index: finished.count + 1)) }
            weakPending = nil
        }
        current = fresh
        gap = false
    }

    /// Close the run in progress into a finished row. A short run that is no Pokémon of its own (no
    /// settled bars, or a CP that does not fit its HP and bars) next to a row of the same Pokémon with a
    /// related CP is a card caught mid-slide (a partial CP while the model crosses the text): its frames
    /// go to that neighbour, the one it slid out of if no swipe came between, else the one it slid into.
    private mutating func closeCurrent(next: inout Run) {
        var none: Run? = next
        closeCurrent(next: &none)
        if let n = none { next = n }
    }

    private mutating func closeCurrent(next: inout Run?) {
        guard let c = current else { return }
        current = nil
        let row = makeRow(c, index: finished.count + 1)
        if c.frames <= Tuning.strayMaxFrames, isStray(c, row) {
            if !c.startedAfterSwipe, let p = finished.last, p.name == row.name, Self.cpsRelated(p.cp, row.cp) {
                finished[finished.count - 1].frames += c.frames
                finished[finished.count - 1].lastFrame = c.lastFrame; finished[finished.count - 1].lastTime = c.lastTime
                return
            }
            if var n = next, !n.startedAfterSwipe, n.name == c.name,
               Self.cpsRelated(n.topCp, row.cp) || Self.cpsRelated(makeRow(n, index: 0).cp, row.cp) {   // the next row's CP may be the recovered one (971 is 1971)
                n.frames += c.frames
                n.firstFrame = c.firstFrame; n.firstTime = c.firstTime
                n.startedAfterSwipe = c.startedAfterSwipe
                next = n
                return
            }
        }
        finished.append(row)
    }

    private static func cpsRelated(_ a: Int?, _ b: Int?) -> Bool {
        guard let a = a, let b = b else { return true }
        return cpRelated(a, b)
    }

    private func isStray(_ run: Run, _ row: LiveRow) -> Bool {
        if row.ivs == nil || row.flags.contains("bars-unsettled") { return true }
        if let t = table, let ivs = row.ivs, let cp = row.cp, cpFits(t.species(for: run.speciesIds), cp: cp, hp: row.hp, ivs: ivs) == false { return true }
        return false
    }

    /// A CP with no name. Inside a named Pokémon's time on screen (a frame whose name was misread) it adds
    /// nothing; otherwise it builds an unnamed stretch.
    private mutating func addUnnamed(_ r: FrameReading, cp: Int) {
        if let c = current, !swipe, cpRelated(cp, c.lastCp) || cpRelated(cp, c.topCp) { gap = false; return }
        if var u = unnamed, !swipe, cpRelated(cp, u.lastCp) || cpRelated(cp, u.topCp) {
            u.frames += 1; u.lastCp = cp; u.cps[cp, default: 0] += 1; u.lastFrame = r.frame; u.lastTime = r.time
            unnamed = u
        } else {
            flushUnnamed()
            unnamed = Unnamed(cps: [cp: 1], lastCp: cp, frames: 1, firstFrame: r.frame, lastFrame: r.frame, firstTime: r.time, lastTime: r.time)
        }
        gap = true
    }

    private mutating func flushUnnamed() {
        guard let u = unnamed else { return }
        unnamed = nil
        guard u.frames >= Tuning.unnamedMinFrames else { return }
        finished.append(LiveRow(index: finished.count + 1, name: "(name not read)", cp: u.topCp, hp: nil, ivs: nil, frames: u.frames, flags: ["name-not-read"],
                                firstFrame: u.firstFrame, lastFrame: u.lastFrame, firstTime: u.firstTime, lastTime: u.lastTime))
    }

    private mutating func addWeak(_ r: FrameReading) {
        // A weak read of the current Pokémon's own name adds nothing and splits nothing.
        if let c = current, c.name == r.name { return }
        if var w = weakPending, w.joins(r) { w.add(r); weakPending = w } else { weakPending = Run(r, weak: true) }
        gap = true
    }

    private mutating func addHidden(_ r: FrameReading) {
        let ivs = (r.ivs != nil && r.ivConfidence >= SETTLED) ? r.ivs : nil
        let hpMax = r.hp?.max
        if var h = hidden, h.name == r.name, !swipe, h.hp == nil || hpMax == nil || h.hp == hpMax,
           !gap || ivsCompatible(h.settledIvs(), ivs) {
            h.frames += 1
            h.lastFrame = r.frame; h.lastTime = r.time
            if h.hp == nil { h.hp = hpMax }
            if let v = ivs { h.stamp += 1; var e = h.ivTally[v] ?? Tally(n: 0, first: h.stamp, last: 0); e.n += 1; e.last = h.stamp; h.ivTally[v] = e }
            hidden = h
        } else {
            let hadOther = hidden != nil
            resolveHidden(next: nil, gapAfter: true, swipe: true)
            var h = Hidden(name: r.name ?? "", speciesIds: r.speciesIds ?? [], hp: hpMax, prevBeside: false)
            h.frames = 1
            h.firstFrame = r.frame; h.lastFrame = r.frame; h.firstTime = r.time; h.lastTime = r.time
            if let v = ivs { h.stamp = 1; h.ivTally[v] = Tally(n: 1, first: 1, last: 1) }
            if let c = current { h.prevBeside = Self.beside(h, c, gapBetween: gap || hadOther, swipe: swipe) }
            hidden = h
        }
        gap = false
    }

    /// A hidden stretch right beside a run of the same Pokémon (same name, HP not different, bars not
    /// contradicting, no unreadable frame between) is that Pokémon with its model in front of the CP
    /// for a moment; otherwise it is listed as a row of its own.
    /// `swipe`: a swipe lies between them. `gapBetween`: some unreadable frame does. An exact match of HP
    /// and settled bars survives the second (a frame or two lost) but never the first.
    private static func beside(_ h: Hidden, _ run: Run, gapBetween: Bool, swipe: Bool = false) -> Bool {
        guard !swipe, run.name == h.name, h.hp == nil || run.hp == nil || run.hp!.max == h.hp, ivsCompatible(run.ivs, h.settledIvs()) else { return false }
        if !gapBetween { return true }
        return h.hp != nil && run.hp?.max == h.hp && run.ivs != nil && run.ivs == h.settledIvs()
    }

    private mutating func resolveHidden(next: Run?, gapAfter: Bool, swipe: Bool) {
        guard let h = hidden else { return }
        hidden = nil
        let nextBeside = next.map { Self.beside(h, $0, gapBetween: gapAfter, swipe: swipe) } ?? false
        // One or two frames with no HP read are a card caught sliding in or out, not a Pokémon to list.
        let substantial = h.hp != nil || h.frames >= 3
        if h.prevBeside || nextBeside || !substantial { return }
        var flags = ["cp-not-read"]
        var cp: Int? = nil
        let ivs = h.settledIvs()
        if let t = table {
            let opts = cpOptions(t.species(for: h.speciesIds), hp: h.hp, ivs: ivs).options
            // One level fits the HP and the settled bars: that is the CP, worked out (the model hid all
            // of it). Flagged for a check in the game, like a recovered CP.
            if opts.count == 1 { cp = opts[0]; flags = ["cp-computed:\(opts[0])"] }
            else if !opts.isEmpty && opts.count <= 6 { flags.append("cp-options:" + opts.map(String.init).joined(separator: "|")) }
        }
        finished.append(LiveRow(index: finished.count + 1, name: Self.displayName(h.name, h.speciesIds), cp: cp, hp: h.hp, ivs: ivs, frames: h.frames, flags: flags,
                                firstFrame: h.firstFrame, lastFrame: h.lastFrame, firstTime: h.firstTime, lastTime: h.lastTime))
    }

    // MARK: - rows

    private static func plainName(_ display: String) -> String { display.hasPrefix("Nidoran") ? "Nidoran" : display }

    private static func displayName(_ name: String, _ ids: [String]) -> String {
        guard name == "Nidoran", ids.count == 1 else { return name }
        return ids[0] == "nidoran_female" ? "Nidoran♀" : "Nidoran♂"
    }

    private func makeRow(_ run: Run, index: Int) -> LiveRow {
        var flags = [String]()
        let candidates = run.ranked(run.cpTally)
        var cp: Int? = candidates.first
        let hp = run.ranked(run.hpTally).first
        // Bars: only settled reads count (the panel animates from the previous Pokémon's values);
        // they are voted, ties to the later read. With none settled, the last read is the closest
        // to the final state and is flagged.
        let settled = run.ranked(run.ivTally)
        var ivs: IVs? = settled.first
        if ivs == nil, let last = run.lastIvs { ivs = last; flags.append("bars-unsettled") }
        if settled.count > 1 { flags.append("ivs-disagree") }

        if let t = table, let top = candidates.first, let settledIvs = settled.first {
            let species = t.species(for: run.speciesIds)
            // The first CP read (ranked by how many frames read it) that fits the HP and bars; failing
            // that, work the CP out from them (fault 3): when a model covers the leading digits the
            // reads are the tail of the real CP. Take it when exactly one such CP ends in a read and
            // no read at all is as long as it (a full-length read that does not fit means misread
            // bars, not a hidden digit). The row stays flagged for a check in the game.
            if let fit = candidates.first(where: { cpFits(species, cp: $0, hp: hp, ivs: settledIvs) == true }) {
                cp = fit
                if fit != top { flags.append("cp-chosen-\(fit)-over-\(top)") }
            } else {
                let o = cpOptions(species, hp: hp, ivs: settledIvs, ivConfidence: 1, reads: candidates)
                if o.supported.count == 1, let rec = o.supported.first,
                   !candidates.contains(where: { String($0).count >= String(rec).count }) {
                    cp = rec
                    flags.append("cp-recovered:\(rec)-from-\(o.tailOf[rec]!)")
                }
            }
        }
        if run.weak { flags.append("name-low-confidence") }
        if run.name == "Nidoran" && run.speciesIds.count != 1 { flags.append("sex-from-stats") }
        if hp == nil { flags.append("hp-unread") }
        if ivs == nil { flags.append("no-bars") }
        return LiveRow(index: index, name: Self.displayName(run.name, run.speciesIds), cp: cp, hp: hp, ivs: ivs, frames: run.frames, flags: flags,
                       firstFrame: run.firstFrame, lastFrame: run.lastFrame, firstTime: run.firstTime, lastTime: run.lastTime)
    }
}
