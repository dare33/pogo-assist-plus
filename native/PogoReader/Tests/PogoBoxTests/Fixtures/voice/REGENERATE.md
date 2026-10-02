# The voice-command fixtures

Each `*.vc.deflate` is the output of `experiments/voice-control/generate_commands.py` for one of the command lines below, raw-deflate
compressed (Python `zlib.compressobj(9, zlib.DEFLATED, -15)`). `VoiceCommandFileTests.testMatchesThePythonOutput` makes the same file in
Swift and compares the two as property lists with the embedded archives decoded. `--now` fixes the time stamps; the per-mode names and
identifiers are the app's (`VoiceCommandFile.Pace`).

Run each from the repository root as `python3 experiments/voice-control/generate_commands.py out.vc --now 2026-10-02T00:00:00 <arguments>`:

| fixture | arguments |
|---|---|
| swipe-normal-50 | `--count 50 --batch 50 --name "Pogo slow swipe" --batch-name "Quiet walnut" --id-base 780000400` |
| swipe-normal-1427 | `--count 1427 --batch 50 --name "Pogo slow swipe" --batch-name "Quiet walnut" --id-base 780000400` |
| swipe-normal-3 | `--count 3 --batch 3 --name "Pogo slow swipe" --batch-name "Quiet walnut" --id-base 780000400` |
| swipe-normal-51 | `--count 51 --batch 50 --name "Pogo slow swipe" --batch-name "Quiet walnut" --id-base 780000400` |
| swipe-fast-1427 | `--count 1427 --batch 50 --every 1.6 --duration 0.6 --name "Pogo swipe" --batch-name "Velvet marble" --id-base 780000600` |
| tap-normal-1427 | `--count 1427 --batch 50 --tap 424 775 --screen-width 440 --screen-height 956 --every 1.2 --name "Pogo scan" --batch-name "Amber lantern" --id-base 780000000` |
| tap-normal-3-fr_FR | `--count 3 --batch 3 --locale fr_FR --tap 424 775 --screen-width 440 --screen-height 956 --every 1.2 --name "Pogo scan" --batch-name "Amber lantern" --id-base 780000000` |
| tap-fast-51 | `--count 51 --batch 50 --tap 424 775 --screen-width 440 --screen-height 956 --every 1.0 --name "Pogo fast scan" --batch-name "Silver compass" --id-base 780000200` |

To check them: generate each file and compare it with the decompressed fixture
(`python3 -c "import zlib,sys; sys.stdout.buffer.write(zlib.decompress(open(sys.argv[1],'rb').read(), -15))" <fixture>`); the files are byte
identical. The Swift output is compared structurally, not byte for byte.
