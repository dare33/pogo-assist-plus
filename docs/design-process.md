# Design passes

How a design pass runs, from the brief for the design session to Greg's phone check. Agreed by Greg on 25 Oct 2026
after design pass 1 (the league options, list and Pogo Hub handoff of 22 Oct, built as PRs 1 to 5 from 23 to 25 Oct).

Pass 1 drew the screens precisely, but most rework came from meaning: what a tag means (Strong was defined three
times), rule text written without the rule (the ranking explainer did not match `src/leagues.js`), labels that clash
("Great" beside Great League), and gaps the design never covered, filled by guesses overnight. Most of the tedium came
from feedback arriving only after five PRs were built, stacked PRs that conflicted when combined for a test build, and
the full paired review on every colour and word change. Each stage below targets one of those.

## 1. The brief for the design session

The repo writes the brief (`docs/<pass>-design-brief.md`), as for pass 1: the files to read, the files to ignore,
the data shapes, the project rules. Every brief also carries:

- **The decisions log instruction**, in these words: "Keep `DECISIONS.md` in the handoff as we go. For every change
  Greg asks for, write his words, then what changed in the design. When the session ends, write `CONCEPTS.md` from
  those decisions (section 2), and have Greg confirm it before the handoff is final."
- **Greg's own data** (section 3): the prototype reads it instead of sample data.
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

Greg confirms `CONCEPTS.md` before the handoff ends. In the repo it is the reference for wording and rules; the
read-back (section 4) checks it against the code.

## 3. The prototype runs on Greg's own data

The HTML prototype reads an export of Greg's own box as the app works it out (per copy: its tags, ratings, ranks,
league picks; per species: its tiles) in place of sample data, so he sees his own Pokémon with the rules applied
while the design can still change cheaply. The export is made by a repo script from the app's own computations, so the
prototype and the app cannot drift. The script does not exist yet; it is the first task of the next pass. The export
holds only a Pokémon inventory (as the fixtures do); Greg gives it to the design session himself, and it is never
committed (like the handoff screenshots).

## 4. Read-back before anything is built

When the handoff arrives, and before any code, the manager writes `READBACK.md` in the handoff folder:

- **Per screen, numbered statements** of what it does, each one checkable on a device ("Tapping a card opens that
  copy's Pokémon page").
- **Rules checked against the code**: each rule in `CONCEPTS.md` compared with the engine (`src/`) and PogoBox; every
  mismatch listed with the file and line.
- **Every gap the design does not cover**: screens or states it does not draw (empty, loading, error, Select mode),
  dark mode, the largest text sizes, VoiceOver, where a moved panel goes. Each is a question with a recommended answer.

Greg answers in one sitting (one-click questions); the answers are written into `READBACK.md`. Nothing is built
until then. The statements are what the reviewers check the build against. Anything decided later without Greg is a
manager call, written in STATUS and the pull request and listed for him.

## 5. One design branch and a current preview build

- The pass is built on one branch, `design/<pass>`, off `main`, with one series of commits per screen. Engine or data
  changes the screens need go first, as their own commits. One draft pull request carries the pass.
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
screenshots in light and dark mode, at the default text size and at AX5. The manager publishes them on a private
page Greg can comment on, one section per screen, and turns each comment into an item as with phone feedback. Phone
runs check how the app feels; wrong colours and clipped text are caught on the screenshots first.

## 7. Feedback

Each eyeball item, from the phone or the screenshot page, is written down with Greg's words and the decision, given a
review size (section 8), and built on the design branch (or on its own branch when it is not part of the design).

## 8. Review sized to the change

Greg's ruling (25 Oct 2026): a cosmetic change is not load-bearing, so it does not need the paired review.

- **Cosmetic**: changes only how existing information looks or reads: colour, spacing, type, layout, the order of
  elements on a screen, the wording of labels, sentences and VoiceOver text. Nothing changes in what is computed,
  stored, matched, sorted or filtered, or in which items appear. Gate: the three schemes build; the affected UI tests
  pass, one at a time, on the iPhone 17; before and after screenshots of each changed screen; one `reviewer` pass at
  high effort or above, on the diff and the screenshots. A new word must agree with `CONCEPTS.md`.
- **Everything else** (logic, data, the engine, storage and merging, scripts, build tooling): the full paired review
  as before (`reviewer` plus `reviewer-gpt`, a fold, one confirmation round).
- A change that mixes both, or that the manager is unsure about, takes the full review. The manager names the size in
  the commit message and the pull request. A reviewer who finds a cosmetic change touching logic sends it to the full
  review.

## The handoff folder

`design_handoff_<pass>/` in the repo: `README.md` and `design-files/` from the design session (as pass 1),
`DECISIONS.md` and `CONCEPTS.md` from the design session, `READBACK.md` from the repo. Screenshots stay local, not in
git.
