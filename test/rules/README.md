# Firestore security-rules tests

These test `firestore.rules` directly against the Firestore emulator — the
thing `flutter test` cannot reach. They exist to catch **silent rule
failures** (e.g. the bare map-key bug that could deny legitimate
`meta/arm_counter` writes).

## Run

Requires the Firebase CLI and Java (for the emulator).

```bash
firebase emulators:exec --only firestore --project loneliness-pilot-dev \
  "cd test/rules && npm install && npm test"
```

The emulator loads `firestore.rules` from the repo root; the tests seed data
with rules disabled, then assert allow/deny for each write shape.

## What's covered

`arm_counter.test.js` — the stratified RCT arm-balance counter invariant:
- unauthenticated write → denied
- first-ever write (empty counter) → allowed  *(bare-key-bug regression)*
- first write into an empty cell → allowed
- single valid +1 in one cell → allowed
- two cells changed at once → denied
- a count decreasing → denied
- an increment > +1 → denied
