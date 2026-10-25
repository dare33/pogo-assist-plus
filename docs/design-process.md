# Design passes

How a design pass runs, from the brief for the design session to Greg's phone check. Agreed by Greg on 25 Oct 2026
after design pass 1 (the league options, list and Pogo Hub handoff of 22 Oct, built as design PRs 1 to 5, pull requests
#9, #10, #14, #15 and #13, from 23 to 25 Oct), except section 5's open item. `<pass>` below is a short lower-case slug
naming the pass (for example `pass-2-hub-teams`), used in `docs/<pass>-design-brief.md`, `design/<pass>` and
`design_handoff_<pass>/`.

Pass 1 drew the screens precisely, but most rework came from meaning: what a tag means (Strong was defined three
times), rule text written without the rule (the ranking explainer did not match `src/leagues.js`), labels that clash
("Great" beside Great League), and gaps the design never covered, filled by guesses overnight. Most of the tedium came
from feedback arriving only after five PRs were built, stacked PRs that conflicted when combined for a test build, and
the full paired review on every colour and word change. Each stage below targets one of those.

## 1. The brief for the design session

The repo writes the brief (`docs/<pass>-design-brief.md`; pass 1's was not committed, from pass 2 the brief is
committed): the files to read, the files to ignore, the data shapes, the project rules. Every brief also carries:

- **The decisions log instruction**, in these words: "Keep `DECISIONS.md` in the handoff as we go. For every change
  Greg asks for, write his words, then what changed in the design. When the session ends, write `CONCEPTS.md` from
  those decisions (section 2), and have Greg confirm it before the handoff is final."
- **Greg's own data** (section 3): the prototype reads it instead of sample data, when he gives the session the file.
- **What is out of scope**, named, so the session does not redesign it (pass 1: the scan screens).

## 2. Concepts come out of the session, not before it

Greg makes his changes in the session first; the definitions follow from what he decided. At the end the session writes
`CONCEPTS.md` in the handoff:

- **Terms**: every label and word the screens use for a rating, a ranking, an activity or a state, each defined in one
  sentence (what "Top" means, what "best" means on each screen).
- **Rules**: every rule the screens apply, stated so it can be checked against the engine: which copy a card shows,
  which ranking a screen follows, what a filter keeps, how ties break.
- **Word check**: each label against every other label on the same screens and against the game's own terms, with
  any clash named (pass 1: "Great" the tag beside "Great League" the card).

Greg confirms `CONCEPTS.md` before the handoff ends (the manager's addition to what Greg agreed). In the repo it is
the reference for wording and rules; the read-back (section 4) checks it against the code.

## 3. The prototype runs on Greg's own data

The HTML prototype reads an export of Greg's own box as the app works it out (per copy: its tags, ratings, ranks,
league picks; per species: its tiles) in place of sample data, so he sees his own Pokémon with the rules applied
while the design can still change cheaply.

- **The file**: `box-data.json` (the prototype may also read a `box-data.js` wrapper of the same data), written by a
  script under the git-ignored `out/design-data/`. Both names are git-ignored in any folder. The committed handoff
  keeps sample data in `design-files/`, so the committed prototype still runs; the prototype loads `box-data.json`
  when it is present beside it.
- **Permitted content**: per copy its species, form, CP, IV values and %, Shadow/Purified/Dynamax marks, and what the
  app computes from them (tags, ratings, ranks, league picks; per species its tiles). Nothing else: no account name,
  no scan history or dates, no file paths, no device or source fields. `BoxExport.swift` carries an account field, so
  the script must not reuse it as is.
- **Which code makes it**: from PogoBox, the Swift code the app's screens read (`BoxInsight`, `LeaguePanel` and the
  advice it decodes), run as a small executable in the PogoReader package, not a re-implementation. The data cannot
  drift from the app; the export is regenerated whenever those computations change and before the prototype is shown
  again.
- **Order**: the script is prepared before the design session, as its own change from `main`. It is a script, so it
  takes the full review (section 8).
- Greg gives the file to the design session himself. It is never committed (like the handoff screenshots).

## 4. Read-back before anything is built

When the handoff arrives, and before any of it is built, the manager writes `READBACK.md` in the handoff folder:

