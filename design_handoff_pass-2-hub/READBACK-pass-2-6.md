# Read-back: design pass 2-6 (phone run 6 asks A–E, plus readability)

Written by the manager on 7 Nov 2026 from the design panel Greg confirmed the same day (four rounds of comments on the
private panel page; its HTML is kept as `design-files/pass-2-6-panel.html`). Per `docs/design-process.md` section 4:
each statement is checkable on a device, each rule is checked against the code at `design/pass-2-5` 146e796, and every
gap the panel did not draw is a question with a recommended answer. Nothing is built until Greg answers section 3.

## 1. What each screen does (checkable on a device)

Shared by the five squad screens (Raids, Max, Gym, Rocket, PvP), from the pass 2-5 build

1.1 Over the slots: one row with the tabs on the left and, on Raids, the style switch on the right: Available | Best,
    and Current as a third segment on the right once the squad has a Current. Available and Best never move. No SQUAD
    or STYLE caption; VoiceOver still names the controls "Squad" and "Raids style".
1.2 Every segmented switch in the app draws its chosen segment on the accent tint in the accent ink; the other
    segments are plain. (Was: the chosen segment on the surface colour.)
1.3 The title has one (i). It opens the squad explainer: what Current, Available and Best are, then how the squad is
    suggested and the style, then one line per status chip sign (1.20). The tabs' own (i) is gone.
1.4 Under the tabs: the status chip ("Not ready: 2 to get") on the left and, on Available and Best, the pill on the
    right: "Set this squad" (solid accent) when the tab's squad is not the Current, "✓ Squad set" (accent tint, accent
    outline, same size and place) when it is. The Current tab has no pill.
1.5 "Set this squad" makes the tab's squad as drawn the squad's Current and sets it: the Current segment appears (if it
    was not there), the pill turns to "✓ Squad set", the player stays on the tab. A different Current is replaced with
    no question; it goes to the history (1.12) and a toast "Current squad replaced" offers Undo for five seconds.
1.6 Tapping "✓ Squad set" unsets at once: the Current goes to the history, the Current segment disappears, the pill
    reads "Set this squad", a toast "Squad unset" offers Undo. "Set" and "has a Current" are one thing.
1.7 The strength line reads "Squad strength 41% of best · 87% after upgrades" in one tone with the figures bold, the
    after part only when the bar draws its faint part; the unedited Best tab reads "Squad strength 100%"; a squad at or
    over the reference reads "Squad strength 100%". No "the best squad", no "Matches the best squad", no dot.
1.8 Every change on Available or Best is kept as it is made, per account, per squad and per tab (on Raids per style
    too), and survives leaving the screen and the app. A raid or Max squad's kept edits go when its event ends.
1.9 Under the slots of an Available or Best tab that differs from its suggestion: a "Reset to suggestion" link. It
    drops the kept edits at once, no question. No Save to Current, no Reset otherwise, no "Saved to Current".
1.10 No mark on a tab that holds edits.
1.11 After a re-scan a kept edit follows the box as Current does: a pick whose copy left the box is emptied, that slot
    refills with the next best unused, and the refill is kept.
1.12 The Current tab shows "Delete current squad" (asks: "Delete current squad?" with Delete and Cancel, no message
    line) and under it EARLIER CURRENT SQUADS: up to ten rows, newest first. Each row: when it was current (Today 10:16
    / Yesterday 18:40 / 5 Nov 09:12), one small disc per slot in the role colour with the Pokémon's initial (a dashed
    hollow disc for a Pokémon no longer in the box; a grey disc for an empty slot), the strength figure it had when it
    was current, and an accent "Set squad" pill. Set squad makes it the Current with no question, shows the replaced
    toast with Undo, and the replaced squad goes to the top of the list. A row is one VoiceOver element reading the
    date, each Pokémon ("Zacian, not in your box"), the figure, with Set squad as its action.
1.13 Every confirmation dialog in the app shows its bold question and its buttons only, with no message line.
1.14 Shadow Pokémon are named as the box names them, "Gardevoir (Shadow)", everywhere on the squad screens (slots,
    picker rows, strip chips, Best rows). "Mega Gardevoir" stays as the game names it.

