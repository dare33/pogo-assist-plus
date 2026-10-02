import Foundation

/// Port of `readFrame` (src/extract/frame.js): anchors, text reads of CP / name / HP, bar IVs,
/// sharpness. A pure function of the image plus a text reader; the grouper decides what to do with
/// the readings. The regions and the decisions are the JS ones; only the recogniser changed.
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
        var sharpness: Double
    }

    /// `cp` and `name` are nil when the frame is not a settled Pokémon screen; `flags` say why.
    public func read(_ img: RGBAImage, frame: String? = nil, time: Double? = nil, wantHp: Bool = true, wantBars: Bool = true) -> FrameReading {
        var out = FrameReading(frame: frame, time: time)
        let rect = contentRect(img)
        guard rect.w > 0, rect.h > 0 else { out.flags.append("no-cp-text"); return out }
        let cpText = findCpText(img, rect)
        let hpBar = findHpBar(img, rect)
        let regions = regionsFrom(rect, cpText, hpBar, cpPadding: cpPadding, cpIncludesPrefix: cpIncludesPrefix)
        guard let bar = hpBar, let nameRegion = regions.name, let hpRegion = regions.hp, let panel = regions.panelSearch else {
            out.flags.append(cpText == nil ? "no-cp-text" : "no-hp-bar")
            return out
        }
        // Mid-swipe: the CP text is there but off-centre (the card is sliding).
        if let c = cpText, !c.centred { out.flags.append("mid-swipe"); return out }
        // A tall model (Zapdos, Moltres) can cover the CP completely (fault 3). The name, HP and
        // bars are still on screen, and the grouper can work the CP out from them, so read on when
        // the HP bar sits where a settled card puts it (its left edge does not move when the
        // Pokémon is damaged).
        if cpText == nil {
            out.flags.append("no-cp-text")
            let left = Double(bar.x0 - rect.x) / Double(rect.w)
            if left < Tuning.settledBarLeft.lowerBound || left > Tuning.settledBarLeft.upperBound { return out }
        }
        if cpText != nil {
            let r = text.read(crop(img, regions.cp), kind: .cp)
            out.cpText = r.text
            out.cp = cpReadHasValidShape(r.text) ? parseCp(r.text) : nil
            if let cp = out.cp { out.cpReads = [cp] } else { out.cpReads = [] }
        }

        // Tesseract reported confidence 0 for a line with anything it could not place, so a read
        // whose whole text is exactly a species name (four letters or more) is taken whatever the
        // confidence; Vision gives a real confidence, but the rule stays: a near miss, or a match
        // that dropped a word, still needs confidence.
        func readName(_ region: Rect) -> NameRead {
            let nameCrop = crop(img, region)
            let r = text.read(nameCrop, kind: .name)
            let letterWords = r.words.filter { hasLetterRun($0.text) }
            let confidence = letterWords.isEmpty ? 0 : letterWords.reduce(0) { $0 + $1.confidence } / Double(letterWords.count)
            let found = matchName(r.text, names)
            var ok = false
            if let f = found { ok = confidence >= Tuning.weakNameConfidence || (f.distance == 0 && f.whole && f.text.count >= 4) }
            return NameRead(text: r.text, confidence: confidence, match: ok ? found : nil, sharpness: laplacianVariance(nameCrop))
        }
        var nameRead = readName(nameRegion)
        // Fault 2: a Lucky Pokémon has a "LUCKY POKÉMON" line between its name and the HP bar, so
        // the name sits higher: when nothing matched, look one line up. That line is the model's
        // feet on any other screen, so only a confident, exact, whole read of four letters or more
        // counts there.
        if nameRead.match == nil {
            var up = nameRegion
            up.y -= Tuning.luckyLineOffset * Double(rect.h)
            let lucky = readName(up)
            if let m = lucky.match, lucky.confidence >= Tuning.luckyNameConfidence, m.distance == 0, m.whole, m.text.count >= 4 { nameRead = lucky }
        }
        out.sharpness = nameRead.sharpness
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
                out.baseName = nameAndFormNidoran(id)
            }
            // A name taken without confidence (Nidoran aside: its symbol is what could not be
            // placed). The grouper uses such a frame only when a neighbouring frame agrees.
            out.nameWeak = nameRead.confidence < Tuning.weakNameConfidence && !m.symbol
            if m.attached { out.nameAttached = true }
        } else if !nameRead.text.isEmpty { out.flags.append("name-unmatched") }

        if out.cp == nil && cpText != nil { out.flags.append("cp-unread") }
        // A frame without an identifiable Pokémon is not a reading (the grouper asks for a name),
        // but it keeps its CP so a Pokémon on screen under a nickname can be listed.
        if out.name == nil { return out }

        if wantHp {
            let r = text.read(crop(img, hpRegion), kind: .hp)
            out.hpText = r.text
            out.hp = hpReadHasValidShape(r.text) ? parseHp(r.text) : nil
            if out.hp == nil { out.flags.append("hp-unread") }
        }
        if wantBars {
            if let result = readBars(img, rect, panel).result {
                out.ivs = result.ivs; out.ivConfidence = result.confidence; out.fills = result.fills
            } else { out.flags.append("no-bars") }
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

private func nameAndFormNidoran(_ id: String) -> String { id == "nidoran_female" ? "Nidoran♀" : "Nidoran♂" }
