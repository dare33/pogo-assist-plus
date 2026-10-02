#!/usr/bin/env python
"""Generate an iOS Voice Control commands file that pages through Pokémon GO storage.

    python generate_commands.py out.voicecontrolcommands --count 400
    python generate_commands.py out.voicecontrolcommands --count 400 --name "Pogo scan" --every 2.1

The file is imported on the phone under Settings > Accessibility > Voice Control > Commands >
Import Custom Commands. It holds two commands: a batch gesture (slow right-to-left
swipes across the middle of the screen) and a chain that repeats the batch until `--count`
Pokémon have been passed. Saying the chain's name with a Pokémon's appraisal bars on screen pages
through the box; "Turn off Voice Control" or locking the phone stops it. Nothing here touches the
game beyond paging (swipes, or with --tap a press at the measured arrow point): it reads nothing and changes nothing.

What the format is (from an export made on iOS 27.2 beta, 1 Oct 2026): an XML property list with
a CommandsTable. A gesture is an NSKeyedArchiver archive of an AXMutableReplayableGesture: a list
of events, each with the finger positions in screen points, forces and a timestamp, and an event
with no fingers for each lift. A chain is a CACRecordedUserActionFlow: a list of tasks that each
name a command identifier. See PLAN.md (phase 3) for what was tested and on which devices.

Tap paging (`--tap X Y --screen-width W --screen-height H`) presses the game's right-hand next-Pokemon arrow. The file holds absolute
points, so it is made only for a screen in CHECKED_SCREENS and only at that screen's measured point (440 x 956 at 424, 775); anything else
is refused with a plain message and exit code 2, as are non-finite or non-positive numbers, a swipe position that is not finite and non-negative or
travels under MIN_SWIPE_TRAVEL points sideways or lies beyond MAX_COORDINATE, a --duration outside 0.2 to 1.5 s, a swipe slower than MIN_SWIPE_SPEED points per second, a swipe off the screen (default 440 x 956, or --screen-width/--screen-height) or within EDGE_MARGIN of its top or bottom, an --every not longer
than the duration plus 0.1 s, a non-finite --id-base, an unreadable --now, a --batch above 50, a --count below 1 or above MAX_COUNT (the app's steps for 10,000 Pokémon), a --batch below 1, and an
--every not longer than one touch. The exact command lines that produce the test fixtures are in
native/PogoReader/Tests/PogoBoxTests/Fixtures/voice/REGENERATE.md; the refusals are tested by test_generate_commands.py in this folder.

Tested on an iPhone (440 x 956 points) and an iPad mini 6: the default positions work on both.
Start with the appraisal panel open. A swipe must travel at least MIN_SWIPE_TRAVEL points sideways: a swipe that does not move is a tap,
and a tap closes the panel (and, away from the arrow, can press a button). Taps are only made with --tap, at the checked point.
"""
import argparse
import datetime
import math
import plistlib
from plistlib import UID

FINGER = 3  # the finger identifier the on-phone recorder used

# The screens a tap point has been measured on: (width, height, tap x, tap y) in points. A tap file holds absolute points, so the
# generator makes one only for a screen in this table and only for its measured point (the app's `checkedScreens` is the same list).
CHECKED_SCREENS = [(440.0, 956.0, 424.0, 775.0)]
TAP_HOLD = 0.06
SWIPE_HZ = 60
# A swipe that does not move is a tap, so a swipe must travel this far sideways. The default travels 265.
MIN_SWIPE_TRAVEL = 100.0
# The most steps the app makes: StorageCount.maximum (10,000 Pokémon) through VoiceCommandFile.steps. A larger --count is refused.
# A slow swipe is still a press: it holds near its start. A swipe lasts between these, leaves 0.1 s before the next, and stays on a screen.
MIN_SWIPE_SECONDS, MAX_SWIPE_SECONDS, SWIPE_GAP = 0.2, 1.5, 0.1
MAX_COORDINATE = 1400.0
# A swipe must move at a finger's pace: the proven swipes are 265 points in 0.85 s (312 pt/s) and in 0.6 s (442 pt/s).
MIN_SWIPE_SPEED = 250.0
# A swipe in the home-indicator band (the top and bottom 60 points) is a system gesture, not a swipe in the game. The screen defaults to the
# 440 x 956 iPhone the swipes were proven on.
EDGE_MARGIN = 60.0
DEFAULT_SCREEN = (440.0, 956.0)
MAX_BATCH = 50
MAX_COUNT = ((10_000 - 1) * 102 + 99) // 100


