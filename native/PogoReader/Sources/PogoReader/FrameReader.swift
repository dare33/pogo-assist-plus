import Foundation

/// What the pixel work of `readFrame` (src/extract/frame.js) found in one frame, before any text is
/// read: anchors, the flags those decided, the appraisal bars, and the sharpness of the name crop.
/// The text reads then happen live (`FrameReader.read`) or later on saved crops
/// (`FrameReader.complete`); both go through the same two functions, so a deferred read of a frame
/// gives the same reading as a live one. Codable: a saved frame's JSON is this.
public struct FrameAnalysis: Codable, Equatable {
    public var frame: String?
    public var time: Double?
    /// Flags decided by the pixel work (mid-swipe, no-hp-bar, no-cp-text).
    public var flags: [String] = []
    /// False when the reading ends before any text is read (not a settled card).
    public var needsText = false
    /// The CP text was found (a tall model can hide it; the card is then read without CP).
    public var hasCpText = false
    /// The CP text is there but no HP bar (a special-background or buddy card, a bar the colour test
    /// misses): only the CP can be read, and the Pokémon is listed unnamed rather than lost.
    public var cpOnly = false
    /// The HP bar was placed by `findDamagedHpBar` (a damaged or fainted card), not by its green: the
    /// frame counts as a card only if the HP text under it parses (`complete`), else it is a CP-only
    /// frame flagged `no-hp-bar`, exactly as it was before the fallback existed. nil = no.
    public var damagedBar: Bool?
    public var sharpness = 0.0          // of the usual name crop
    public var sharpnessUp = 0.0        // of the Lucky second-look crop
    public var ivs: IVs?
    public var ivConfidence = 0.0
    public var fills: [Double]?
    /// Where the crops were cut, in frame pixels (information only).
    public var cpRect: Rect?
    public var nameRect: Rect?
    public var hpRect: Rect?
    /// "Save crops" mode: which on-screen segment (swipe to swipe) the frame belongs to.
    public var segment: Int?

    public init(frame: String? = nil, time: Double? = nil) { self.frame = frame; self.time = time }

    /// Bars settled: the appraisal panel finished animating (whole units).
    public var barsSettled: Bool { ivs != nil && ivConfidence >= SETTLED }
}

extension Rect: Codable {
    private enum K: String, CodingKey { case x, y, w, h }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        self.init(x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y), w: try c.decode(Double.self, forKey: .w), h: try c.decode(Double.self, forKey: .h))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(x, forKey: .x); try c.encode(y, forKey: .y); try c.encode(w, forKey: .w); try c.encode(h, forKey: .h)
    }
}

/// The small crops the text reads need; the only pixels that leave the frame buffer.
public struct FrameCrops {
    public var cp: RGBAImage?
    public var name: RGBAImage
    /// One line above the usual name position (the Lucky Pokémon second look).
    public var nameUp: RGBAImage
    public var hp: RGBAImage
}

/// Port of `readFrame` (src/extract/frame.js): anchors, text reads of CP / name / HP, bar IVs,
/// sharpness. The regions and the decisions are the JS ones; only the recogniser changed. The work is
/// split in two so the extension can do the pixel half alone (`analyse`) and leave the text reads
/// (`complete`) to the app: `read` is just the two in a row.
public final class FrameReader {
    public let text: TextReader
    public let names: [NameCandidate]
    public var cpPadding = Tuning.cpCropPadding
    public var cpIncludesPrefix = true

    public init(text: TextReader, names: [NameCandidate]) { self.text = text; self.names = names }

    private struct NameRead {
        var text: String
        var confidence: Double
        var match: NameMatch?
    }

    /// `cp` and `name` are nil when the frame is not a settled Pokémon screen; `flags` say why.
    public func read(_ img: RGBAImage, frame: String? = nil, time: Double? = nil, wantHp: Bool = true, wantBars: Bool = true) -> FrameReading {
        let (analysis, crops) = analyse(img, frame: frame, time: time)
        return complete(analysis, crops, wantHp: wantHp, wantBars: wantBars)
    }

    // MARK: - pixel half

