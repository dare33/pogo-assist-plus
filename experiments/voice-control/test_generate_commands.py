"""Checks of the generator's argument handling: python3 -m unittest experiments/voice-control/test_generate_commands.py

Every refusal is a plain message and exit code 2, never a traceback; a tap file is made only for a screen in the table."""
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "generate_commands.py")


def run(*args):
    out = os.path.join(tempfile.mkdtemp(), "x.voicecontrolcommands")
    return subprocess.run([sys.executable, SCRIPT, out, "--now", "2026-10-02T00:00:00", *args], capture_output=True, text=True), out


class Refusals(unittest.TestCase):
    def refused(self, *args):
        r, out = run(*args)
        self.assertEqual(r.returncode, 2, (args, r.stderr))
        self.assertNotIn("Traceback", r.stderr, args)
        self.assertTrue(r.stderr.strip(), args)
        self.assertFalse(os.path.exists(out), args)

    def test_a_tap_needs_a_checked_screen_and_its_exact_point(self):
        self.refused("--count", "10", "--tap", "424", "775")                                           # no --screen-height
        self.refused("--count", "10", "--tap", "424", "775", "--screen-width", "440", "--screen-height", "957")   # not a checked size
        self.refused("--count", "10", "--tap", "418", "775", "--screen-width", "440", "--screen-height", "956")   # passes the edge rule only
        self.refused("--count", "10", "--tap", "424", "774", "--screen-width", "440", "--screen-height", "956")
        self.refused("--count", "10", "--tap", "424", "775", "--screen-width", "744", "--screen-height", "1133")  # an iPad mini

    def test_non_finite_and_non_positive_numbers(self):
        for bad in ("nan", "inf", "-1", "0"):
            self.refused("--count", "10", "--tap", bad, "775", "--screen-width", "440", "--screen-height", "956")
            self.refused("--count", "10", "--tap", "424", "775", "--screen-width", bad, "--screen-height", "956")
            self.refused("--count", "10", "--tap", "424", "775", "--screen-width", "440", "--screen-height", bad)
        self.refused("--count", "10", "--every", "nan")
        self.refused("--count", "10", "--duration", "inf")

    def test_timing_counts_and_sizes(self):
        self.refused("--count", "0")
        self.refused("--count", "-3")
        self.refused("--count", "10", "--batch", "0")
        self.refused("--count", "10", "--every", "0.5", "--duration", "0.85")        # a swipe must be over before the next starts
        self.refused("--count", "10", "--duration", "0.01")                           # too short to be a swipe
        self.refused("--count", "10", "--tap", "424", "775", "--screen-width", "440", "--screen-height", "956", "--every", "0.06")   # not longer than the touch


    def test_a_swipe_that_does_not_move_is_a_tap(self):
        self.refused("--count", "10", "--x-from", "200", "--x-to", "200", "--y", "775")      # presses left of the arrow
        self.refused("--count", "10", "--x-from", "200", "--x-to", "299")                    # travel under 100
        self.refused("--count", "10", "--x-from", "299", "--x-to", "200")

    def test_swipe_positions_must_be_finite_and_not_negative(self):
        for bad in ("nan", "inf", "-inf", "-1", "abc"):
            for flag in ("--x-from", "--x-to", "--y"):
                self.refused("--count", "10", flag, bad)

    def test_count_has_the_apps_upper_limit(self):
        self.refused("--count", "10200")
        self.refused("--count", "999999999999999999999")


class Accepts(unittest.TestCase):
    def test_the_checked_screen_and_the_defaults(self):
        r, out = run("--count", "10", "--tap", "424", "775", "--screen-width", "440", "--screen-height", "956")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.getsize(out) > 0)
        r, out = run("--count", "10")
        self.assertEqual(r.returncode, 0, r.stderr)
        r, out = run("--count", "10", "--x-from", "300", "--x-to", "200")                     # exactly 100 points of travel
        self.assertEqual(r.returncode, 0, r.stderr)
        r, out = run("--count", "10199")                                                       # the app's most: steps for 10,000 Pokémon
        self.assertEqual(r.returncode, 0, r.stderr)


if __name__ == "__main__":
    unittest.main()