def finite_positive(text):
    """argparse type: a number that is finite and above zero (so nan, inf, 0 and negatives are refused with a plain message)."""
    try:
        v = float(text)
    except ValueError:
        raise argparse.ArgumentTypeError("%r is not a number" % text)
    if not math.isfinite(v) or v <= 0:
        raise argparse.ArgumentTypeError("%r must be a finite number above zero" % text)
    return v


def finite_non_negative(text):
    """argparse type: a number that is finite and not below zero (a screen position)."""
    try:
        v = float(text)
    except ValueError:
        raise argparse.ArgumentTypeError("%r is not a number" % text)
    if not math.isfinite(v) or v < 0:
        raise argparse.ArgumentTypeError("%r must be a finite number, zero or more" % text)
    return v


def whole_at_least_one(text):
    try:
        v = int(text)
    except ValueError:
        raise argparse.ArgumentTypeError("%r is not a whole number" % text)
    if v < 1:
        raise argparse.ArgumentTypeError("%r must be 1 or more" % text)
    return v


def finite_any(text):
    """argparse type: any finite number (an identifier base)."""
    try:
        v = float(text)
    except ValueError:
        raise argparse.ArgumentTypeError("%r is not a number" % text)
    if not math.isfinite(v):
        raise argparse.ArgumentTypeError("%r must be a finite number" % text)
    return v


def batch_in_range(text):
    v = whole_at_least_one(text)
    if v > MAX_BATCH:
        raise argparse.ArgumentTypeError("%r is more than %d swipes in one gesture (50 was tested)" % (text, MAX_BATCH))
    return v


def count_in_range(text):
    v = whole_at_least_one(text)
    if v > MAX_COUNT:
        raise argparse.ArgumentTypeError("%r is more than the %d page steps the app makes for 10,000 Pokémon" % (text, MAX_COUNT))
    return v


class Archive:
    """The small part of NSKeyedArchiver's layout these two classes need."""

    def __init__(self):
        self.objects = ["$null"]
        self.memo = {}

    def add(self, value):
        self.objects.append(value)
        return UID(len(self.objects) - 1)

    def once(self, key, make):
        if key not in self.memo:
            self.memo[key] = self.add(make())
        return self.memo[key]

    def string(self, text):
        return self.once(("s", text), lambda: text)

    def cls(self, *names):
        return self.once(("c", names[0]), lambda: {"$classname": names[0], "$classes": list(names)})

    def dumps(self):
        return plistlib.dumps({"$version": 100000, "$archiver": "NSKeyedArchiver", "$top": {"root": UID(1)},
                               "$objects": self.objects}, fmt=plistlib.FMT_BINARY)