    /// Anchors, bars and crops; no text is read. `crops` is nil when the frame is not a settled card.
    public func analyse(_ img: RGBAImage, frame: String? = nil, time: Double? = nil) -> (FrameAnalysis, FrameCrops?) {
        var a = FrameAnalysis(frame: frame, time: time)
        let rect = contentRect(img)
        guard rect.w > 0, rect.h > 0 else { a.flags.append("no-cp-text"); return (a, nil) }
        let cpText = findCpText(img, rect)
        var hpBar = findHpBar(img, rect)
        var damaged = false
        // Only with the CP centred: a frame the green search could not place and that has no settled CP text
        // stays what it was (no bar, or mid-swipe).
        if hpBar == nil, let c = cpText, c.centred, let bar = findDamagedHpBar(img, rect) { hpBar = bar; damaged = true }
        let regions = regionsFrom(rect, cpText, hpBar, cpPadding: cpPadding, cpIncludesPrefix: cpIncludesPrefix)
        guard let bar = hpBar, let nameRegion = regions.name, let hpRegion = regions.hp, let panel = regions.panelSearch else {
            a.flags.append(cpText == nil ? "no-cp-text" : "no-hp-bar")
            // Deviation from the JS reader (which stops here): a centred CP with no HP bar is still read, for
            // the CP alone. On the iPad clip three Pokémon (two with a special background, one Lucky
            // nicknamed one) show no HP bar at all and were otherwise invisible.
            if let c = cpText, c.centred {
                a.needsText = true; a.hasCpText = true; a.cpOnly = true; a.cpRect = regions.cp
                let empty = RGBAImage(width: 0, height: 0)
                return (a, FrameCrops(cp: crop(img, regions.cp), name: empty, nameUp: empty, hp: empty))
            }
            return (a, nil)
        }
        // Mid-swipe: the CP text is there but off-centre (the card is sliding).
        if let c = cpText, !c.centred { a.flags.append("mid-swipe"); return (a, nil) }
        // A tall model (Zapdos, Moltres) can cover the CP completely (fault 3). The name, HP and
        // bars are still on screen, and the grouper can work the CP out from them, so read on when
        // the HP bar sits where a settled card puts it (its left edge does not move when the
        // Pokémon is damaged).
        if cpText == nil {
            a.flags.append("no-cp-text")
            let left = Double(bar.x0 - rect.x) / Double(rect.w)
            if left < Tuning.settledBarLeft.lowerBound || left > Tuning.settledBarLeft.upperBound { return (a, nil) }
        }
        a.needsText = true
        a.hasCpText = cpText != nil
        if damaged { a.damagedBar = true }
        var up = nameRegion
        up.y -= Tuning.luckyLineOffset * Double(rect.h)
        a.cpRect = cpText != nil ? regions.cp : nil; a.nameRect = nameRegion; a.hpRect = hpRegion
        let nameCrop = crop(img, nameRegion), upCrop = crop(img, up)
        a.sharpness = laplacianVariance(nameCrop)
        a.sharpnessUp = laplacianVariance(upCrop)
        if let result = readBars(img, rect, panel).result { a.ivs = result.ivs; a.ivConfidence = result.confidence; a.fills = result.fills }
        return (a, FrameCrops(cp: cpText != nil ? crop(img, regions.cp) : nil, name: nameCrop, nameUp: upCrop, hp: crop(img, hpRegion)))
    }

    // MARK: - text half

