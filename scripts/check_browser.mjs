import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { loadPreview } from '../examples/browser/embed.mjs';

const wasm = await readFile(new URL(
  '../_build/wasm-gc/release/build/examples/browser/browser.wasm',
  import.meta.url,
));
const preview = await loadPreview(wasm);
const valid = preview('let port = 8080 in { port = port, name = "配置🌙", big = 9007199254740993 }');
assert.match(valid.type, /port : Natural/);
assert.match(valid.json, /9007199254740993/);
assert.equal(JSON.parse(valid.json).name, '配置🌙');
assert.equal(JSON.parse(valid.json).port, 8080);
assert.match(preview('let x = 1 in\nTrue + x').error, /^editor\.dhall:2:\d+:/);
assert.match(preview('{ port = }').error, /^editor\.dhall:1:\d+:/);
assert.deepEqual(preview('True'), { type: 'Bool', json: 'true' });
