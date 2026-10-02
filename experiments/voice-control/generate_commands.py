#!/usr/bin/env python
"""Generate an iOS Voice Control commands file that pages through Pokémon GO storage.

    python generate_commands.py out.voicecontrolcommands --count 400
    python generate_commands.py out.voicecontrolcommands --count 400 --name "Pogo scan" --every 2.1

The file is imported on the phone under Settings > Accessibility > Voice Control > Customize
Commands > Import Custom Commands. It holds two commands: a batch gesture (slow right-to-left
swipes across the middle of the screen) and a chain that repeats the batch until `--count`
Pokémon have been passed. Saying the chain's name with a Pokémon's appraisal bars on screen pages
through the box; "Turn off Voice Control" or locking the phone stops it. Nothing here touches the
game beyond those swipes: it reads nothing and changes nothing.

What the format is (from an export made on iOS 27.2 beta, 1 Oct 2026): an XML property list with
a CommandsTable. A gesture is an NSKeyedArchiver archive of an AXMutableReplayableGesture: a list
of events, each with the finger positions in screen points, forces and a timestamp, and an event
with no fingers for each lift. A chain is a CACRecordedUserActionFlow: a list of tasks that each
name a command identifier. See PLAN.md (phase 3) for what was tested and on which devices.

Tested on an iPhone (440 x 956 points) and an iPad mini 6: the default positions work on both.
Start with the appraisal panel open. Do not add a tap: a tap closes the panel.
"""
import argparse
import datetime
import math
import plistlib
from plistlib import UID

FINGER = 3  # the finger identifier the on-phone recorder used


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


def swipes(start, count, x_from, x_to, y, every, duration, hz=60):
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


def taps(start, count, x, y, every, hold=0.06):
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
    p.add_argument("--count", type=int, required=True, help="how many Pokémon to page past (the storage count)")
    p.add_argument("--name", default="Pogo scan", help="what to say; keep it unlike any other command")
    p.add_argument("--batch-name", default="Storage page step", help="name of the batch gesture; it must not share words with --name, or Voice Control can run the wrong one")
    p.add_argument("--batch", type=int, default=20, help="swipes in one gesture (50 was tested)")
    p.add_argument("--every", type=float, default=None, help="seconds between swipe starts (default 2.1, or 1.2 with --tap; 2.1 gives 7 frames at 5 fps; 1.6 was tested on a small sample)")
    p.add_argument("--duration", type=float, default=0.85, help="seconds one swipe lasts (0.6 with --every 1.6)")
    p.add_argument("--x-from", type=float, default=340.0)
    p.add_argument("--x-to", type=float, default=75.0)
    p.add_argument("--y", type=float, default=340.0)
    p.add_argument("--locale", default="en_AU", help="the phone's Voice Control language")
    p.add_argument("--tap", type=float, nargs=2, metavar=("X", "Y"), help="page by tapping the next-Pokémon arrow at this point (screen points) instead of swiping")
    p.add_argument("--screen-width", type=float, default=440.0, help="width in points of the screen the --tap point was measured on")
    p.add_argument("--now", help="fix the time stamps and identifiers (UTC, YYYY-MM-DDTHH:MM:SS) so two runs give the same file; for tests")
    args = p.parse_args()
    if args.tap and args.tap[0] < MIN_TAP_X_FRACTION * args.screen_width:
        p.error("--tap x %.1f is left of %.0f%% of the %.0f pt screen width: a tap there could reach Power up or Evolve" % (args.tap[0], MIN_TAP_X_FRACTION * 100, args.screen_width))
    if args.every is None:
        args.every = 1.2 if args.tap else 2.1

    now = datetime.datetime.fromisoformat(args.now) if args.now else datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    ref = (now - datetime.datetime(2001, 1, 1)).total_seconds()  # Apple's reference date
    batch_id, chain_id = "Custom.%.6f" % ref, "Custom.%.6f" % (ref + 60)
    repeats = math.ceil(args.count / args.batch)
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
