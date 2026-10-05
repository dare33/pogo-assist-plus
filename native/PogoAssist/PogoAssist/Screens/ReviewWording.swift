import SwiftUI
import PogoBox
import PogoReader

/// The words and answers of one open question on the Review screen (design handoff v2 section 1b), worked out from the merge's own
/// `Unsure` and `BoxMerge.effect`. Every note says what `BoxMerge.apply` will do, because it is written from the same `effect`.
struct ReviewQuestion {
    enum Shape { case single, several, extraTwin, megaPair }
    struct Answer: Identifiable {
        var label: String
        var icon: String?
        var resolution: BoxMerge.Resolution
        var style: PillStyle
        var id: String { label }
    }
    /// A saved Pokémon offered with a "This one" button.
    struct Candidate: Identifiable {
        var id: String
        var line: String
        /// "Already seen in this scan": choosing it means this row is a second read of that Pokémon.
        var alreadySeen: Bool
        var effect: BoxMerge.Effect
        var effectText: String
    }
    var scanned: Int
    var shape: Shape
    var kind: QuestionKind
    var title: String
    var short: String
    var compare: QuestionCompare?
    /// The Mega pair's own headings (NORMAL / MEGA): the shared compare pair is fixed to READ NOW / IN YOUR BOX.
    var pair: [(heading: String, side: CompareSide)] = []
    /// What the scan read, for a card that has no compare pair.
    var readLine: String?
    var answers: [Answer]
    var candidates: [Candidate] = []
    /// `Plan.rankedCounts`: the first this many candidates are the ranked best matches; with 0 the whole list is shown.
    var rankedCount = 0
    var note: String?
    var search: String?
}

enum ReviewWording {
    // MARK: the card for one question