Pinned strip (while a slot's picker is open)

1.15 On Raids and Gym (six slots) the strip is two rows of three chips, each a third of the width, all six in view.
     Max, Rocket and PvP (three slots) stay one row of three.
1.16 A chip shows the slot number and the Pokémon's name without a bracketed form ("Zamazenta", "Gardevoir"); a name
     that still does not fit is cut with …; VoiceOver reads the full name. "Empty" stays grey with the word.
1.17 A chip for a Pokémon not in the box (a Best pick) has a hollow number and a dashed edge; VoiceOver adds "not in
     your box".
1.18 At accessibility text sizes the two rows stay and a chip's name wraps to two lines; the list is inset below the
     taller strip.

Pickers

1.19 Under Available and under Best, tapping the Mega role chip in a slot's picker while another slot holds the squad's
     Mega shows "You can only have 1 Mega slot" alone, in a box no taller than the line needs, in place of the rows.
     The chip stays tappable and does not change the slot's role. The Mega slot's own picker, and the Mega chip when no
     slot holds a Mega, list the Mega candidates as today. All is unchanged.
1.20 Status chips in place of the status sentences, each a small pill with a sign, a colour and one word: "✓ Ready"
     (green), "↑ 206k" (orange, the cost; "↑ Upgrade" when the cost is unknown; "↑ No build" when the copy has no build
     for the area), "◎ Get now" (blue) with the Easy / Medium / Hard meter when known, "◌ Not now" (grey) with the month
     when the schedule knows it, "⇄ Slot 5" for a Pokémon in another slot ("⇄ Empty slot" for "moves it here"). Colour
     is never the only sign; VoiceOver reads the full words as today.
1.21 Picker rows show the role word only under All. Gym's DEF / HP / BULK figures, PvP's score and IV line, Rocket's
     "beats n of 3" and "vs …" lines, "Same copy as …", and the tier chip are unchanged.
1.22 Slot cards show the same chips in place of their status line(s) and the bottom status word; the card colour
     stays. Lines that are not a status stay: "Its role: …", "beats 2 of 3", "vs Zekrom", "level not read", "You can
     only have 1 Mega slot" on an empty Mega slot.

Raids

1.23 Best for a raid ranks every species in the game master by the damage estimate against this boss (the figure the
     picker bars use, at level 50, 15/15/15, best moves): the top 12 Heavy hitters, the top 12 Bulky hitters (by
     `PogoRules.raidRole`: a Shadow or Attack at least 1.3 × Defence is Heavy, else Bulky) and the top 12 Megas and
     Primals for the Mega slot. The Best suggestion, its picker rows and the strength reference come from these rows.
1.24 A Best row carries the Raids table's tier chip when the table lists that Pokémon under one of the boss's bring
     types; otherwise none. Rows are in damage order whatever their chip.
1.25 A Best row's status words are as today: a copy in the box (✓ or ↑), a boss on now or an obtain line (◎), else ◌.
     A species the table does not list has no obtain text, so it reads ◎ only when the schedule has it now, else ◌ with
     the month if known.
1.26 The style switch keeps its own Available and Best edits per style; switching back shows them again. Current is one
     per squad whatever the style.
1.27 The raid card fills in the accent exactly when the squad has a Current (the "Squad set" mark is the Current).

Max battles

1.28 As Raids without the style switch: the tabs alone on the left, the pill on the right of the status chip. A Max
     row is tinted and reads SQUAD SET exactly when its squad has a Current. Max Best stays table-driven (logged for
     later).

Gym, Rocket, PvP

1.29 The same tabs, pill, kept edits, history and chips. "Set this squad" there means only "make this the Current";
     there is no card to fill. (Today these three have Save to Current but no Set this squad button.)
1.30 Rocket's grunt list follows the remembered Available or Best; PvP's bar has no after part. Unchanged.

## 2. Rules checked against the code (at 146e796)

CONCEPTS rules that change, with where today's behaviour lives:

2.1 Rule 27.1 (tabs): `SquadTabsRow` (`UI/SquadPieces.swift:772-814`) draws Current | Available | Best with the
    caption and its own (i). Changes: order Available | Best | Current; no caption; the (i) and `SquadExplainer`
    move into the title's info (`Screens/SquadEvents.swift:519-523` and the Gym, Rocket and PvP equivalents).
2.2 Rule 27.2 and 27.3 (drafts, Save to Current, Reset): `SquadWorkspace` and `SquadDrafts`
    (`Screens/SquadKeeper.swift:93-176`, `PogoBox/SquadCurrent.swift:81-154`) hold drafts in memory only; `SquadDraftBar`
    (`SquadPieces.swift:869-911`) draws Save to Current, Reset and "Saved to Current"; `replaceCurrentDialog`
    (`SquadPieces.swift:858-868`) asks first. Changes: the edits are stored in `SquadStore` per account, squad key, tab
    and (Raids) style; `SquadDraftBar` becomes the Reset link alone; the replace dialog and `squad-save-current*`
    identifiers go; the "Saved to Current" note, `justSaved` and the announcement go.
2.3 Rule 27.8 (Set this squad): `SetSquadFooter` (`SquadPieces.swift:690-722`) is drawn only by `EventSquadView`
    (Raids and Max, `SquadEvents.swift:546-553`); on Current it sets the mark, on Available or Best it saves then sets.
    Changes: one toggle pill on all five screens, above the slots beside the status line, hidden on Current; "✓ Squad
    set" reads from "this tab's squad as drawn equals the Current as drawn"; tapping it unsets (1.6).
2.4 Rule 27.4, 27.7 and 27.9 (Current, Delete, old files): `SquadStore.Saved.hasCurrent` and `isSet`
    (`PogoBox/SquadStore.swift:17-38`), `deleteCurrent` (`SquadCurrent.swift:67`). Changes: `isSet` is no longer a
    separate state (a Current is set; the stored flag is kept for old files and read as "has a Current"); Delete and
    unset move the squad to the history. Old files: a squad with the mark alone becomes a Current (manager call,
    accepted 7 Nov).
2.5 New rule (history): nothing today. `SquadStore` gains, per squad key, up to ten entries of {date, slots as kept
    (entry ids and species keys), source tab, edited flag, strength percent at the time}. Pruned with the event as the
    raids and max squads are (`SquadStore.swift`, the per-event drop).
2.6 Rule 32 (strength words): `SquadStrength.line` (`PogoBox/SquadStrength.swift:83-90`) builds "of best", "· the
    best squad", "· Matches the best squad"; `SquadStrengthLine` (`SquadPieces.swift:198-232`) draws the two labels.
    Changes: the words of 1.7; one label; the stacked-at-AX behaviour stays.
2.7 Rule 33 (style): `RaidStyleRow` (`SquadPieces.swift:940-962`) and the style change handler
    (`SquadEvents.swift:522-527`) drop every Raids draft on a switch. Changes: no caption; edits stored per style, not
    dropped.
2.8 Rule 34 (strip): `SquadStripView` (`SquadPieces.swift:1013-1058`) is one sideways-scrolling line; a chip's name is
    `c.name ?? "Empty"` with no form stripping and no owned/unowned sign. Changes: 1.15-1.18. The UI test fold H10
    (Done dragged out from under the strip) assumes the one-line height and must follow the taller strip.
2.9 Rule 10 and the Mega message: the text exists only on the empty Mega slot card (`SquadEvents.swift:438-442`);
    the picker hides other Mega rows under Best only (`SquadEvents.swift:351-353`, `megaHidden`), and under Available
    the Mega chip on any slot lists Mega candidates (`SquadEvents.swift:358`). Changes: 1.19 on both tabs.
2.10 Best for Raids: `HubSquads.bestRaidRows` (`PogoBox/HubSquads+Best.swift:279-300`) reads only the Raids table
    entries under the boss's bring types. The pieces C2 needs exist: `DamageEstimate.computeBest`
    (`PogoBox/DamageEstimate.swift:424-440`) already scans every eligible species in `gm.ordered` at level 50,
    15/15/15 against the boss (plain and Shadow); `PogoRules.raidRole` (`PogoBox/PogoRules.swift:198-203`) gives Heavy
    or Bulky from base stats for any species; `BestRow` (`HubSquads+Best.swift:45-73`) carries name, tier, roles,
    build/copy, availability and status. Changes: a new row source for Raids Best (1.23-1.25) that keeps `BestRow`'s
    shape, so the suggestion (`bestSquad`), the picker, the strength reference (`reference(style:)`,
    `SquadEvents.swift:420-430`) and the status words work unchanged. The table's tier is looked up per species.
2.11 Status words: `BestStatus.text` (`HubSquads+Best.swift:28-35`), the amber note (`SquadPieces.swift:451`), the
    swap line (`SquadPieces.swift:593`), the role word on rows (`PickerRowModel.role`, `SquadPieces.swift:354`), the
    slot card lines and status word (`SlotCardModel`, `SquadPieces.swift:117-136`; `HubSquads.SlotStatus`). Changes:
    1.20-1.22; the `spoken` strings keep the words.
2.12 Obtain difficulty: the table's obtain text ("Medium. T5 raids") is parsed to Easy / Medium / Hard already
    (`HubSquads+Best.swift:249-275`), so the meter has its source.
2.13 Switch accent: `SegmentedSwitch` (`UI/RankingControls.swift:25-110`, selected = `Theme.surface` background) and
    `StackedChoice` (`SquadPieces.swift`), used in eight files (HistoryScansView, HubCollectionListsView, HubPvPView,
    HubRaidsView, LeaguesPanel, DesignGallery, RankingControls, SquadPieces). Changes: selected = `accent.tint`
    background, `accent.ink` text. Cosmetic.
2.14 Confirmation dialogs with a message line, app-wide: `replaceCurrentDialog` (goes), `DeleteCurrentButton`
    (`SquadPieces.swift:930-935`), BoxView:95, SettingsView:143, ScanView:155, ScreenshotImportSheet:64 and :67,
    RootView:246 (Export), ScanDone:117, ReviewView:50, HistoryScansView:115, BoxChrome:69, ReviewResult:87, :91 and
    :98. Changes: each keeps its title and buttons; the `message:` block goes where it only restates the title (the
    implementer lists any whose message carries a fact the title does not, for the manager's call). Alerts that take
    input (Rename account, New account, Stardust) and the plain message alerts are not confirmations and stay.
    Cosmetic.
2.15 Shadow naming: the Raids table names Shadows "Shadow Gardevoir" (`BestRow.name`, `HubSquads+Best.swift:46`) while
    the box names copies "Gardevoir (Shadow)" (`PogoBox/BoxAdvice.swift:473`, `BoxExport.swift:63`). Changes: squad
    screens draw the box form for a Shadow row or slot. Cosmetic (a rename with the same meaning; CONCEPTS word check
    updated).
2.16 Toast: `ToastHost` / `ToastView` (`UI/Toast.swift:30-60`) shows a message with no action. Changes: an Undo
    action, five seconds.

Mismatches found between the confirmed design and today's rules, all resolved by the changes above: none that the
design did not already decide. Two things the panel did not state, settled here as recommendations (3.1, 3.5).

## 3. Gaps the panel does not cover, each with a recommended answer

Answer each with yes, or say what to change. A yes on the whole section is enough.

3.1 The pill on Gym, Rocket and PvP. Today only Raids and Max have Set this squad; the other three reach Current
    through Save to Current, which goes. Recommended: the same pill on all five, meaning "make this the Current"; no
    card fills there.
3.2 When a history row is made. Recommended: when a Current is replaced (Set this squad, Set squad from the history,
    Undo), unset or deleted. Edits on the Current tab make no row. A squad equal to the newest row is not added
    again.
3.3 The history row's strength figure. Recommended: stored when the row is made, from the bar's figure at that moment
    ("—" when it was not yet worked out), never recomputed; so ten rows cost nothing to draw.
3.4 The Undo toast. Recommended: five seconds, one Undo action, announced to VoiceOver; Undo puts the previous
    Current back and removes the row it made.
3.5 "Matches the best squad" for a squad that is not Best but reaches the reference. Recommended: "Squad strength
    100%", the same as the unedited Best; the (i) keeps the sentence that 100% means the squad matches the Best squad.
3.6 Which chips, exactly (1.20). Recommended: as listed. "Same copy as …" stays a muted line. The chip's cost is the
    build's `costShort` (dust, or candy with its icon) as today's arrow badge shows.
3.7 Mega naming. Recommended: "Mega Gardevoir" stays; only Shadow moves to the bracket form.
3.8 Stored edits per style. Recommended: Available and Best edits are keyed by the style on Raids; Current is one
    per squad; a style switch shows that style's edits and leaves Current alone.
3.9 C2 cost. Ranking every species per boss and role is the same scan `computeBest` already runs once per boss.
    Recommended: the rows are built once per boss and style, off the main thread like the strength, and cached by
    the box generation, the advice and today.
3.10 C2 statuses for species the table does not list (1.25). Recommended: as stated; "Can get now" only from the
    schedule; no meter.
3.11 Old files. Drafts were never stored, so nothing migrates; the store's file version bumps and old files decode
    with empty edits and history. Recommended: note only.
3.12 Tests. The squad UI tests change where the design does: the tab order and the removed Save identifiers, the new
    `squad-set` toggle on every screen, `squad-reset-draft` as a link, `squad-history-row-N` and
    `squad-history-set-N`, the two-row strip (H10's drag), the Mega message under both tabs, the chip texts. The
    implementer updates each and adds a test per new statement in section 1. Recommended: yes.
3.13 Screenshots. Light and dark, default and AX5, per screen, on the private page as pass 2-5. Recommended: yes.
3.14 Review sizes (CLAUDE.md "Design passes"). Full paired review: 1.1, 1.3-1.6, 1.8-1.12, 1.15-1.29 (behaviour,
    tap targets, what is shown and stored). Cosmetic: 1.2, 1.7's wording, 1.13, 1.14, 1.21's tier chip. Recommended:
    as listed; anything mixed takes the full review.
3.15 Order to the phone. Recommended: one test build after all of A–F land and pass review, not screen by screen,
    since A, B and F touch the same views.

## 4. Greg's answers

(To be written in when given.)
