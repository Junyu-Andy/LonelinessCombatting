# DistressDetector — Classification Performance v1.0

> **Purpose.** Archival record of the rule-based distress classifier's
> recall/precision on the synthetic validation corpus, for the dissertation
> methods appendix and the HREC safety file. Regenerate this document
> whenever the wordlist or corpus changes and bump the version.

## Provenance

| Field | Value |
|---|---|
| Generated | 2026-07-21 |
| Detector source | `lib/core/safety/distress_detector.dart` |
| Wordlist version | `v3-2026-07` |
| Detector commit | `e982d4e9f8f24fba6cfbc437c2863827d4c60e3c` ("Safety lexicon v3: worthlessness + harm-to-others") |
| Corpus source | `test/distress_corpus_test.dart` (`_corpus`) |
| Repo HEAD at generation | `f215f86bc1b53a1a650c0beefdbd3bbb1266cc30` |

## Classifier mechanism

Deterministic, **rule-based keyword substring matching** — no LLM, no ML,
no negation/sarcasm handling. `analyze(text)` lower-cases the input and
returns the **first** tier whose wordlist has any substring hit, checked in
order **acute → moderate → low → none**. Identical in Arm A and Arm B (safety
equivalence requirement). Tuning policy: acute optimises for recall (a false
negative is the unsafe outcome); moderate balances recall/precision; low is
precision-leaning and never escalates.

Because matching is pure substring `contains`, there is **no rule that can
mis-consume or cancel a match** — every miss below is a **wordlist coverage
gap** (missing synonym) or **implicit phrasing with no keyword at all**, not a
negation/sarcasm mis-fire.

## Corpus

Synthetic, engineering-authored, written to exercise the keyword surface.
**Not** the co-design corpus — the pilot-launch criterion (per the test file
header) is to supplement these with ≥200 annotated real utterances plus a
cultural-advisor review pass.

| Tier (ground truth) | N |
|---|---|
| none | 40 |
| low | 50 |
| moderate | 50 |
| acute | 50 |
| **Total** | **190** |

Annotation: single-annotator (engineering team), band assigned by the intended
keyword category. No inter-rater reliability computed at v1.0 (a limitation to
resolve with the co-design corpus).

## Results

| Tier | Metric | Value | Threshold (P5.4) | Pass |
|---|---|---|---|---|
| acute | recall | **1.000** (50/50) | ≥ 0.95 | ✅ |
| moderate | recall | **0.920** (46/50) | ≥ 0.80 | ✅ |
| low | recall | **0.700** (35/50) | — (no threshold) | — |
| none | precision¹ | **1.000** (40/40) | ≥ 0.90 | ✅ |

¹ "none precision" here = none-labelled items correctly left as none / all
none-labelled items (i.e. no false escalation on routine text). No routine
utterance was over-triggered.

### Confusion matrix (rows = ground truth, columns = predicted)

| ground truth ↓ | none | low | moderate | acute |
|---|---|---|---|---|
| **none** (40) | 40 | 0 | 0 | 0 |
| **low** (50) | 15 | 35 | 0 | 0 |
| **moderate** (50) | 4 | 0 | 46 | 0 |
| **acute** (50) | 0 | 0 | 0 | 50 |

## Misses (unsafe direction) — for human safety review

### moderate → none (4) — a distress cue was not surfaced

| # | Utterance | Why missed |
|---|---|---|
| 1 | `I lost my husband three weeks ago. Everything is heavy.` | Loss phrased as "lost my husband"; lexicon has `lost him`/`lost her`/`passed away`/`grieving` but not this form. |
| 2 | `我屋企人都唔關心我。` | Lexicon has `冇人關心` (no one cares); does not cover `都唔關心我` (they don't care about me). |
| 3 | `連阿仔阿女都唔理我。` | Lexicon has `冇人理我`; does not cover `都唔理我` (they ignore me). |
| 4 | `我覺得自己係個負擔，唔該人哋。` | Lexicon has `負累`/`拖累`/`累贅` but **not `負擔`** — a very common burden synonym. |

All four fall to `none` (not `low`) because they contain no low-tier keyword
either. None are safety-critical (acute) — moderate routes to a soft support
sheet, not the crisis surface.

### low → none (15) — representative sample of 5

| Utterance | Why missed |
|---|---|
| `成日諗起阿婆，覺得寂寞。` | `寂寞` (lonely) is not in the lexicon (has `孤獨`/`孤單`). |
| `心情有少少低落。` | `低落` (low mood) not covered (has `失落`/`心情差`). |
| `呢排冇咩心機。` | `冇咩心機` — the infix `咩` breaks the exact substring `冇心機`. |
| `I miss having someone around in the evenings.` | Implicit loneliness, no keyword ("miss having someone around"). |
| `呢排心情真係唔多好。` | Indirect (`心情唔多好` vs the literal `心情差`). |

Two failure modes across all 15: (a) **missing synonyms** (`寂寞`, `低落`,
`負擔`), and (b) **implicit/figurative phrasing** with no keyword (staring out
the window, quiet house at night, haven't laughed in a long time). Type (b)
cannot be caught by keyword additions without material precision cost.

## Path to moderate recall ≥ 0.95 — options & trade-off (not yet applied)

Current moderate recall 0.920 (4 misses of 50). To reach ≥ 0.95 requires
fixing ≥ 2 of the 4 misses (48/50 = 0.96).

- **Add the safe synonym gaps** — `負擔` (moderate), and `都唔關心我` /
  `都唔理我` (or the looser `唔關心我` / `唔理我`). On *this* corpus this
  lifts moderate recall to 0.96–1.00 with **zero** change to `none` precision
  (no none-labelled item contains these strings).
- **Cost / caveat.** The corpus is small (50/band) and self-authored, so
  hitting 0.95 by inserting the exact missing strings is **overfitting the
  synthetic set** — it inflates the metric without evidence of real-world
  recall. The looser forms (`唔關心`, `唔理`) carry real-world false-positive
  risk (e.g. "我唔關心呢啲小事") that this corpus cannot measure.
- **Recommendation.** (1) Add the unambiguous, high-value synonyms that
  *should* have been covered anyway — `負擔`, `寂寞`, `低落` — as fail-safe
  additions. (2) Treat the formal 0.95 target as **pending the co-design
  corpus**, not the synthetic one. (3) Note that the safety-critical tier
  (acute) is already 1.000; moderate/low misses degrade to a softer surface or
  none, not to a missed crisis. Any wordlist change is safety-gated and needs
  PI sign-off.

## Change log

| Version | Date | Detector wordlist | Notes |
|---|---|---|---|
| v1.0 | 2026-07-21 | `v3-2026-07` | First archived run. acute 1.00 / moderate 0.92 / low 0.70 / none-precision 1.00 on the 190-item synthetic corpus. |
