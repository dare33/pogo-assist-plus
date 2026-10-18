import Foundation
import PogoReader

extension BoxMerge {
    /// Questions that can be answered together: the same kind, and the same effect of the "yes" answer.
    public struct QuestionGroup: Equatable {
        public var kind: Unsure.Kind
        /// What the primary answer does (`BoxMerge.effect` for that candidate), shared by every member. nil when the members have no single primary candidate.
        public var effect: Effect?
        /// `Unsure.scanned` of each member, in plan order.
        public var members: [Int]
        /// For each member with exactly one unambiguous "yes" answer, that answer: `.existing(id)` of its only candidate ("It is this one"), or for a Mega pair `.existing(base entry id)`
        /// ("Join them"). A member with several candidates (or a ranked list), an extra twin (its answers are "add a second one" or "leave it out", not "it is the saved one"), or a
        /// candidate missing from `saved` has no primary answer, so is never in a group with others.
        public var primary: [Int: Resolution]
        /// Two or more members, every one with a primary answer, and giving all the primaries together is valid: no saved entry is chosen by two members that would each write to it
        /// (`apply` refuses that with `chosenTwice`). Only members of this group are compared; an answer given in another group is not.
        public var canBulk: Bool
    }

    /// The plan's unsure questions grouped for bulk answers. Pure: nothing in the plan, `apply` or any result changes.
    /// Every unsure item is in exactly one group; groups follow the order of their first member in `plan.unsure`. Members that have a primary answer are grouped by
    /// (kind, effect); a member without one is a group of its own with `effect` nil and `canBulk` false.
    public static func questionGroups(_ plan: Plan, saved: [BoxEntry], gameMaster gm: GameMaster?) -> [QuestionGroup] {
        let byId = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var groups = [QuestionGroup]()
        for u in plan.unsure {
            let yes: String? = u.kind == .extraTwin ? nil : (u.kind == .megaPair ? (u.candidates.count == 2 ? u.candidates.first : nil) : (u.candidates.count == 1 ? u.candidates.first : nil))
            guard let id = yes, let e = byId[id] else {
                groups.append(QuestionGroup(kind: u.kind, effect: nil, members: [u.scanned], primary: [:], canBulk: false))
                continue
            }
            let fx = effect(plan, u, candidate: e, gameMaster: gm)
            if let g = groups.firstIndex(where: { $0.kind == u.kind && $0.effect == fx }) {
                groups[g].members.append(u.scanned); groups[g].primary[u.scanned] = .existing(id)
            } else {
                groups.append(QuestionGroup(kind: u.kind, effect: fx, members: [u.scanned], primary: [u.scanned: .existing(id)], canBulk: false))
            }
        }
        let byScanned = Dictionary(plan.unsure.map { ($0.scanned, $0) }, uniquingKeysWith: { a, _ in a })
        for g in groups.indices where groups[g].members.count >= 2 && groups[g].primary.count == groups[g].members.count {
            var chosen = Set<String>(), ok = true
            for m in groups[g].members {
                guard let u = byScanned[m], case .existing(let id)? = groups[g].primary[m] else { ok = false; break }
                if writes(u, id, plan), !chosen.insert(id).inserted { ok = false; break }
            }
            groups[g].canBulk = ok
        }
        return groups
    }
}