- **Per screen, numbered statements** of what it does, each one checkable on a device ("Tapping a card opens that
  copy's Pokémon page").
- **Rules checked against the code**: each rule in `CONCEPTS.md` compared with the engine (`src/`) and PogoBox; every
  mismatch listed with the file and line.
- **Every gap the design does not cover**: screens or states it does not draw (empty, loading, error, Select mode),
  dark mode, the largest text sizes, VoiceOver, where a moved panel goes. Each is a question with a recommended answer.

Greg answers it before any of the handoff is built (one-click questions); the answers are written into
`READBACK.md`. Nothing is built until then. The statements are what the reviewers check the build against. Anything
decided later without Greg is a manager call, written in STATUS and the pull request and listed for him.

## 5. One design branch and a current preview build

- The pass is built on one branch, `design/<pass>`, off `main`, with one commit per screen. Each screen lands as ONE
  commit: an implementer's work-in-progress commits for a screen are squashed before the screen goes to review, while
  unpushed; review fixes are later, separate commits that name the screen. Engine or data changes the screens need go
  first, as their own commits. One draft pull request carries the pass.
- Fixes found along the way that are not part of the design go on their own branches from `main`, not on the design
  branch.
- The preview build Greg runs from Xcode (`test/greg-build`, local, never pushed) is the design branch plus any open
  fixes Greg wants in it. The manager rebuilds it whenever a screen or a review fix lands and says which commit it is
  at, so what is on the phone is never behind what is being reviewed.
- Greg's eyeball goes screen by screen, not pull request by pull request.
- Open (Greg, 25 Oct): one screen to the phone first, or a batch of screens at once. Until he decides, the manager
  asks at the start of each pass.

## 6. Screenshots between phone runs

For each screen, UI tests on the iPhone 17 simulator (through `native/tools/xcb.sh`, as every build) capture
screenshots in light and dark mode, at the default text size and at AX5. The screen's implementer writes its screenshot
test. AX5 is the launch argument `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` (as
`ListScreensTests` uses). Screenshot runs and the cosmetic gate's UI tests use the iPhone 17 simulator, or a
`native/tools/sim-temp.sh` clone of it when another run is using it (never two runs on one simulator).

The screenshots are kept locally under the git-ignored `out/screens/`. The manager publishes them on a private
claude.ai Artifact, one section per screen, updated in place for each new round, which Greg can comment on, and turns
each comment into an item as with phone feedback. Phone runs check how the app feels; wrong colours and clipped text
are caught on the screenshots first.

## 7. Feedback

Each eyeball item, from the phone or the screenshot page, is written down with Greg's words and the decision, given a
review size (section 8), and built on the design branch (or on its own branch when it is not part of the design).

## 8. Review sized to the change

Greg's ruling (25 Oct 2026): a cosmetic change is not load-bearing, so it does not need the paired review.

- **Cosmetic**: changes only how existing information looks or reads (colour, spacing, type, the layout of elements
  already on the screen, the order of fixed elements such as chips or panels, and the wording of labels, sentences and
  VoiceOver text), and the meaning, the accessibility behaviour (traits, grouping, actions) and which action comes
  first are unchanged. Gate: the PogoAssist build for an iPhone simulator through `native/tools/xcb.sh`, `swift test`
  in `native/PogoReader` and `npm test` pass; the affected UI tests pass, one at a time, on the iPhone 17; before and
  after screenshots of each changed screen; one `reviewer` pass at high effort or above, on the diff and the
  screenshots. A new word must agree with `CONCEPTS.md`.
- **Full review** (`reviewer` plus `reviewer-gpt`, a fold, one confirmation round): anything that changes what is
  computed, stored, matched, sorted or filtered, or which items appear; a change to the order of data rows or which
  item the user sees first; a condition that shows or hides an element; a new state or screen (empty, loading,
  error); adding, removing or moving a button or tap target, or changing what a tap does; changing accessibility
  identifiers or any UI test expectation other than text the change itself rewords; a word whose meaning changes; any
  change to a term or rule in `CONCEPTS.md`; and logic, data, the engine, storage and merging, scripts and build
  tooling.
- A sentence that states a rule (an explainer, a tag's line) may be cosmetic, but the reviewer checks it against the
  `CONCEPTS.md` rule and the code it describes.
- A change that mixes both, or that the manager is unsure about, takes the full review. The manager names the size in
  the commit message and the pull request.
- A reviewer cannot route work. A reviewer who finds a cosmetic-sized change that belongs in the full review returns
  NEEDS-FULL-REVIEW; the manager then runs the paired review before the change is pushed for Greg.
- After the handoff, when Greg's feedback renames or redefines a term or changes a rule, the manager updates
  `CONCEPTS.md` with Greg's words in the same commit as the change, and that change takes the full review. A word
  swap with the same meaning (for example Strong to Top) updates `CONCEPTS.md` and stays cosmetic.

## The handoff folder

`design_handoff_<pass>/` in the repo: `README.md` and `design-files/` from the design session (as pass 1),
`DECISIONS.md` and `CONCEPTS.md` from the design session, `READBACK.md` from the repo. Screenshots stay local, not in
git.
