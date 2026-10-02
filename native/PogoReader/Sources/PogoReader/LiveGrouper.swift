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
/// the same rules as the JS merge (src/extract/merge.js): same name, a CP that is `cpRelated`,
/// agreeing HP, compatible settled bars; unreadable frames do not break a run; within a run CP, HP
/// and bars are voted. Memory is bounded: the current run's tallies plus finished rows (small
/// structs), never the readings themselves.
///
/// Every threshold is a DURATION computed from the readings' times, not a frame count, because the
/// extension drops frames while Vision is busy (a card is then seen in two or three readings, not
/// seven). A swipe is seen by either of two things: `Tuning.swipeSeparatorSeconds` of consecutive readings
/// that are not cards (no CP, no HP, and no name that has lasted `hiddenMinSeconds`), or a swipe tick from the
/// extension's luma signature (`swipe(at:)`), which sees frames that were never read. The signature is not
/// reliable everywhere (it misses swipes on the iPad and on hand-tapped paging), so a swipe it or the separators
/// miss is not seen: two identical neighbours can then merge. What the grouper cannot know it leaves a trace for:
/// `absorbed:<cp>`, `long-stay` (a row that spans `Tuning.longStaySeconds` or more may be two identical Pokémon
/// whose swipe was not seen), `same-as-previous` (a run started only by a tick that reads like the row before),
/// `short-run`, `no-level-fits`, `name-low-confidence`, `sex-not-read`.
///
/// What it leaves to the JS `finish()` (not in this proof): the full CP solver (a small check against
/// HP and bars stands in for it) and the whole-clip weak-name placement.
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
        var sameAsPrevious = false       // started only by a swipe tick yet reads like the row before
        var absorbed = [Int]()          // CPs of strays folded into this run
        var firstFrame: String?, lastFrame: String?
        var firstT: Double, lastT: Double

        init(_ r: FrameReading, t: Double, weak: Bool) {
            self.weak = weak
            firstFrame = r.frame; firstT = t; lastT = t
            name = r.name ?? ""
            speciesIds = r.speciesIds ?? []
            add(r, t: t)
        }

        /// Time on screen: first to last reading plus one frame period.
        var duration: Double { lastT - firstT + Tuning.framePeriod }

        private static func bump<K: Hashable>(_ t: inout [K: Tally], _ stamp: inout Int, _ k: K, cap: Int) {
            stamp += 1
            var e = t[k] ?? Tally(n: 0, first: stamp, last: 0)
            e.n += 1; e.last = stamp
            t[k] = e
            if t.count > cap, let drop = t.min(by: { ($0.value.n, $0.value.last) < ($1.value.n, $1.value.last) })?.key { t[drop] = nil }
        }

        mutating func add(_ r: FrameReading, t: Double) {
            frames += 1
            lastFrame = r.frame; lastT = t
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

        var tallySize: Int { cpTally.count + hpTally.count + ivTally.count }

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

    /// Frames with a CP but no species name (a nickname, a card with no HP bar).
    private struct Unnamed {
        var cps = [Int: Int]()
        var lastCp: Int
        var frames = 0
        var startedAfterSwipe = false
        var firstFrame: String?, lastFrame: String?
        var firstT: Double, lastT: Double
        var topCp: Int { cps.max(by: { $0.value < $1.value })?.key ?? lastCp }
        var duration: Double { lastT - firstT + Tuning.framePeriod }
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
        var firstFrame: String?, lastFrame: String?
        var firstT: Double, lastT: Double
        var duration: Double { lastT - firstT + Tuning.framePeriod }
        func settledIvs() -> IVs? { ivTally.max(by: { ($0.value.n, $0.value.last) < ($1.value.n, $1.value.last) })?.key }
    }

    private let table: SpeciesTable?
    private var finished = [LiveRow]()
    private var current: Run?
    private var hidden: Hidden?
    private var weakPending: Run?
    private var unnamed: Unnamed?
    /// An unreadable frame (no name) lies between the last Pokémon frame and now.
    private var gap = false
    /// Consecutive readings with neither a CP nor an HP read, from `sepStart` to `sepLast`; `swipe` says
    /// they covered `Tuning.swipeSeparatorSeconds` right before the reading being consumed (a swipe
    /// happened: the next card is a new Pokémon).
    private var sepStart: Double?
    private var sepLast = 0.0
    private var swipe = false
    private var tickOnly = false          // the swipe was seen only by a tick (no separator frames)
    private var seenCard = false
    private var clock = 0.0
    /// Time of the last card reading, and the pending swipe ticks (a swipe seen by the cheap luma signature on
    /// frames that were never read). A tick in (last card, this reading] is a swipe.
    private var lastCardT = -Double.infinity
    private var ticks = [Double]()                 // pending swipe tick times (bounded)
    private var prevReadingT = -Double.infinity
    private var gapSinceCard = 0.0                 // the longest silence between readings since the last card
    private var nameOnlyStart: Double?, nameOnlyLast = 0.0, nameOnlyName = ""

    public init(species: SpeciesTable?) { table = species }

    /// Finished rows plus the one in progress.
    public var rows: [LiveRow] {
        var out = finished
        if let c = current { out.append(makeRow(c, index: finished.count + 1)) }
        return out
    }

    /// Size of the in-progress run's tallies (tests check that it stays bounded).
    var debugTallySize: Int { current?.tallySize ?? 0 }

    /// Feed one reading. Returns true when `rows` changed.
    @discardableResult
    public mutating func add(_ r: FrameReading) -> Bool {
        let before = current.map { makeRow($0, index: finished.count + 1) }
        let finishedBefore = finished.count
        consume(r)
        let after = current.map { makeRow($0, index: finished.count + 1) }
        return before != after || finished.count != finishedBefore
    }

    /// A swipe was seen at `time` without reading the frame (the luma signature in the extension's callback, on
    /// every kept frame even while Vision is busy). The next card reading after it is a new Pokémon, even when
    /// it reads exactly like the last: a swipe the reader never got a frame of is still seen, so two identical
    /// neighbours stay two rows (when the signature saw the swipe).
    public mutating func swipe(at time: Double) {
        guard time.isFinite else { return }
        if ticks.count >= Tuning.maxPendingTicks { ticks.removeFirst() }   // the oldest goes
        ticks.append(time)
    }

    /// End of the stream: close the last run, then settle what is pending after it (in time order).
    @discardableResult
    public mutating func finish() -> Bool {
        let before = rows
        var none: Run? = nil
        closeCurrent(next: &none)
        flushUnnamed(next: nil)                    // the same order as when a next Pokémon starts
        resolveHidden(next: nil, gapAfter: true, swipe: true)
        resolveWeak(next: nil)
        return rows != before
    }

    // MARK: - one reading

    private mutating func consume(_ r: FrameReading) {
        // Reading time; a reading with none follows the last by one frame period, and time never runs backwards.
        let t = max(r.time ?? (clock + Tuning.framePeriod), clock)
        clock = t
        // A card is a reading of a Pokémon with a CP or an HP. A name alone (CP and HP hidden) is a card only once
        // the same name has lasted `Tuning.hiddenMinSeconds`: shorter, it is a card sliding past and counts as a
        // separator frame, like an anchor-less one.
        var isCard = r.cp != nil || r.hp != nil
        if r.cp == nil && r.hp == nil, let n = r.name {
            if nameOnlyStart == nil || nameOnlyName != n || t - nameOnlyLast > Tuning.nameOnlyGapSeconds { nameOnlyStart = t; nameOnlyName = n }
            nameOnlyLast = t
            if t - nameOnlyStart! + Tuning.framePeriod >= Tuning.hiddenMinSeconds - 1e-9 { isCard = true }
        } else { nameOnlyStart = nil }
        let seenSeparators = sepStart != nil && (sepLast - sepStart! + Tuning.framePeriod) >= Tuning.swipeSeparatorSeconds - 1e-9
        // Ticks older than the last card are used up; any in (last card, t] is a swipe.
        ticks.removeAll { $0 <= lastCardT + 1e-9 }
        // A tick is evidence only where readings are missing: if every frame since the last card was read (no silence
        // longer than 1.5 frame periods), the readings already show whether a swipe happened, and a tick there can
        // only be a false jump (the iPad's leader animation) that would split a Pokémon.
        if prevReadingT.isFinite { gapSinceCard = max(gapSinceCard, t - prevReadingT) }
        prevReadingT = t
        let seenTick = gapSinceCard > 1.5 * Tuning.framePeriod && ticks.contains { $0 <= t + 1e-9 }
        swipe = seenSeparators || seenTick
        tickOnly = seenTick && !seenSeparators
        if isCard { sepStart = nil; lastCardT = t; gapSinceCard = 0; if !seenCard { seenCard = true; swipe = true; tickOnly = false } } else { if sepStart == nil { sepStart = t }; sepLast = t }
        guard let name = r.name else {
            if let cp = r.cp { addUnnamed(r, cp: cp, t: t) } else { gap = true }   // mid-swipe, cut off
            return
        }
        if r.cp == nil {
            if r.nameWeak == true { gap = true } else { addHidden(r, t: t) }
            return
        }
        // "Nidoran" with a letter stuck to it, next to a Nidorina or Nidorino, is that Pokémon's name
        // misread by a letter: unreadable, so it cannot split the run.
        if name == "Nidoran", r.nameAttached == true, let c = current, c.name == "Nidorina" || c.name == "Nidorino" { gap = true; return }
        if r.nameWeak == true { addWeak(r, t: t); return }
        addStrong(r, t: t)
    }

    private mutating func addStrong(_ r: FrameReading, t: Double) {
        if var c = current, !swipe, c.joins(r) {
            resolveHidden(next: c, gapAfter: gap, swipe: false)
            // A weak frame of another name inside this Pokémon's time on screen is set aside.
            weakPending = nil
            c.add(r, t: t)
            current = c
            gap = false
            return
        }
        var fresh = Run(r, t: t, weak: false)
        fresh.startedAfterSwipe = swipe
        closeCurrent(next: &fresh)
        // A run started only because a tick said so, that reads like the row before it (same name, HP and settled
        // bars not different, related CP), is either a genuine twin or a false split: flagged either way.
        if tickOnly, let p = finished.last, Self.plainName(p.name) == fresh.name, Self.related(p.cp, p.hp, r.cp, r.hp?.max),
           !(p.ivs != nil && r.ivs != nil && r.ivConfidence >= SETTLED && p.ivs != r.ivs) { fresh.sameAsPrevious = true }
        flushUnnamed(next: fresh)
        resolveHidden(next: fresh, gapAfter: gap, swipe: swipe)
        resolveWeak(next: fresh)
        current = fresh
        gap = false
    }

    /// Close the run in progress into a finished row. A short run that is no Pokémon of its own (no
    /// settled bars, or a CP that does not fit its HP and bars) next to a row of the same Pokémon with a
    /// related CP and an HP that does not differ is a card caught mid-slide (a partial CP while the model
    /// crosses the text): its frames go to that neighbour, the one it slid out of if no swipe came
    /// between, else the one it slid into. The absorbing row says so (`absorbed:<cp>`).
    private mutating func closeCurrent(next: inout Run) {
        var none: Run? = next
        closeCurrent(next: &none)
        if let n = none { next = n }
    }

    private mutating func closeCurrent(next: inout Run?) {
        guard let c = current else { return }
        current = nil
        let row = makeRow(c, index: finished.count + 1)
        if c.duration <= Tuning.strayMaxSeconds + 1e-9, isStray(c, row) {
            if !c.startedAfterSwipe, let p = finished.last, p.name == row.name, Self.related(p.cp, p.hp, row.cp, row.hp) {
                finished[finished.count - 1].frames += c.frames
                finished[finished.count - 1].lastFrame = c.lastFrame; finished[finished.count - 1].lastTime = c.lastT
                if let cp = row.cp { Self.addTrace(&finished[finished.count - 1].flags, "absorbed:\(cp)") }
                return
            }
            if var n = next, !n.startedAfterSwipe, n.name == c.name {
                let nextRow = makeRow(n, index: 0)   // its CP may be the recovered one (971 is 1971)
                if Self.related(n.topCp, nextRow.hp, row.cp, row.hp) || Self.related(nextRow.cp, nextRow.hp, row.cp, row.hp) {
                    n.frames += c.frames
                    n.firstFrame = c.firstFrame; n.firstT = c.firstT
                    n.startedAfterSwipe = c.startedAfterSwipe
                    if let cp = row.cp { n.absorbed.append(cp) }
                    next = n
                    return
                }
            }
        }
        finished.append(row)
    }

    private static func addTrace(_ flags: inout [String], _ f: String) { if !flags.contains(f) { flags.append(f) } }

    /// Same Pokémon by CP and HP: CPs related, and HPs not different (an unread HP does not differ).
    private static func related(_ cpA: Int?, _ hpA: Int?, _ cpB: Int?, _ hpB: Int?) -> Bool {
        if let a = hpA, let b = hpB, a != b { return false }
        guard let a = cpA, let b = cpB else { return true }
        return cpRelated(a, b)
    }

    private func isStray(_ run: Run, _ row: LiveRow) -> Bool {
        if row.ivs == nil || row.flags.contains("bars-unsettled") { return true }
        if let t = table, let ivs = row.ivs, let cp = row.cp, cpFits(t.species(for: run.speciesIds), cp: cp, hp: row.hp, ivs: ivs) == false { return true }
        return false
    }

    /// A CP with no name. Inside a named Pokémon's time on screen (a frame whose name was misread) it adds
    /// nothing; otherwise it builds an unnamed stretch.
    private mutating func addUnnamed(_ r: FrameReading, cp: Int, t: Double) {
        if let c = current, !swipe, cpRelated(cp, c.lastCp) || cpRelated(cp, c.topCp) { gap = false; return }
        if var u = unnamed, !swipe, cpRelated(cp, u.lastCp) || cpRelated(cp, u.topCp) {
            u.frames += 1; u.lastCp = cp; u.cps[cp, default: 0] += 1; u.lastFrame = r.frame; u.lastT = t
            unnamed = u
        } else {
            flushUnnamed(next: nil)
            unnamed = Unnamed(cps: [cp: 1], lastCp: cp, frames: 1, startedAfterSwipe: swipe, firstFrame: r.frame, lastFrame: r.frame, firstT: t, lastT: t)
        }
        gap = true
    }

    /// List the unnamed stretch if it lasted `Tuning.unnamedMinSeconds` (two frames at full rate, as in JS)
    /// and is not just a card sliding past the neighbour it is the CP of.
    private mutating func flushUnnamed(next: Run?) {
        guard let u = unnamed else { return }
        unnamed = nil
        guard u.duration >= Tuning.unnamedMinSeconds - 1e-9 else { return }
        if !u.startedAfterSwipe, let p = finished.last, let pc = p.cp, cpRelated(u.topCp, pc) { return }
        if let n = next, !n.startedAfterSwipe, cpRelated(u.topCp, n.topCp) || makeRow(n, index: 0).cp.map({ cpRelated(u.topCp, $0) }) == true { return }
        finished.append(LiveRow(index: finished.count + 1, name: "(name not read)", cp: u.topCp, hp: nil, ivs: nil, frames: u.frames, flags: ["name-not-read"],
                                firstFrame: u.firstFrame, lastFrame: u.lastFrame, firstTime: u.firstT, lastTime: u.lastT))
    }

    private mutating func addWeak(_ r: FrameReading, t: Double) {
        // A weak read of the current Pokémon's own name adds nothing and splits nothing, unless a swipe
        // came between (then it is another Pokémon).
        if let c = current, c.name == r.name, !swipe { return }
        if var w = weakPending, !swipe, w.joins(r) { w.add(r, t: t); weakPending = w }
        else {
            resolveWeak(next: nil)
            var w = Run(r, t: t, weak: true)
            w.startedAfterSwipe = swipe
            weakPending = w
        }
        gap = true
    }

    /// A Pokémon read only with a weak name. JS drops these at the ends of a clip because clips are joined
    /// by matching their last and first rows; live there is no join, so they are kept as flagged rows
    /// (`name-low-confidence`). Dropped only when they are that neighbour's own first or last frames: the
    /// same name with a related CP and HP, or when no swipe set them apart from the Pokémon they sit in.
    private mutating func resolveWeak(next: Run?) {
        guard let w = weakPending else { return }
        weakPending = nil
        let wrow = makeRow(w, index: finished.count + 1)
        if let p = finished.last, Self.plainName(p.name) == w.name, Self.related(p.cp, p.hp, wrow.cp, wrow.hp) { return }
        if let n = next, n.name == w.name {
            let nrow = makeRow(n, index: 0)
            if Self.related(nrow.cp, nrow.hp, wrow.cp, wrow.hp) { return }
        }
        // No swipe before it, and a confident Pokémon around: a misread name of that Pokémon's own frames.
        if !w.startedAfterSwipe && (!finished.isEmpty || next != nil) { return }
        finished.append(wrow)
    }

    private mutating func addHidden(_ r: FrameReading, t: Double) {
        let ivs = (r.ivs != nil && r.ivConfidence >= SETTLED) ? r.ivs : nil
        let hpMax = r.hp?.max
        if var h = hidden, h.name == r.name, !swipe, h.hp == nil || hpMax == nil || h.hp == hpMax,
           !gap || ivsCompatible(h.settledIvs(), ivs) {
            h.frames += 1
            h.lastFrame = r.frame; h.lastT = t
            if h.hp == nil { h.hp = hpMax }
            if let v = ivs { h.stamp += 1; var e = h.ivTally[v] ?? Tally(n: 0, first: h.stamp, last: 0); e.n += 1; e.last = h.stamp; h.ivTally[v] = e }
            hidden = h
        } else {
            let hadOther = hidden != nil
            resolveHidden(next: nil, gapAfter: true, swipe: true)
            var h = Hidden(name: r.name ?? "", speciesIds: r.speciesIds ?? [], hp: hpMax, prevBeside: false, firstFrame: r.frame, lastFrame: r.frame, firstT: t, lastT: t)
            h.frames = 1
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
        // A card with no HP read that lasted under `hiddenMinSeconds` is a card caught sliding in or out, not a Pokémon to list.
        let substantial = h.hp != nil || h.duration >= Tuning.hiddenMinSeconds - 1e-9
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
                                firstFrame: h.firstFrame, lastFrame: h.lastFrame, firstTime: h.firstT, lastTime: h.lastT))
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
        var ids = run.speciesIds

        if let t = table, let top = candidates.first, let settledIvs = settled.first {
            let species = t.species(for: ids)
            // The first CP read (ranked by how many frames read it) that fits the HP and bars; failing
            // that, work the CP out from them (fault 3): when a model covers the leading digits the
            // reads are the tail of the real CP. Take it when exactly one such CP ends in a read and
            // no read at all is as long as it (a full-length read that does not fit means misread
            // bars, not a hidden digit). The row stays flagged for a check in the game. If nothing
            // fits and nothing is recovered, the row says so (`no-level-fits`, as JS does): the CP is
            // the most-read one but nothing supports it.
            if let fit = candidates.first(where: { cpFits(species, cp: $0, hp: hp, ivs: settledIvs) == true }) {
                cp = fit
                if fit != top { flags.append("cp-chosen-\(fit)-over-\(top)") }
            } else {
                let o = cpOptions(species, hp: hp, ivs: settledIvs, ivConfidence: 1, reads: candidates)
                if o.supported.count == 1, let rec = o.supported.first,
                   !candidates.contains(where: { String($0).count >= String(rec).count }) {
                    cp = rec
                    flags.append("cp-recovered:\(rec)-from-\(o.tailOf[rec]!)")
                } else {
                    flags.append("no-level-fits")
                }
            }
            // Nidoran without the symbol read: the sex whose stats fit the CP, HP and bars, if exactly one does.
            if run.name == "Nidoran", ids.count > 1, let c = cp {
                let fits = ids.filter { cpFits(t.species(for: [$0]), cp: c, hp: hp, ivs: settledIvs) == true }
                if fits.count == 1 { ids = fits; if hp == nil { flags.append("sex-from-stats-no-hp") } }
            }
        }
        if run.sameAsPrevious { flags.append("same-as-previous") }
        if run.weak { flags.append("name-low-confidence") }
        if run.name == "Nidoran" && ids.count != 1 { flags.append("sex-not-read") }
        if hp == nil { flags.append("hp-unread") }
        if ivs == nil { flags.append("no-bars") }
        // A trace for each fold of a stray into this row, and for a stay long enough to be two identical Pokémon.
        for c in run.absorbed { Self.addTrace(&flags, "absorbed:\(c)") }
        if run.duration >= Tuning.longStaySeconds - 1e-6 { flags.append("long-stay") }
        // Seen for under `shortRunSeconds` (one frame at full rate): too little evidence to leave unmarked.
        if run.duration < Tuning.shortRunSeconds - 1e-9 { flags.append("short-run") }
        return LiveRow(index: index, name: Self.displayName(run.name, ids), cp: cp, hp: hp, ivs: ivs, frames: run.frames, flags: flags,
                       firstFrame: run.firstFrame, lastFrame: run.lastFrame, firstTime: run.firstT, lastTime: run.lastT)
    }
}