    /// Read the text on the crops and assemble the reading, exactly as `readFrame` does.
    public func complete(_ a: FrameAnalysis, _ crops: FrameCrops?, wantHp: Bool = true, wantBars: Bool = true) -> FrameReading {
        var out = FrameReading(frame: a.frame, time: a.time)
        out.flags = a.flags
        guard a.needsText, let crops = crops else { return out }
        // A bar placed by the damaged-bar fallback is trusted only when the HP text under it is an HP: any
        // other screen with a bar-shaped band gets the reading it had before the fallback existed.
        var hpRead: TextRead?
        var cpOnly = a.cpOnly
        if a.damagedBar == true {
            let r = text.read(crops.hp, kind: .hp)
            if hpReadHasValidShape(r.text), parseHp(r.text) != nil { hpRead = r } else { cpOnly = true; out.flags.append("no-hp-bar") }
        }
        if cpOnly {
            if let cpCrop = crops.cp {
                let r = text.read(cpCrop, kind: .cp)
                out.cpText = r.text
                out.cp = cpReadHasValidShape(r.text) ? parseCp(r.text) : nil
                out.cpReads = out.cp.map { [$0] } ?? []
            }
            if out.cp == nil { out.flags.append("cp-unread") }
            return out
        }
        if let cpCrop = crops.cp {
            let r = text.read(cpCrop, kind: .cp)
            out.cpText = r.text
            out.cp = cpReadHasValidShape(r.text) ? parseCp(r.text) : nil
            if let cp = out.cp { out.cpReads = [cp] } else { out.cpReads = [] }
        }

        // Tesseract reported confidence 0 for a line with anything it could not place, so a read
        // whose whole text is exactly a species name (four letters or more) is taken whatever the
        // confidence; Vision gives a real confidence, but the rule stays: a near miss, or a match
        // that dropped a word, still needs confidence.
        func readName(_ crop: RGBAImage) -> NameRead {
            let r = text.read(crop, kind: .name)
            let letterWords = r.words.filter { hasLetterRun($0.text) }
            let confidence = letterWords.isEmpty ? 0 : letterWords.reduce(0) { $0 + $1.confidence } / Double(letterWords.count)
            let found = matchName(r.text, names)
            var ok = false
            if let f = found { ok = confidence >= Tuning.weakNameConfidence || (f.distance == 0 && f.whole && f.text.count >= 4) }
            return NameRead(text: r.text, confidence: confidence, match: ok ? found : nil)
        }
        var nameRead = readName(crops.name)
        out.sharpness = a.sharpness
        // Fault 2: a Lucky Pokémon has a "LUCKY POKÉMON" line between its name and the HP bar, so
        // the name sits higher: when nothing matched, look one line up. That line is the model's
        // feet on any other screen, so only a confident, exact, whole read of four letters or more
        // counts there.
        if nameRead.match == nil {
            let lucky = readName(crops.nameUp)
            if let m = lucky.match, lucky.confidence >= Tuning.luckyNameConfidence, m.distance == 0, m.whole, m.text.count >= 4 {
                nameRead = lucky
                out.sharpness = a.sharpnessUp
            }
        }
        out.nameText = nameRead.text
        out.nameConfidence = nameRead.confidence
        if let m = nameRead.match {
            out.name = m.candidate.display
            out.baseName = m.candidate.name
            out.form = m.candidate.form
            out.speciesIds = m.candidate.speciesIds
            out.nameDistance = m.distance
            // Fault 1: if Vision actually read the Nidoran symbol, the sex is known: narrow the
            // species to it. Otherwise the name stays "Nidoran" with both candidates and the
            // sex is left to the stats.
            if m.candidate.display == "Nidoran", let id = nidoranSex(inRawText: nameRead.text) {
                out.speciesIds = [id]
                out.baseName = id == "nidoran_female" ? "Nidoran♀" : "Nidoran♂"
            }
            // A name taken without confidence (Nidoran aside: its symbol is what could not be
            // placed). The grouper uses such a frame only when a neighbouring frame agrees.
            out.nameWeak = nameRead.confidence < Tuning.weakNameConfidence && !m.symbol
            if m.attached { out.nameAttached = true }
        } else if !nameRead.text.isEmpty { out.flags.append("name-unmatched") }

        if out.cp == nil && a.hasCpText { out.flags.append("cp-unread") }
        // A frame without an identifiable Pokémon is not a reading (the grouper asks for a name),
        // but it keeps its CP so a Pokémon on screen under a nickname can be listed.
        if out.name == nil { return out }

        if wantHp {
            let r = hpRead ?? text.read(crops.hp, kind: .hp)
            out.hpText = r.text
            out.hp = hpReadHasValidShape(r.text) ? parseHp(r.text) : nil
            if out.hp == nil { out.flags.append("hp-unread") }
        }
        if wantBars {
            if a.ivs != nil { out.ivs = a.ivs; out.ivConfidence = a.ivConfidence; out.fills = a.fills }
            else { out.flags.append("no-bars") }
        }
        return out
    }
}

private func hasLetterRun(_ s: String) -> Bool {
    var run = 0
    for c in s.unicodeScalars {
        if (c.value >= 65 && c.value <= 90) || (c.value >= 97 && c.value <= 122) { run += 1; if run >= 2 { return true } } else { run = 0 }
    }
    return false
}