    static func question(_ u: BoxMerge.Unsure, plan: BoxMerge.Plan, saved: [String: BoxEntry], gm: GameMaster?) -> ReviewQuestion {
        let row = plan.scanned[u.scanned]
        let search = GameSearch.text([GameSearch.part(for: u, row: row, saved: saved)])
        let short = "\(row.title), CP \(row.cp)"
        let ids = u.kind == .extraTwin ? Array(u.candidates.dropFirst()) : u.candidates
        let cands: [ReviewQuestion.Candidate] = ids.compactMap { id in
            guard let e = saved[id] else { return nil }
            let fx = BoxMerge.effect(plan, u, candidate: e, gameMaster: gm)
            return .init(id: id, line: candidateLine(e.row, among: row), alreadySeen: alreadySeen(id, plan), effect: fx, effectText: effectSentence(fx) + megaFormSentence(plan, u, e, gm))
        }
        let ranked = plan.rankedCounts[u.scanned] ?? 0

        switch u.kind {
        case .megaPair:
            let entries = u.candidates.compactMap { saved[$0] }
            if entries.count == 2 {
                return ReviewQuestion(scanned: u.scanned, shape: .megaPair, kind: .copies,
                    title: "Your \(entries[0].row.name) is saved twice, as a Mega and not. Are they the same Pokémon?", short: "\(entries[0].row.name), saved twice",
                    pair: [("NORMAL", side(entries[0].row, plain: true)), ("MEGA", side(entries[1].row, plain: true))],
                    answers: [.init(label: "Same Pokémon", icon: nil, resolution: .existing(entries[0].id), style: .tint), .init(label: "Different ones", icon: nil, resolution: .leaveOut, style: .tint)],
                    note: "Same Pokémon: the box keeps one entry with both forms. The normal entry keeps its values and hand corrections, the Mega entry's values become its Mega form, and the separate Mega entry is removed. If the normal entry already had a Mega form, the Mega values kept are the most recently seen ones. Different ones changes nothing.",
                    search: search)
            }
            return ReviewQuestion(scanned: u.scanned, shape: .megaPair, kind: .copies, title: "This Pokémon is saved twice, as a Mega and not. Are they the same Pokémon?", short: short,
                answers: [.init(label: "Same Pokémon", icon: nil, resolution: u.candidates.first.map { .existing($0) } ?? .leaveOut, style: .tint), .init(label: "Different ones", icon: nil, resolution: .leaveOut, style: .tint)],
                note: "Same Pokémon: the box keeps one entry with both forms. The Mega entry's values become the normal entry's Mega form and the separate Mega entry is removed. If the normal entry already had a Mega form, the Mega values kept are the most recently seen ones. Different ones changes nothing.", search: search)

        case .extraTwin:
            let n = plan.scanned.filter { sameRead($0, row) }.count
            let k = saved.values.filter { sameRead($0.row, row) }.count
            let exact = k >= 1 && n == k + 1
            var note = "Yes adds one more to the box. No leaves it out and changes nothing."
            if !cands.isEmpty { note += " A saved Pokémon with the same CP and HP but other IVs is listed above: it may be this one, read with the wrong IVs." }
            return ReviewQuestion(scanned: u.scanned, shape: .extraTwin, kind: .copies,
                title: exact ? "The scan saw \(word(n)) identical \(row.name). Your box has \(word(k)). Do you have \(word(n))?" : "The scan saw \(word(n)) identical \(row.name). Your box has \(k == 0 ? "none" : word(k)). Add one more?",
                short: short,
                compare: exact ? QuestionCompare(readNow: side(row, name: "\(row.name) ×\(n)"), inBox: side(saved[u.candidates.first ?? ""]?.row ?? row, name: "\(row.name) ×\(k)")) : nil,
                answers: [.init(label: "Yes, add one", icon: "checkmark", resolution: .new, style: .filled), .init(label: "No, don't include", icon: "minus", resolution: .leaveOut, style: .tint)],
                candidates: cands, note: note, search: search)

        default: break
        }

        let addNew = ReviewQuestion.Answer(label: "Add new", icon: "plus", resolution: .new, style: .tint)
        let leave = ReviewQuestion.Answer(label: "Don't include", icon: "minus", resolution: .leaveOut, style: .tint)
        let kind: QuestionKind = (u.kind == .evolved || u.kind == .poweredUp || u.kind == .megaToBase) ? .change : .match

        if cands.count == 1, let e = saved[cands[0].id] {
            // One saved candidate: the compare pair and one "yes".
            let fx = cands[0].effect
            let compare = QuestionCompare(readNow: side(row), inBox: side(e.row))
            let yes: String, title: String, note: String
            switch u.kind {
            case .evolved:
                yes = "Yes, it evolved"
                title = "Is this \(row.title) your \(e.row.title), evolved?"
                note = fx == .replacesValues ? "Yes updates the saved \(e.row.title) to \(row.title). If the game still shows \(e.row.title) \(cpText(e.row.cp)), it is a different one." : ivsExplanation(row, e) + " " + cands[0].effectText
            case .poweredUp:
                yes = "Yes, powered up"
                title = "Is this your \(e.row.title), powered up?"
                note = fx == .replacesValues ? "Yes updates the saved \(e.row.title) with the values read in the scan. If the game still shows \(cpText(e.row.cp)), it is a different one." : ivsExplanation(row, e) + " " + cands[0].effectText
            case .megaToBase:
                yes = "Yes, same Pokémon"
                title = "Is this your \(e.row.title), scanned now in its normal form?"
                note = explanation(u, row: row, saved: saved) + " " + cands[0].effectText
            default:
                yes = "It's this one"
                title = "Is this the \(e.row.title) in your box?"
                // The design's note, for the case it describes: other IVs read at the same CP and HP.
                note = fx == .keepsIVsAndFlags ? "IVs never change, so one read is wrong. \"It's this one\" keeps the saved IVs and marks it to check."
                    : (u.kind == .ambiguous && fx == .replacesIVs ? cands[0].effectText : explanation(u, row: row, saved: saved) + " " + cands[0].effectText)
            }
            return ReviewQuestion(scanned: u.scanned, shape: .single, kind: kind, title: title, short: short, compare: compare,
                answers: [.init(label: yes, icon: "checkmark", resolution: .existing(e.id), style: .filled), addNew, leave], candidates: cands, rankedCount: ranked, note: note, search: search)
        }

        // Several saved candidates (or a ranked list): "This one" for each, and Add new / Don't include.
        let n = ids.count
        let title: String
        if u.kind == .partialRead {
            title = "\(row.title), CP \(row.cp) read\(row.hp.map { ", HP \($0)" } ?? ""). Which saved one is it?"
        } else if n == 0 {
            title = "Is this \(row.title) new?"
        } else {
            title = "\(n) saved Pokémon could be this \(row.title)."
        }
        // One sentence for the cards when every candidate shown does the same; otherwise each candidate says its own.
        let same = Set(cands.map(\.effectText)).count <= 1
        let note = [explanation(u, row: row, saved: saved), same ? cands.first?.effectText : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return ReviewQuestion(scanned: u.scanned, shape: .several, kind: kind, title: title, short: short, readLine: readLine(row),
            answers: [addNew, leave], candidates: cands, rankedCount: ranked, note: note.isEmpty ? nil : note, search: search)
    }

    /// The note under a card whose candidates are listed one by one: only when they do not all do the same.
    static func perCandidateNotes(_ q: ReviewQuestion) -> Bool { Set(q.candidates.map(\.effectText)).count > 1 }

    // MARK: the answered row

    /// What the collapsed row says after this answer.
    static func answeredText(_ q: ReviewQuestion, _ r: BoxMerge.Resolution, plan: BoxMerge.Plan, saved: [String: BoxEntry], gm: GameMaster?) -> String {
        let u = plan.unsure.first { $0.scanned == q.scanned }
        let row = plan.scanned[q.scanned]
        switch r {
        case .leaveOut: return q.shape == .megaPair ? "Different ones: both kept" : "Not included"
        case .new: return q.shape == .extraTwin ? "Second one added" : "Added as new"
        case .existing(let id):
            guard let u, let e = saved[id] else { return "Saved one" }
            let fx = BoxMerge.effect(plan, u, candidate: e, gameMaster: gm)
            switch fx {
            case .joinsMegaPair:
                // The design's answered state: the two forms side by side.
                guard u.candidates.count == 2, let mega = saved[u.candidates[1]] else { return "Same Pokémon: joined into one entry" }
                return "Same Pokémon · Normal · \(cpText(e.row.cp)) · Mega · \(cpText(mega.row.cp))"
            case .seenOnly: return "Saved one: marked as seen"
            case .seenAsMega: return GameSearch.noLevelFits(row.flags) || row.cp <= 0 ? "Saved one: marked as seen and as Mega" : "Saved one: marked as seen and as Mega, Mega values kept"
            case .replacesIVs: return "Saved one: IVs replaced with those read now"
            case .keepsIVsAndFlags: return "Saved one: saved IVs kept, marked to check"
            case .replacesValues:
                switch u.kind {
                case .evolved: return "Evolved: saved \(e.row.title) becomes \(row.title)"
                case .poweredUp: return "Powered up: \(cpText(e.row.cp)) to \(cpText(row.cp))"
                default: return "Saved one: updated with the values read"
                }
            }
        }
    }

    // MARK: sentences

    /// What "It's this one" will do, for one candidate: the same `BoxMerge.effect` that `apply` follows, so the card cannot disagree with the result.
    static func effectSentence(_ fx: BoxMerge.Effect) -> String {
        switch fx {
        case .seenOnly: return "Choosing this only marks it as seen. Nothing is changed."
        case .seenAsMega: return "Choosing this marks it as seen and as Mega evolved when scanned. If its CP was read and fits a level, the Mega values read now are kept as its Mega form. Its own saved values do not change."
        case .replacesValues: return "Choosing this updates the saved Pokémon with the values read in the scan."
        case .replacesIVs: return "The saved IVs were not an exact read, so choosing this replaces them with the IVs read now."
        case .joinsMegaPair: return "Joining keeps this entry with its values and hand corrections, keeps the other entry's values as its Mega form, and removes the separate Mega entry. If this entry already had a Mega form, the Mega values kept are the most recently seen ones. It is marked Mega when scanned if the scan read the Mega form."
        case .keepsIVsAndFlags: return "The scan read other IVs for the same CP and HP. IVs never change, so one read is wrong: choosing this keeps the saved IVs and marks it to check."
        }
    }

    /// For a megaToBase candidate, when "It's this one" keeps the Mega values the entry was saved with: said after the effect sentence. Empty otherwise.
    static func megaFormSentence(_ plan: BoxMerge.Plan, _ u: BoxMerge.Unsure, _ e: BoxEntry, _ gm: GameMaster?) -> String {
        guard let gm, BoxMerge.keepsSavedMegaAsMegaForm(plan, u, candidate: e, gameMaster: gm) else { return "" }
        return " The Mega values it was saved with become its Mega form."
    }

    /// "Same IVs" is only true when the saved entry's current IVs equal the read ones; a match through a hand correction's old IVs says so.
    private static func ivsExplanation(_ row: ScanRow, _ e: BoxEntry) -> String {
        if let ivs = row.ivs, e.row.ivs != ivs, e.corrections.ivs?.was == ivs { return "These IVs match this saved one's IVs from before you corrected them." }
        return "Same IVs as this saved one."
    }

    /// Why the merge asks, in words (the engine's `Unsure.Kind` documents each case).
    static func explanation(_ u: BoxMerge.Unsure, row: ScanRow, saved: [String: BoxEntry]) -> String {
        var ivsPhrase = "Same IVs as this saved one."
        if u.candidates.count == 1, let e = saved[u.candidates[0]] { ivsPhrase = ivsExplanation(row, e) }
        switch u.kind {
        case .partialRead: return "Only part of the CP was read, so this may be a Pokémon already in your box."
        case .misreadSaved: return "A Pokémon in your box was read badly earlier (no IVs). This may be the same Pokémon read properly."
        case .extraTwin: return ""
        case .poweredUp: return "\(ivsPhrase) It may be that Pokémon powered up, or a different one with the same IVs."
        case .evolved: return "\(ivsPhrase) It may be that Pokémon evolved, or a different one with the same IVs."
        case .megaPair: return ""
        case .megaToBase: return "This is the normal form; the saved one was scanned in its Mega form. \(ivsPhrase) It may be that same Pokémon, or a different one with the same IVs."
        case .ambiguous:
            if u.candidates.count == 1, let e = saved[u.candidates[0]], let ivs = row.ivs, e.row.cp < row.cp {
                if e.row.ivs == ivs || e.corrections.ivs?.was == ivs { return "\(ivsPhrase) It may be that Pokémon powered up, or a different one with the same IVs." }
            }
            return u.candidates.count == 1 ? "It could be this Pokémon already in your box." : "It could be more than one Pokémon already in your box."
        }
    }

    /// The note under a part-read question or group (Standard's group panel and Guide me's one-question screen say the same sentence). `members` are the rows read and the
    /// saved rows they were matched to. Only a CP whose digits are in the saved CP's was "only partly read"; any other (or none) was not read properly.
    static func partReadNote(effect: BoxMerge.Effect?, members: [(read: ScanRow, saved: ScanRow)], showAddNew: Bool) -> String {
        let plural = members.count != 1
        guard effect == .seenOnly else { return effect.map(effectSentence) ?? "" }
        let fragments = members.filter { isFragment($0.read.cp, of: $0.saved.cp) }.count
        let allZero = members.allSatisfy { $0.read.cp <= 0 }
        let what: String
        if fragments == members.count { what = "Only part of \(plural ? "each CP was" : "the CP was") read." }
        else if fragments == 0 { what = plural ? (allZero ? "The CPs were not read." : "The CPs were not read properly.") : (allZero ? "The CP was not read." : "The CP was not read properly.") }
        else { what = "Some CPs were only partly read and the others not read properly." }
        var s = "\(what) Picking the saved one just marks it as seen."
        if showAddNew { s += " Add new saves the row as read, with its part-read CP." }
        return s
    }

    // MARK: trouble stretches

    /// The words of one trouble stretch panel (`TroubleStretches`): what happened, with the engine's real numbers, and how to read the cards again.
    struct StretchText: Equatable {
        var title: String
        var what: String
        var resume: String
    }

    /// The command that covers the cards from where the person resumes (`cardsToEndFromResume`: the first affected card, or the unread card that comes right before it) to the end: the smallest
    /// size of the set that covers them. nil when THIS scan was not paged by a command (`pagedByCommand`: `review.paging`; false when that is unknown, as in a state saved before it was kept),
    /// no command set was made on this phone, or the cards outnumber the largest command. A person who changed the setting since the scan does not change how that scan was paged.
    static func resumeSize(_ t: TroubleStretch, pagedByCommand: Bool, commandSetMade: Bool) -> Int? {
        pagedByCommand && commandSetMade ? VoiceCommandFile.setSize(covering: t.cardsToEndFromResume) : nil
    }

    static func stretch(_ t: TroubleStretch, commandSize: Int?) -> StretchText {
        let n = t.count.formatted(), first = t.firstCard, last = t.lastCard
        let clean = t.cleanRowsInside
        let between = clean > 0 ? " \(ReviewFormat.count(clean, "Pokémon", "Pokémon")) in between had \(clean == 1 ? "its" : "their") \(t.kind == .cpHidden ? "CP" : "IV bars") read." : ""
        let title: String, what: String
        switch t.kind {
        case .cpHidden:
            // With clean rows inside, the cards counted are not all the cards from the first to the last, so the title does not say "in a row".
            title = clean > 0 ? "The CP was covered for \(n) cards, on and off" : "The CP was covered for \(n) in a row"
            var s = "Something probably covered the top of the screen, such as a banner or an alarm, from \(first.name) (CP \(first.cp), worked out) to \(last.name)."
            if t.unreadCards > 0 { s += " \(t.unreadCards.formatted()) of them are not in this scan's list: their CP could not be read or worked out." }
            what = s + between
        case .barsUnread:
            title = clean > 0 ? "The IV bars were not read for \(n) cards, on and off" : "The IV bars were not read for \(n) in a row"
            what = "The appraisal may have been closed or covered from \(first.name) to \(last.name), so the IV bars were not read." + between
        }
        // Where to open: the first affected card, unless the scan holds unread cards between the one before and it: the card right after the one before is then one the scan could not read.
        let target: String, place: String
        if t.leadingUnread > 0 {
            if let b = t.cardBefore { target = "the Pokémon that comes right after \(b.name) CP \(b.cp) (the scan could not read it)"; place = "" }
            else { target = "the first Pokémon in this scan (the scan could not read it)"; place = "" }
        } else {
            target = first.name
            place = " (\(t.cardBefore.map { "it comes right after \($0.name) CP \($0.cp)" } ?? "it is the first one in this scan"))"
        }
        let then = commandSize.map { "choose Add and update, then say \"Wake up\" and \"Pogo scan \($0)\"." } ?? "then scan again from there (Add and update)."
        return StretchText(title: title, what: what, resume: "To read them again: in Pokémon GO open \(target)\(place) with the appraisal showing, \(then)")
    }

    /// The first card of a stretch as a game search: its HP when its CP is not to be trusted (always for a hidden CP, and for a CP that was worked out or fits no level).
    static func stretchSearch(_ t: TroubleStretch, scan: ScanResult) -> String? {
        // With unread cards ahead of the first affected row, the place to open is one the scan could not read: there is nothing to search for.
        guard t.leadingUnread == 0, scan.rows.indices.contains(t.firstRow) else { return nil }
        let r = scan.rows[t.firstRow]
        let worked = t.kind == .cpHidden || r.flags.contains { $0 == "cp-computed" || $0.hasPrefix("cp-computed:") } || GameSearch.untrusted(r)
        return GameSearch.text([GameSearch.part(name: r.name, cp: r.cp, hp: r.hp, noLevelFits: worked)])
    }

    // MARK: pieces

    static func cpText(_ cp: Int) -> String { cp > 0 ? "CP \(cp)" : "CP not known" }
    static func hpText(_ hp: Int?) -> String { hp.map { "HP \($0)" } ?? "HP not read" }
    static func ivsText(_ ivs: IVs?) -> String { ivs.map { "IVs \($0.atk)/\($0.def)/\($0.hp)" } ?? "IVs not read" }

    static func readLine(_ r: ScanRow) -> String {
        var parts = ["Read in the scan: \(r.title)", cpText(r.cp), hpText(r.hp), ivsText(r.ivs)]
        if GameSearch.untrusted(r) { parts.append("no level fits") }
        return parts.joined(separator: ", ")
    }

    static func side(_ r: ScanRow, name: String? = nil, plain: Bool = false) -> CompareSide {
        CompareSide(name: name ?? r.title, line: plain ? cpText(r.cp) : "\(cpText(r.cp)) · \(hpText(r.hp))", ivs: ivsText(r.ivs))
    }

    /// "CP 1982 · HP 142 · IVs 13/12/15", with the species first when it is not the read row's own.
    static func candidateLine(_ c: ScanRow, among row: ScanRow) -> String {
        let core = "\(cpText(c.cp)) · \(hpText(c.hp)) · \(ivsText(c.ivs))"
        return c.title == row.title ? core : "\(c.title) · \(core)"
    }

    /// The digits of a CP read in part are some of the digits of the saved CP, in order (182 in 1982), which is what makes it "only partly read".
    static func isFragment(_ read: Int, of saved: Int) -> Bool {
        guard read > 0, read != saved else { return false }
        var i = Array(String(read)).makeIterator(), next = i.next()
        for c in String(saved) where c == next { next = i.next() }
        return next == nil
    }

    static func alreadySeen(_ id: String, _ plan: BoxMerge.Plan) -> Bool {
        plan.same.contains { $0.savedId == id } || plan.updated.contains { $0.savedId == id }
    }

    private static func sameRead(_ a: ScanRow, _ b: ScanRow) -> Bool { a.speciesId == b.speciesId && a.cp == b.cp && a.hp == b.hp && a.ivs == b.ivs }

    private static func word(_ n: Int) -> String {
        let w = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        return n >= 0 && n < w.count ? w[n] : "\(n)"
    }
}
