#!/usr/bin/env node
// Host I/O adapter. Parsing, checking, normalization, CBOR and integrity checks
// are implemented by the MoonBit package, including dependency traversal.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';

function originHeaders() {
  if (Object.hasOwn(process.env, 'DHALL_HEADERS')) {
    return {
      headerSource: process.env.DHALL_HEADERS,
      headerOrigin: pathToFileURL(path.resolve('__headers__.dhall')).href
    };
  }
  const config = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config');
  const filename = path.join(config, 'dhall', 'headers.dhall');
  try {
    const bytes = fs.readFileSync(filename);
    if (bytes.length > 262144) throw new Error('Origin header configuration exceeds 256 KiB');
    return { headerSource: new TextDecoder('utf-8', { fatal: true }).decode(bytes),
      headerOrigin: pathToFileURL(filename).href };
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    return { headerSource: '' };
  }
}

function saveSemanticCache(directory, entries) {
  if (!entries || Object.keys(entries).length === 0) return;
  try { fs.mkdirSync(directory, { recursive: true }); } catch { return; }
  for (const [digest, hex] of Object.entries(entries)) {
    if (!/^[0-9a-f]{64}$/.test(digest)) continue;
    const filename = path.join(directory, '1220' + digest);
    const temporary = filename + '.' + process.pid + '.tmp';
    try {
      fs.writeFileSync(temporary, Buffer.from(hex, 'hex'));
      fs.renameSync(temporary, filename);
    } catch {
      try { fs.unlinkSync(temporary); } catch { /* Optional cache write. */ }
    }
  }
}

function importRequest(key) {
  const [parent, written, metadata] = key.split('\n');
  if (!written) throw new Error('Invalid import request');
  const [mode, headers, digest] = metadata ? JSON.parse(metadata) : ['Code', [], null];
  return { parent, written, mode, headers, digest };
}

function unquotePath(written) {
  return written.split('/').map(segment => segment.startsWith('"') && segment.endsWith('"')
    ? segment.slice(1, -1) : segment).join('/');
}

function environmentName(written) {
  const name = written.slice(4);
  return name.startsWith('"') ? JSON.parse(name) : name;
}

