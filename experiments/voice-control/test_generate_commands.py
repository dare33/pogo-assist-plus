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

    def test_a_slow_swipe_is_still_a_press_and_positions_stay_on_a_screen(self):
        self.refused("--count", "10", "--duration", "60", "--every", "61")
        self.refused("--count", "10", "--duration", "0.1", "--every", "2")
        self.refused("--count", "10", "--duration", "1.6", "--every", "5")
        self.refused("--count", "10", "--duration", "0.85", "--every", "0.9")    # under duration + 0.1
        self.refused("--count", "10", "--x-from", "2000")
        self.refused("--count", "10", "--y", "5000")
        self.refused("--count", "10", "--x-to", "1401", "--x-from", "100")

    def test_a_slow_travel_is_refused(self):
        self.refused("--count", "10", "--duration", "1.5", "--every", "2", "--x-from", "340", "--x-to", "75")      # 177 pt/s
        self.refused("--count", "10", "--duration", "0.85", "--x-from", "300", "--x-to", "100")                   # 235 pt/s

    def test_swipes_stay_on_the_screen_and_out_of_the_edge_band(self):
        self.refused("--count", "10", "--y", "30")
        self.refused("--count", "10", "--y", "900")                      # within 60 of the bottom of 956
        self.refused("--count", "10", "--x-from", "500")                 # right of 440
        self.refused("--count", "10", "--screen-width", "300", "--x-from", "340")
        self.refused("--count", "10", "--screen-height", "500", "--y", "480")
        r, _ = run("--count", "10", "--y", "60"); self.assertEqual(r.returncode, 0, r.stderr)
        r, _ = run("--count", "10", "--y", "896"); self.assertEqual(r.returncode, 0, r.stderr)
        r, _ = run("--count", "10", "--screen-width", "744", "--screen-height", "1133", "--y", "1000", "--x-from", "700"); self.assertEqual(r.returncode, 0, r.stderr)

    def test_now_with_z_works_and_a_swipe_at_the_right_edge_is_refused(self):
        out = os.path.join(tempfile.mkdtemp(), "x")
        r = subprocess.run([sys.executable, SCRIPT, out, "--count", "10", "--now", "2026-10-02T00:00:00Z"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.refused("--count", "10", "--x-from", "440")                     # equal to the width
        self.refused("--count", "10", "--x-from", "439", "--x-to", "100", "--screen-width", "439")

    def test_now_with_an_offset_is_converted_or_refused_plainly(self):
        out = os.path.join(tempfile.mkdtemp(), "x")
        for text in ("2026-10-02T10:00:00+10:00", "2026-10-02T00:00:00Z"):
            r = subprocess.run([sys.executable, SCRIPT, out, "--count", "10", "--now", text], capture_output=True, text=True)
            self.assertNotIn("Traceback", r.stderr, text)
            self.assertIn(r.returncode, (0, 2), text)
        a = subprocess.run([sys.executable, SCRIPT, out + "a", "--count", "10", "--now", "2026-10-02T10:00:00+10:00"], capture_output=True, text=True)
        self.assertEqual(a.returncode, 0, a.stderr)
        b = subprocess.run([sys.executable, SCRIPT, out + "b", "--count", "10", "--now", "2026-10-02T00:00:00"], capture_output=True, text=True)
        self.assertEqual(open(out + "a", "rb").read(), open(out + "b", "rb").read(), "+10:00 is the same instant as 00:00 UTC")

    def test_id_base_now_and_batch(self):
        self.refused("--count", "10", "--id-base", "nan")
        self.refused("--count", "10", "--id-base", "inf")
        r, out = subprocess.run([sys.executable, SCRIPT, os.path.join(tempfile.mkdtemp(), "x"), "--count", "10", "--now", "not-a-time"], capture_output=True, text=True), None
        self.assertEqual(r.returncode, 2); self.assertNotIn("Traceback", r.stderr)
        self.refused("--count", "10", "--batch", "51")

    def test_count_has_the_apps_upper_limit(self):
        self.refused("--count", "10200")
        self.refused("--count", "999999999999999999999")


class Accepts(unittest.TestCase):
    def test_the_fixture_command_lines_still_work(self):
        for line in (["--count", "1427", "--batch", "50", "--every", "1.6", "--duration", "0.6", "--name", "Pogo swipe", "--batch-name", "Velvet marble", "--id-base", "780000600"],
                     ["--count", "51", "--batch", "50", "--name", "Pogo slow swipe", "--batch-name", "Quiet walnut", "--id-base", "780000400"],
                     ["--count", "51", "--batch", "50", "--tap", "424", "775", "--screen-width", "440", "--screen-height", "956", "--every", "1.0", "--id-base", "780000200"]):
            r, out = run(*line)
            self.assertEqual(r.returncode, 0, (line, r.stderr))

    def test_the_checked_screen_and_the_defaults(self):
        r, out = run("--count", "10", "--tap", "424", "775", "--screen-width", "440", "--screen-height", "956")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.getsize(out) > 0)
        r, out = run("--count", "10")
        self.assertEqual(r.returncode, 0, r.stderr)
        r, out = run("--count", "10", "--x-from", "300", "--x-to", "200", "--duration", "0.4")                     # exactly 100 points of travel
        self.assertEqual(r.returncode, 0, r.stderr)
        r, out = run("--count", "10199")                                                       # the app's most: steps for 10,000 Pokémon
        self.assertEqual(r.returncode, 0, r.stderr)


if __name__ == "__main__":
    unittest.main()
