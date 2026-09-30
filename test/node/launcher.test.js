// The Windows launcher, run through cmd.exe. `shift` in a batch file also shifts %0, so a launcher
// that reads its own folder after shifting fails with MODULE_NOT_FOUND on every argument-driven
// launch (drag and drop, command line). A nonexistent folder makes the script fail fast, with its
// own message, so no clip, ffmpeg or OCR is involved.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const launcher = fileURLToPath(new URL('../../extract-box.cmd', import.meta.url));

test('extract-box.cmd reaches scripts/extract-box.mjs when given arguments', { skip: process.platform !== 'win32' && 'Windows only' }, () => {
  const missing = join(fileURLToPath(new URL('../../', import.meta.url)), 'scratch', 'no such folder & (x)');
  // Empty stdin so the launcher's final `pause` returns; the empty argument and --force must
  // survive the argument loop and reach the script.
  const r = spawnSync(process.env.ComSpec ?? 'cmd.exe', ['/d', '/c', `""${launcher}" "${missing}" "" --force"`], { encoding: 'utf8', input: '', windowsVerbatimArguments: true });
  const out = `${r.stdout}${r.stderr}`;
  assert.doesNotMatch(out, /MODULE_NOT_FOUND|Cannot find module/);
  assert.match(out, /is not a folder\./);
  assert.match(out, /no such folder/);
});
