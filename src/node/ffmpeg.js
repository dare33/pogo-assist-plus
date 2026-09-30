// Find an ffmpeg binary without running Python or asking the user, in this order: --ffmpeg, the
// FFMPEG env var, PATH, then the places the usual installers put it. Everything that touches the
// machine (env, file checks, globbing, the -version probe) is injectable so tests never do.

import { existsSync, readdirSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, sep } from 'node:path';
import { spawnSync } from 'node:child_process';
import { naturalCompare } from '../extract/batch.js';

export const FFMPEG_NOT_FOUND = 'ffmpeg not found. Install it with "winget install Gyan.FFmpeg" (Windows) or "brew install ffmpeg" (Mac), or pass --ffmpeg <path> / set FFMPEG.';

/** Files matching a pattern whose segments may contain `*` (any characters) or be `**` (any depth). */
export function globFiles(pattern) {
  const parts = pattern.split(/[\\/]/);
  const out = [];
  const rx = (seg) => new RegExp(`^${seg.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*')}$`, 'i');
  const walk = (dir, i) => {
    if (i === parts.length) { out.push(dir); return; }
    const seg = parts[i];
    if (!seg.includes('*')) {
      const next = join(dir, seg);
      if (i === parts.length - 1) { if (existsSync(next)) out.push(next); } else walk(next, i + 1);
      return;
    }
    let names;
    try { names = readdirSync(dir === '' ? '.' : dir); } catch { return; }
    if (seg === '**') {
      walk(dir, i + 1);
      for (const n of names) { const p = join(dir, n); try { if (statSync(p).isDirectory()) walk(p, i); } catch { /* unreadable: skip */ } }
      return;
    }
    const re = rx(seg);
    for (const n of names) if (re.test(n)) walk(join(dir, n), i + 1);
  };
  // Absolute patterns start from the root ("/" or "C:\") rather than the working directory.
  if (parts[0] === '') walk(sep, 1);
  else if (/^[a-z]:$/i.test(parts[0])) walk(parts[0] + sep, 1);
  else walk('', 0);
  return out;
}

const probeVersion = (cmd) => spawnSync(cmd, ['-version'], { stdio: 'ignore' }).status === 0;

/** @returns { path, source } or null */
export function findFfmpeg({ explicit = null, env = process.env, platform = process.platform, exists = existsSync, glob = globFiles, probe = probeVersion } = {}) {
  if (explicit) {
    if (!exists(explicit)) throw new Error(`--ffmpeg is ${explicit} but no such file exists`);
    if (!probe(explicit)) throw new Error(`--ffmpeg is ${explicit}, which exists but does not run as ffmpeg ("-version" failed)`);
    return { path: explicit, source: '--ffmpeg' };
  }
  if (env.FFMPEG) {
    if (!exists(env.FFMPEG)) throw new Error(`FFMPEG is set to ${env.FFMPEG} but no such file exists`);
    if (!probe(env.FFMPEG)) throw new Error(`FFMPEG is set to ${env.FFMPEG}, which exists but does not run as ffmpeg ("-version" failed)`);
    return { path: env.FFMPEG, source: 'FFMPEG' };
  }
  for (const cmd of platform === 'win32' ? ['ffmpeg', 'ffmpeg.exe'] : ['ffmpeg']) if (probe(cmd)) return { path: 'ffmpeg', source: 'PATH' };

  // Known install locations: only files are checked; the one process started is the final probe.
  const candidates = [];
  const add = (source, pattern) => candidates.push({ source, pattern });
  if (platform === 'win32') {
    const local = env.LOCALAPPDATA, roaming = env.APPDATA;
    if (local) {
      add('winget', join(local, 'Microsoft', 'WinGet', 'Links', 'ffmpeg.exe'));
      add('winget', join(local, 'Microsoft', 'WinGet', 'Packages', 'Gyan.FFmpeg*', '**', 'bin', 'ffmpeg.exe'));
      add('imageio-ffmpeg', join(local, 'Programs', 'Python', 'Python*', 'Lib', 'site-packages', 'imageio_ffmpeg', 'binaries', 'ffmpeg-*.exe'));
    }
    if (roaming) add('imageio-ffmpeg', join(roaming, 'Python', 'Python*', 'site-packages', 'imageio_ffmpeg', 'binaries', 'ffmpeg-*.exe'));
  } else {
    const home = env.HOME ?? homedir();
    add('homebrew', '/opt/homebrew/bin/ffmpeg');
    add('system', '/usr/local/bin/ffmpeg');
    add('system', '/usr/bin/ffmpeg');
    add('imageio-ffmpeg', `${home}/.local/lib/python3*/site-packages/imageio_ffmpeg/binaries/ffmpeg-*`);
    add('imageio-ffmpeg', '/usr/lib/python3*/site-packages/imageio_ffmpeg/binaries/ffmpeg-*');
    add('homebrew', '/opt/homebrew/lib/python3*/site-packages/imageio_ffmpeg/binaries/ffmpeg-*');
  }
  for (const { source, pattern } of candidates) {
    const found = pattern.includes('*') ? glob(pattern) : (exists(pattern) ? [pattern] : []);
    // Highest version first (natural order, so Python312 beats Python39): the newest install is the most likely to work.
    for (const p of [...found].sort((x, y) => naturalCompare(y, x))) if (probe(p)) return { path: p, source };
  }
  return null;
}
