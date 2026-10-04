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
            return .init(id: id, line: candidateLine(e.row, among: row), alreadySeen: alreadySeen(id, plan), effect: fx, effectText: effectSentence(fx))
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
                    note: "Same Pokémon keeps the normal entry exactly as saved (marked Mega when scanned if the scan read the Mega form) and removes the Mega entry with whatever was saved for it. Different ones changes nothing.",
                    search: search)
            }
            return ReviewQuestion(scanned: u.scanned, shape: .megaPair, kind: .copies, title: "This Pokémon is saved twice, as a Mega and not. Are they the same Pokémon?", short: short,
                answers: [.init(label: "Same Pokémon", icon: nil, resolution: u.candidates.first.map { .existing($0) } ?? .leaveOut, style: .tint), .init(label: "Different ones", icon: nil, resolution: .leaveOut, style: .tint)],
                note: "Same Pokémon removes the Mega entry. Different ones changes nothing.", search: search)

        case .extraTwin:
            let n = plan.scanned.filter { sameRead($0, row) }.count
            let k = saved.values.filter { sameRead($0.row, row) }.count
            let exact = k >= 1 && n == k + 1
            var note = "Yes adds one more to the box. No leaves it out and changes nothing."
            if !cands.isEmpty { note += " A saved Pokémon with the same CP and HP but other IVs is listed above: it may be this one, read with the wrong IVs." }
            return ReviewQuestion(scanned: u.scanned, shape: .extraTwin, kind: .copies,
                title: exact ? "The scan saw \(word(n)) identical \(row.name). Your box has \(word(k)). Do you have \(word(n))?" : "The scan saw identical \(row.name) in a row, and the box has one like it. Add a second one?",
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
        let same = Set(cands.map { effectKey($0.effect) }).count <= 1
        let note = [explanation(u, row: row, saved: saved), same ? cands.first?.effectText : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return ReviewQuestion(scanned: u.scanned, shape: .several, kind: kind, title: title, short: short, readLine: readLine(row),
            answers: [addNew, leave], candidates: cands, rankedCount: ranked, note: note.isEmpty ? nil : note, search: search)
    }

    /// The note under a card whose candidates are listed one by one: only when they do not all do the same.
    static func perCandidateNotes(_ q: ReviewQuestion) -> Bool { Set(q.candidates.map { effectKey($0.effect) }).count > 1 }
    private static func effectKey(_ fx: BoxMerge.Effect) -> String { "\(fx)" }

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
            case .joinsMegaPair: return "Same Pokémon: the Mega entry is removed"
            case .seenOnly: return "Saved one: marked as seen"
            case .seenAsMega: return "Saved one: marked as seen and as Mega"
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
        case .seenAsMega: return "Choosing this marks it as seen and as Mega evolved when scanned. The Mega values are not copied."
        case .replacesValues: return "Choosing this updates the saved Pokémon with the values read in the scan."
        case .replacesIVs: return "The saved IVs were not an exact read, so choosing this replaces them with the IVs read now."
        case .joinsMegaPair: return "Joining keeps this entry exactly as saved (values and hand corrections unchanged), marks it Mega when scanned if the scan read the Mega form, and removes the other entry with whatever was saved for it."
        case .keepsIVsAndFlags: return "The scan read other IVs for the same CP and HP. IVs never change, so one read is wrong: choosing this keeps the saved IVs and marks it to check."
        }
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

    static func alreadySeen(_ id: String, _ plan: BoxMerge.Plan) -> Bool {
        plan.same.contains { $0.savedId == id } || plan.updated.contains { $0.savedId == id }
    }

    private static func sameRead(_ a: ScanRow, _ b: ScanRow) -> Bool { a.speciesId == b.speciesId && a.cp == b.cp && a.hp == b.hp && a.ivs == b.ivs }

    private static func word(_ n: Int) -> String {
        let w = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        return n >= 0 && n < w.count ? w[n] : "\(n)"
    }
}