def gesture(events):
    """events: [(time, (x, y) or None)]; None is a lift."""
    a = Archive()
    root = a.add(None)
    array = a.add(None)
    k_fingers, k_forces, k_time = a.string("Fingers"), a.string("Forces"), a.string("Time")
    finger = a.once("finger", lambda: FINGER)
    zero = a.once("zero", lambda: 0.0)
    mutable = lambda: a.cls("NSMutableDictionary", "NSDictionary", "NSObject")
    uids = []
    for time, point in events:
        event = a.add(None)
        uids.append(event)
        if point is None:
            fingers = a.add({"NS.keys": [], "NS.objects": [], "$class": mutable()})
            forces = a.add({"NS.keys": [], "NS.objects": [], "$class": mutable()})
        else:
            value = a.add(None)
            a.objects[value.data] = {"NS.pointval": a.add("{%r, %r}" % point), "$class": a.cls("NSValue", "NSObject"), "NS.special": 1}
            fingers = a.add({"NS.keys": [finger], "NS.objects": [value], "$class": mutable()})
            forces = a.add({"NS.keys": [finger], "NS.objects": [zero], "$class": mutable()})
        a.objects[event.data] = {"NS.keys": [k_fingers, k_forces, k_time], "NS.objects": [fingers, forces, a.add(float(time))],
                                 "$class": a.cls("NSDictionary", "NSObject")}
    a.objects[array.data] = {"NS.objects": uids, "$class": a.cls("NSMutableArray", "NSArray", "NSObject")}
    a.objects[root.data] = {"$class": a.cls("AXMutableReplayableGesture", "AXReplayableGesture", "NSObject"),
                            "AllEvents": array, "Version": a.once("one", lambda: 1), "ArePointsDeviceRelative": False}
    return a.dumps()


def flow(command_id, repeats, locale):
    a = Archive()
    root = a.add(None)
    tasks = a.add(None)
    target = a.string(command_id)
    uids = []
    for _ in range(repeats):
        task = a.add(None)
        uids.append(task)
        attributes = a.add({"NS.keys": [], "NS.objects": [], "$class": a.cls("NSMutableDictionary", "NSDictionary", "NSObject")})
        a.objects[task.data] = {"CommandIdentifier": target, "Version": 1, "Type": 1, "TargetAttributes": attributes,
                                "CanIgnoreFailure": False, "$class": a.cls("CACRecordedUserAction", "NSObject")}
    a.objects[tasks.data] = {"NS.objects": uids, "$class": a.cls("NSMutableArray", "NSArray", "NSObject")}
    settings = a.add({"NS.keys": [a.string("OverlayType"), a.string("LocaleIdentifier")],
                      "NS.objects": [a.string("None"), a.string(locale)], "$class": a.cls("NSDictionary", "NSObject")})
    a.objects[root.data] = {"$class": a.cls("CACRecordedUserActionFlow", "NSObject"), "Version": 1,
                            "EnvironmentSettings": settings, "Tasks": tasks}
    return a.dumps()


def swipes(start, count, x_from, x_to, y, every, duration, hz=SWIPE_HZ):
    """`count` swipes, one starting every `every` seconds, each lasting `duration`."""
    events = []
    for k in range(count):
        t0 = start + k * every
        steps = round(duration * hz)
        for i in range(steps + 1):
            f = i / steps
            f = f * f * (3 - 2 * f)  # ease in and out, like a finger
            events.append((t0 + i / hz, (round(x_from + (x_to - x_from) * f, 2), float(y))))
        events.append((t0 + (steps + 1) / hz, None))
    return events


def taps(start, count, x, y, every, hold=TAP_HOLD):
    """`count` taps at one fixed point, one starting every `every` seconds: a touch, and the lift `hold` seconds later.
    A tap is a swipe that does not move."""
    events = []
    for k in range(count):
        t0 = start + k * every
        events.append((t0, (float(x), float(y))))
        events.append((t0 + hold, None))
    return events