async function fetchImport(location, headers) {
  const signal = AbortSignal.timeout(15000);
  const origin = new URL(location).origin;
  let current = location;
  for (let hop = 0; hop <= 5; hop++) {
    const response = await fetch(current, { headers, signal, redirect: 'manual' });
    if (![301, 302, 303, 307, 308].includes(response.status)) return response;
    const target = response.headers.get('location');
    await response.body?.cancel();
    if (!target) throw new Error('Redirect is missing a Location header');
    const next = new URL(target, current);
    if (next.origin !== origin || next.username || next.password) {
      throw new Error('Import redirect must stay on its original origin');
    }
    current = next.href;
  }
  throw new Error('Import redirect limit exceeded');
}

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
  const semanticDir = path.join(process.env.XDG_CACHE_HOME || path.join(os.homedir(), '.cache'), 'dhall');
  let result;
  for (let iteration = 0; iteration < 256; iteration++) {
    const child = spawnSync(process.execPath, [bridge], { input: JSON.stringify(request), encoding: 'utf8', maxBuffer: 8 * 1024 * 1024, timeout: 30000 });
    if (child.error || child.status !== 0) throw new Error(child.error?.message || child.stderr || 'MoonBit engine failed');
    const response = JSON.parse(child.stdout);
    if (response.error) throw new Error(response.error);
    if (response.result !== undefined) {
      if (cacheDir) saveSemanticCache(semanticDir, response.cache);
      result = response.result;
      break;
    }
    if (typeof response.need !== 'string') throw new Error('Invalid engine response');
    const key = response.need;
    const { parent, written, mode, headers, digest } = importRequest(key);
    const isRemote = /^https?:/.test(parent);
    let location;
    const local = unquotePath(written);
    if (written === 'missing') {
      location = 'missing';
    } else if (written.startsWith('env:')) {
      if (isRemote && mode !== 'Location') throw new Error('Remote imports cannot access environment variables');
      location = 'env:' + environmentName(written);
    } else if (written.startsWith('~/')) {
      if (isRemote && mode !== 'Location') throw new Error('Remote imports cannot access home files');
      location = pathToFileURL(path.join(os.homedir(), local.slice(2))).href;
    } else if (/^https?:/.test(written) || (isRemote && !written.startsWith('/'))) {
      location = new URL(written, parent).href;
    } else {
      if (isRemote && mode !== 'Location') throw new Error('Remote imports cannot access local resources');
      const base = parent.startsWith('file:') ? path.dirname(fileURLToPath(parent)) : process.cwd();
      location = pathToFileURL(path.resolve(base, local)).href;
    }
    if (mode === 'Location') {
      let display = location;
      if (location.startsWith('env:')) display = location.slice(4);
      if (location.startsWith('file:')) {
        const file = fileURLToPath(location);
        if (written.startsWith('~/')) display = '~/' + path.relative(os.homedir(), file).split(path.sep).join('/');
        else if (written.startsWith('/')) display = file.split(path.sep).join('/');
        else {
          const relative = path.relative(process.cwd(), file).split(path.sep).join('/');
          display = relative.startsWith('../') ? relative : './' + relative;
        }
      }
      request.sources.push({ key, location: display, source: null });
      continue;
    }
    if (cacheDir && digest && /^[0-9a-f]{64}$/.test(digest)) {
      try {
        const binary = fs.readFileSync(path.join(semanticDir, '1220' + digest));
        if (binary.length <= 1048576 && createHash('sha256').update(binary).digest('hex') === digest) {
          request.sources.push({ key, location: 'semantic-cache', source: binary.toString('hex') });
          continue;
        }
      } catch { /* A cache miss falls through to the original resource. */ }
    }
    if (/^https?:/.test(location) && !Object.hasOwn(request, 'headerSource')) {
      Object.assign(request, originHeaders());
      if (request.headerSource) continue;
    }
    const decodeResource = bytes => mode === 'Bytes' ? bytes.toString('hex')
      : new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
    let source = null;
    try {
      if (location.startsWith('env:')) {
        const value = process.env[location.slice(4)];
        source = value === undefined ? null : decodeResource(Buffer.from(value));
      } else if (location.startsWith('file:')) {
        const bytes = fs.readFileSync(fileURLToPath(location));
        if (bytes.length > 262144) throw new Error('Import exceeds 256 KiB');
        source = decodeResource(bytes);
      } else if (/^https?:/.test(location)) {
        const cacheFile = cacheDir && headers.length === 0 && path.join(cacheDir, createHash('sha256').update(mode === 'Bytes' ? 'bytes:' + location : location).digest('hex') + '.json');
        if (cacheFile && fs.existsSync(cacheFile)) {
          const cached = JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
          if (cached.url === location && typeof cached.source === 'string') {
            if (isRemote && new URL(parent).origin !== new URL(location).origin) {
              if (cached.cors !== '*' && cached.cors !== new URL(parent).origin) throw new Error('Cached cross-origin import denied by CORS');
            }
            source = cached.source;
            location = cached.effectiveUrl || location;
          }
        }
        if (source === null) {
          if (offline) throw new Error('Remote import is unavailable in offline cache');
          const response = await fetchImport(location, headers);
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
          source = decodeResource(Buffer.concat(chunks));
          if (cacheFile) {
            fs.mkdirSync(cacheDir, { recursive: true });
            const temporary = cacheFile + '.' + process.pid + '.tmp';
            fs.writeFileSync(temporary, JSON.stringify({ url: location, effectiveUrl: response.url, source, cors: response.headers.get('access-control-allow-origin') }));
            fs.renameSync(temporary, cacheFile);
          }
          location = response.url || location;
        }
      } else throw new Error('Unsupported import scheme: ' + location);
      if (source !== null && Buffer.byteLength(source) > (mode === 'Bytes' ? 524288 : 262144)) throw new Error('Import exceeds 256 KiB');
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
