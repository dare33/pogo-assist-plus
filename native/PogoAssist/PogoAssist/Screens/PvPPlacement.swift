import PogoBox

/// Which Pokémon a PvP slot may place under a mode, for the ranking the screen shows. Under Available a pick is placed only when the option the screen shows for its copy
/// (the Classic pick, or the experimental member under the Pogo Assist ranking: `LeaguePanel.shownIndex`) is the copy itself, so the check and the candidate list agree.
enum PvPPlacement {
    static func placeable(league: String, mode: SquadMode, pogoAssist: Bool, ctx: HubContext) -> (String, String) -> Bool {
        guard mode == .available else { return { _, _ in true } }
        return { id, _ in
            guard let r = ctx.advice.leagues[id]?[league] else { return false }
            return r.options[LeaguePanel.shownIndex(r, pogoAssist: pogoAssist)].isSelf
        }
    }
}
