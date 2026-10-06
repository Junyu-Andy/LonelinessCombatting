/**
 * Every DeepSeek request names `deepseek-flash` and turns thinking off
 * (decision record 0017).
 *
 * Run:  cd functions && node test/deepseek_request_test.js
 *
 * Static check on the source, so it needs no network, key or emulator.
 * `deepseek-flash` thinks by default; a call site that forgets
 * `thinking: DEEPSEEK_THINKING` would spend its max_tokens on reasoning and
 * return an empty reply, which no other test would catch.
 */

'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const index = fs.readFileSync(path.join(root, 'index.js'), 'utf8');

assert.ok(index.includes('const DEEPSEEK_MODEL = "deepseek-flash";'),
    'DEEPSEEK_MODEL should be deepseek-flash');
assert.ok(index.includes('const DEEPSEEK_THINKING = {type: "disabled"};'),
    'DEEPSEEK_THINKING should disable thinking');

// Each chat/completions call: the request body that follows the URL must
// use both constants.
const url = 'https://api.deepseek.com/chat/completions';
const calls = index.split(url).slice(1);
assert.ok(calls.length >= 3, `expected >= 3 DeepSeek calls, found ${calls.length}`);
calls.forEach((rest, i) => {
  const body = rest.slice(0, rest.indexOf('messages:'));
  assert.ok(body.includes('model: DEEPSEEK_MODEL,'),
      `call ${i + 1}: model is not DEEPSEEK_MODEL`);
  assert.ok(body.includes('thinking: DEEPSEEK_THINKING,'),
      `call ${i + 1}: thinking is not DEEPSEEK_THINKING`);
});

// No server code still asks for the legacy alias.
fs.readdirSync(root)
    .filter((f) => f.endsWith('.js'))
    .forEach((f) => {
      const src = fs.readFileSync(path.join(root, f), 'utf8');
      const code = src.split('\n').filter((l) => !l.trim().startsWith('//'));
      assert.ok(!code.join('\n').includes('"deepseek-chat"'),
          `${f} still requests "deepseek-chat"`);
    });

console.log(`deepseek_request_test: ${calls.length} DeepSeek calls OK`);
