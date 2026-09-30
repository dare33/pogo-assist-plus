#!/usr/bin/env node
// A folder of screen-recording clips (one Pokémon GO box) in, one merged Poke Genie-layout CSV out.
//
//   node scripts/extract-box.mjs <folder>... [--account NAME] [--fps 5] [--order name|mtime]
//                                [--inbox DIR] [--out-dir DIR] [--ffmpeg PATH] [--force] [--quiet]
//
// The folder holds the clips of one account (.mp4, .mov, .m4v). If it holds none but its
// subfolders do, each subfolder is an account. A clip with "shadow" in its filename is the
// Shadow-filtered pass; "purified" likewise. Each clip's frame readings are cached beside it as
// <clip>.extract.json, so a re-run only reads clips that are new or changed, or all of them when
// the extractor itself changed. The logic is in src/node/box.js; see docs/whole-box.md.

import { runBox } from '../src/node/box.js';

process.exitCode = await runBox(process.argv.slice(2));
