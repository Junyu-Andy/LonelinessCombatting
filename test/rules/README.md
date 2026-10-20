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

`randomization_rules.test.js` (T19, decision 0029) — the allocation
collections (`randomization_sequences`, `randomization_state`,
`enrollments`, `arm_assignment_log`, `llm_denied_log`,
`meta/randomization_config`) and the retired `meta/arm_counter`: no client
(participant, blinded, unblinded, anonymous) reads or writes them; the
participant cannot set `w0Date` or the other assignment fields.
(`arm_counter.test.js` was removed with the minimisation counter.)

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

`reminiscence_chapter_rules.test.js` — 1020d 小篇章
(`users/{uid}/reminiscence_chapters/week_{N}`): the owner reads it and writes
only the client fields; `status` only to `requested` (hybrid, with a new
`requestId`) or `ready` (rule, with `ruleText` and `version`); the server
fields (`finalText`, `flags`, `generatedAt`, `deletedSentences`,
`failReason`, the hybrid `version`, status `generating` / `failed`) and the
`runs/` archive are never client-writable; no deletes; the enrolment gate
applies.  `reminiscence_v2` and `reminiscence_chapter_ratings` stay under
the generic owner rule.
