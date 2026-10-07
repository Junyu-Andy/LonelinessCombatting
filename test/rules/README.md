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
- aCount and bCount of one cell raised together → denied

`memory_rules.test.js` — memory v1 (`users/{uid}/mem_*`): owner may read,
delete and confirm a pending sensitive fact, never create or edit; injection
and extraction logs are server-only.

`llm_calls_rules.test.js` — the C04 model log (`llm_calls`): no client may
read, create, overwrite or delete a row, the participant's own included.

`profile_arm.test.js` — the write-once `arm` on `users/{uid}`: signup create,
null backfill and merge-writes that omit `arm` → allowed; switching, nulling,
deleting or overwriting away an assigned arm → denied; subcollections stay
owner-only.

`ada_rules.test.js` — T17 Phase A ADA and day-7 open questions
(`users/{uid}/ada_responses`, `day7_open_responses`), short and full form
with synthetic data: the owner saves a draft per screen and submits once;
afterwards the doc is frozen; no client deletes; uid / timepoint / status
must match; other participants can't read or write.
