#!/usr/bin/env node
// Host I/O adapter. Parsing, checking, normalization, CBOR and integrity checks
// are implemented by the MoonBit package, including dependency traversal.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const bridge = path.join(root, '_build/js/debug/build/cmd/bridge/bridge.js');
const usage = [
'MoonDhall',
'Usage: node scripts/moondhall.mjs <json|check|normalize|format|hash|encode|decode>',
'       [FILE|-|--expression TEXT] [-o FILE] [--offline] [--cache-dir DIR]',
'Examples:',
'  node scripts/moondhall.mjs json examples/services/config.dhall',
'  node scripts/moondhall.mjs check --expression "Some 1"',
'encode writes raw CBOR; decode reads raw CBOR. Other commands use UTF-8.',
'Build first: moon build --target js'].join('\n');
const operations = new Set(['json', 'check', 'normalize', 'format', 'hash', 'encode', 'decode']);
const args = process.argv.slice(2);
if (args.length === 0 || args.includes('--help')) { console.log(usage); process.exit(0); }
if (args[0] === '--version') { console.log('MoonDhall 0.1.0-dev'); process.exit(0); }
const op = args.shift();
let file = null, expression = null, output = null, offline = false;
let cacheDir = path.join(os.homedir(), '.cache', 'moondhall', 'imports');
function argument(flag) {
  if (!args.length) throw new Error('Missing value for ' + flag);
  return args.shift();
}
try {
  if (!operations.has(op)) throw new Error('Unknown command: ' + op);
  while (args.length) {
    const a = args.shift();
    if (a === '-e' || a === '--expression') expression = argument(a);
    else if (a === '-o' || a === '--output') output = argument(a);
    else if (a === '--offline') offline = true;
    else if (a === '--cache-dir') cacheDir = path.resolve(argument(a));
    else if (a === '--no-cache') cacheDir = null;
    else if (a.startsWith('-') && a !== '-') throw new Error('Unknown option: ' + a);
    else if (file !== null) throw new Error('Expected one input file');
    else file = a;
  }
  if (file !== null && expression !== null) throw new Error('Choose a file or --expression');
  if (!fs.existsSync(bridge)) throw new Error('Build first: moon build --target js');
  const origin = pathToFileURL(path.resolve(file && file !== '-' ? file : '__stdin__.dhall')).href;
  const raw = expression !== null ? Buffer.from(expression) : fs.readFileSync(file && file !== '-' ? file : 0);
  if (raw.length > 1048576) throw new Error('Input exceeds 1 MiB');
  const request = { op, origin, source: op === 'decode' ? raw.toString('hex') : new TextDecoder('utf-8', { fatal: true }).decode(raw), sources: [] };
  let result;
  for (let iteration = 0; iteration < 256; iteration++) {
    const child = spawnSync(process.execPath, [bridge], { input: JSON.stringify(request), encoding: 'utf8', maxBuffer: 8 * 1024 * 1024, timeout: 30000 });
    if (child.error || child.status !== 0) throw new Error(child.error?.message || child.stderr || 'MoonBit engine failed');
    const response = JSON.parse(child.stdout);
    if (response.error) throw new Error(response.error);
    if (response.result !== undefined) { result = response.result; break; }
    if (typeof response.need !== 'string') throw new Error('Invalid engine response');
    const key = response.need;
    const separator = key.indexOf('\n');
    if (separator < 0) throw new Error('Invalid import request');
    const parent = key.slice(0, separator), written = key.slice(separator + 1);
    const isRemote = /^https?:/.test(parent);
    let location;
    if (written.startsWith('env:')) {
      if (isRemote) throw new Error('Remote imports cannot access environment variables');
      location = written;
    } else if (written.startsWith('~/')) {
      if (isRemote) throw new Error('Remote imports cannot access home files');
      location = pathToFileURL(path.join(os.homedir(), written.slice(2))).href;
    } else {
      location = new URL(written, parent).href;
      if (isRemote && !/^https?:/.test(location)) throw new Error('Remote imports cannot access local resources');
    }
    let source = null;
    try {
      if (location.startsWith('env:')) {
        source = process.env[location.slice(4)] ?? null;
      } else if (location.startsWith('file:')) {
        const bytes = fs.readFileSync(fileURLToPath(location));
        if (bytes.length > 262144) throw new Error('Import exceeds 256 KiB');
        source = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
      } else if (/^https?:/.test(location)) {
        const cacheFile = cacheDir && path.join(cacheDir, createHash('sha256').update(location).digest('hex') + '.json');
        if (cacheFile && fs.existsSync(cacheFile)) {
          const cached = JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
          if (cached.url === location && typeof cached.source === 'string') {
            if (isRemote && new URL(parent).origin !== new URL(location).origin) {
              if (cached.cors !== '*' && cached.cors !== new URL(parent).origin) throw new Error('Cached cross-origin import denied by CORS');
            }
            source = cached.source;
          }
        }
        if (source === null) {
          if (offline) throw new Error('Remote import is unavailable in offline cache');
          const response = await fetch(location, { signal: AbortSignal.timeout(15000), redirect: 'error' });
          if (!response.ok) throw new Error('HTTP ' + response.status);
          if (isRemote && new URL(parent).origin !== new URL(location).origin) {
            const allowed = response.headers.get('access-control-allow-origin');
            if (allowed !== '*' && allowed !== new URL(parent).origin) throw new Error('Cross-origin import denied by CORS');
          }
          const reader = response.body.getReader();
          const chunks = []; let length = 0;
          while (true) {
            const { value, done } = await reader.read();
            if (done) break;
            length += value.length;
            if (length > 262144) { await reader.cancel(); throw new Error('Import exceeds 256 KiB'); }
            chunks.push(value);
          }
          source = new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks));
          if (cacheFile) {
            fs.mkdirSync(cacheDir, { recursive: true });
            const temporary = cacheFile + '.' + process.pid + '.tmp';
            fs.writeFileSync(temporary, JSON.stringify({ url: location, source, cors: response.headers.get('access-control-allow-origin') }));
            fs.renameSync(temporary, cacheFile);
          }
        }
      } else throw new Error('Unsupported import scheme: ' + location);
      if (source !== null && Buffer.byteLength(source) > 262144) throw new Error('Import exceeds 256 KiB');
    } catch { source = null; }
    request.sources.push({ key, location, source });
  }
  if (result === undefined) throw new Error('Import request limit exceeded');
  const bytes = op === 'encode' ? Buffer.from(result, 'hex') : Buffer.from(result + '\n');
  if (output) fs.writeFileSync(output, bytes);
  else process.stdout.write(bytes);
} catch (error) {
  process.stderr.write(error.message + '\n');
  process.exitCode = 1;
}