# Tap paging presses the game's right-hand "next Pokémon" arrow. Once the appraisal closes at the end of the list the
# Pokémon page shows, with Power up and Evolve to the LEFT of that arrow, so a tap must stay at the right edge. The
# generator refuses a tap point left of this fraction of the screen width; nothing may act in the game beyond paging.
MIN_TAP_X_FRACTION = 0.95


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("out")
    p.add_argument("--count", type=count_in_range, required=True, help="how many Pokémon to page past (the storage count)")
    p.add_argument("--name", default="Pogo scan", help="what to say; keep it unlike any other command")
    p.add_argument("--batch-name", default="Storage page step", help="name of the batch gesture; it must not share words with --name, or Voice Control can run the wrong one")
    p.add_argument("--batch", type=batch_in_range, default=20, help="most swipes in one gesture (50 was tested); the batch is then cut to ceil(count / repeats) so the last repeat does not overshoot by almost a batch")
    p.add_argument("--every", type=finite_positive, default=None, help="seconds between swipe starts (default 2.1, or 1.2 with --tap; 2.1 gives 7 frames at 5 fps; 1.6 was tested on a small sample)")
    p.add_argument("--duration", type=finite_positive, default=0.85, help="seconds one swipe lasts (0.6 with --every 1.6)")
    p.add_argument("--x-from", type=finite_non_negative, default=340.0)
    p.add_argument("--x-to", type=finite_non_negative, default=75.0)
    p.add_argument("--y", type=finite_non_negative, default=340.0)
    p.add_argument("--locale", default="en_AU", help="the phone's Voice Control language")
    p.add_argument("--tap", type=finite_positive, nargs=2, metavar=("X", "Y"), help="page by tapping the next-Pokémon arrow at this point (screen points) instead of swiping")
    p.add_argument("--screen-width", type=finite_positive, help="width in points of the screen the --tap point was measured on (with --tap)")
    p.add_argument("--screen-height", type=finite_positive, help="height in points of that screen (with --tap)")
    p.add_argument("--id-base", type=finite_any, help="number the command identifiers come from (Custom.<n> and Custom.<n+60>); give the same one every time for a mode so importing the file replaces that mode's commands and leaves the others alone. Default: the time, so every file is a new pair")
    p.add_argument("--now", help="fix the time stamps and identifiers (UTC, YYYY-MM-DDTHH:MM:SS) so two runs give the same file; for tests")
    args = p.parse_args()
    if args.tap:
        if args.screen_width is None or args.screen_height is None:
            p.error("--tap needs --screen-width and --screen-height: a tap file holds absolute points, so it is made for one screen size")
        match = [c for c in CHECKED_SCREENS if c[0] == args.screen_width and c[1] == args.screen_height]
        if not match or (match[0][2], match[0][3]) != tuple(args.tap):
            p.error("tap paging is only available on screens it has been checked on (%s) and at that screen's measured point"
                    % ", ".join("%gx%g at %g, %g" % c for c in CHECKED_SCREENS))
        if args.tap[0] < MIN_TAP_X_FRACTION * args.screen_width:
            p.error("--tap x %.1f is left of %.0f%% of the %.0f pt screen width: a tap there could reach Power up or Evolve" % (args.tap[0], MIN_TAP_X_FRACTION * 100, args.screen_width))
    if args.every is None:
        args.every = 1.2 if args.tap else 2.1
    touch = TAP_HOLD if args.tap else args.duration + 1.0 / SWIPE_HZ
    if args.every <= touch:
        p.error("--every %g must be longer than one touch lasts (%g s): the next must not start before this one is over" % (args.every, touch))
    for flag, v in (("--x-from", args.x_from), ("--x-to", args.x_to), ("--y", args.y)):
        if not args.tap and v > MAX_COORDINATE:
            p.error("%s %g is off any screen (at most %g points)" % (flag, v, MAX_COORDINATE))
    if not args.tap and not MIN_SWIPE_SECONDS <= args.duration <= MAX_SWIPE_SECONDS:
        p.error("--duration %g must be from %g to %g seconds: a slower swipe is a press" % (args.duration, MIN_SWIPE_SECONDS, MAX_SWIPE_SECONDS))
    if not args.tap and args.every <= args.duration + SWIPE_GAP:
        p.error("--every %g must be longer than --duration %g plus %g s" % (args.every, args.duration, SWIPE_GAP))
    if not args.tap:
        width, height = (args.screen_width or DEFAULT_SCREEN[0]), (args.screen_height or DEFAULT_SCREEN[1])
        for flag, v in (("--x-from", args.x_from), ("--x-to", args.x_to)):
            if v >= width:
                p.error("%s %g is at or beyond the right edge of the %g pt wide screen" % (flag, v, width))
        if not EDGE_MARGIN <= args.y <= height - EDGE_MARGIN:
            p.error("--y %g is within %g points of the top or bottom of the %g pt tall screen: that band holds system gestures" % (args.y, EDGE_MARGIN, height))
        if abs(args.x_to - args.x_from) / args.duration < MIN_SWIPE_SPEED:
            p.error("a swipe of %g points in %g s is slower than %g points per second: a slow swipe is a press" % (abs(args.x_to - args.x_from), args.duration, MIN_SWIPE_SPEED))
    if not args.tap and abs(args.x_to - args.x_from) < MIN_SWIPE_TRAVEL:
        p.error("a swipe from x %g to x %g travels under %g points: a swipe that does not move is a tap, and a tap closes the panel or can press a button" % (args.x_from, args.x_to, MIN_SWIPE_TRAVEL))
    if not args.tap and args.duration < 2.0 / SWIPE_HZ:
        p.error("--duration %g is too short for a swipe (at least %g s)" % (args.duration, 2.0 / SWIPE_HZ))

    try:
        # Python 3.9's fromisoformat does not read a trailing Z
        fixed = datetime.datetime.fromisoformat(args.now[:-1] + "+00:00" if args.now and args.now.endswith(("Z", "z")) else args.now) if args.now else None
        if fixed is not None and fixed.tzinfo is not None:
            fixed = fixed.astimezone(datetime.timezone.utc).replace(tzinfo=None)   # an offset is converted to UTC
    except ValueError:
        p.error("--now must be a time like 2026-10-02T00:00:00 (UTC, or with an offset)")
    now = fixed if fixed else datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    ref = (now - datetime.datetime(2001, 1, 1)).total_seconds()  # Apple's reference date
    id_base = args.id_base if args.id_base is not None else ref
    batch_id, chain_id = "Custom.%.6f" % id_base, "Custom.%.6f" % (id_base + 60)
    repeats = math.ceil(args.count / args.batch)
    args.batch = math.ceil(args.count / repeats)  # 51 steps with --batch 50 is 2 x 26, not 2 x 50
    base = dict(ConfirmationRequired=False, CustomModifyDate=now, CustomScope="com.apple.speech.SystemWideScope")
    table = {
        batch_id: dict(base, CustomCommands={args.locale: [args.batch_name]}, CustomType="RunGesture",
                       CustomGesture=gesture(taps(ref, args.batch, args.tap[0], args.tap[1], args.every) if args.tap
                                              else swipes(ref, args.batch, args.x_from, args.x_to, args.y, args.every, args.duration))),
        chain_id: dict(base, CustomCommands={args.locale: [args.name]}, CustomType="RunUserActionFlow",
                       CustomUserActionFlow=flow(batch_id, repeats, args.locale)),
    }
    # An export carries the exporting phone's SystemVersion; the files imported in testing copied
    # one. Whether the importer needs it, or accepts another version, is untested.
    system = {"ProductName": "iPhone OS", "ProductVersion": "27.2", "ProductBuildVersion": "24B5089g", "ReleaseType": "Beta"}
    with open(args.out, "wb") as f:
        plistlib.dump({"CommandsTable": table, "ExportDate": ref, "SystemVersion": system}, f, fmt=plistlib.FMT_XML)
    minutes = repeats * (args.batch * args.every + 0.8) / 60
    print(f'wrote {args.out}: say "{args.name}" for {repeats} x {args.batch} {"taps" if args.tap else "swipes"} ({repeats * args.batch} Pokémon, about {minutes:.0f} min)')


if __name__ == "__main__":
    main()
