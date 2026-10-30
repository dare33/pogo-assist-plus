# Feedback: design pass 3 (the Pokémon screens)

Each eyeball item with Greg's words, the decision and its review size (`docs/design-process.md` sections 7 and 8).

## Phone run 1, 30 Oct 2026 (build 413a8a3)

1. Greg: "dynamax and shadow toggles - the dynamax and shadow icons don't seem to react to my touch when toggled on,
   i.e. i can't toggle off, i clicked it a number of times and now AFTER a while it seems to turn on and off lagged
   behind." Cause: each tap saved a whole box version and re-ran the whole-box advice before the mark redrew, and queued
   taps were replayed later. Decision: a mark (and every Advanced details chip) shows its new state at once; quick taps
   settle on the last state left; one save at a time. Size: full.
2. Greg: "the dynamax and shadow icons are not obvious to me as to what they are or do. Maybe we should have the names
   instead." Decision: the two marks become labelled pills, "Dynamax" and "Shadow"; Advanced details keeps its icon.
   Size: cosmetic.
3. Greg: "scrolling on pokemon page - also laggy when selecting an alphabet from the list. however the scroll animation
   itself seems fine." (My Pokémon's A–Z index.) Decision: measure the jump and fix the measured cause. Size: full.
4. Greg: "advice does update on toggles of things like lucky/shadow/purified etc. but its a bit slow - any way to speed
   it up? make it feel responsive/instant." Decision: an edit no longer queues a whole-box advice per tap; the edited
   Pokémon's family is worked out first for its page, then the whole box. Size: full.
5. Greg: "why are these amaura/aurorus considered weak #110/849 and #154/1152 is pretty good yeah? or is pvp really
   that shallow that if you're #110 its still weak." Answered, no change: WEAK means the species is below the B-tier
   line of our league tables (the top 25 or so per league), not a judgement of the rank alone.
