// T10 / decision 0024: the server's copy of the App lexicon gives the
// same answer as the App on the shared cases (the Dart side runs the same
// file in test/safety_lexicon_export_test.dart).
"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const lex = require("../safety_lexicon");

const cases = JSON.parse(fs.readFileSync(path.join(__dirname,
    "../../test/fixtures/safety_lexicon_cases.json"), "utf8")).cases;
for (const c of cases) {
  const m = lex.analyze(c.text);
  assert.strictEqual(m.tier, c.tier, c.text);
  assert.strictEqual(m.term, c.term, c.text);
}
assert.ok(lex.TERMS.length > 200, "lexicon loaded");
assert.strictEqual(lex.TERMS[0].tier, "acute", "check order starts acute");
assert.ok(/^v\d/.test(lex.WORDLIST_VERSION));
assert.ok(lex.isEscalation("老伴走咗"));
assert.ok(!lex.isEscalation("我好孤獨"), "low tier is not an escalation");
console.log(`safety_lexicon_test: ${cases.length} shared cases ok`);
