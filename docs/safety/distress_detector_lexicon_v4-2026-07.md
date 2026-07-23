# DistressDetector — Lexicon v4 (DRAFT for PI sign-off)

> **Status: DRAFT — applied to the detector for TESTING per Junyu's direction.**
> Supersedes `v3-2026-07`. All v3→v4 changes are itemised in the changelog
> below; decisions that need explicit clinical sign-off are marked **[PI]**.
> **D4 remains pending clinical sign-off before the pilot ships.**
>
> |                  |                                                        |
> | ---------------- | ------------------------------------------------------ |
> | Target source    | `lib/core/safety/distress_detector.dart`               |
> | Wordlist version | `v4-2026-07`                                            |
> | Base version     | `v3-2026-07` (detector commit `e982d4e`)               |
> | Generated        | 2026-07-22                                              |

## How matching works (unchanged)

Lower-cased **substring `contains`**, checked in order **acute → moderate →
low → none**; the first tier with any hit wins. No negation/sarcasm handling.
Routing: **acute** → full-screen crisis page (hotline / 999). **moderate** →
soft bottom sheet. **low** → pill only. **none** → nothing.

**Script-variant strategy.** Every 冇-based term is emitted in three
uniform-substitution forms (冇 / 沒 / 無); simplified 没 forms live in the 简体
sections. Matching is a flat substring check over the whole list, so script
organisation is presentational only. Over-generation is free: an unnatural
variant (e.g. `沒咗我會好啲`) is a substring that never occurs in real input,
so it cannot create false positives; it only costs list size.

---

## Changelog v3 → v4

### Approved decisions (reviewed 2026-07-22)

**D1 — hyperbole-prone bare ideation demoted.** `想死` moved acute → moderate —
everyday hyperbole (攰到想死 / 熱到想死 / 烦得想死了) was firing the crisis page.
`想死了` dropped entirely (contains `想死`, subsumed by the moderate entry).
Acute coverage replaced by `好想死` · `真係想死` · `真想死` · `真的想死`.
Trade-off accepted: a terse genuine "想死" now gets the soft sheet, not the
crisis page. Acute-first check order still routes `真係想死` etc. to acute even
though they contain the moderate term `想死`.

**D2 — bare `跳樓` removed** (collides with 跳樓價 / 跳樓大減價). Replaced by
`想跳樓` / `想跳楼`. `跳樓自殺` not added (contains `自殺`, already acute).

**D3 — harm-to-others narrowed to first-person forms.** `殺死佢`/`殺咗佢`/`杀死他`/
`想殺死`/`想杀死` replaced by `我想殺死`/`我想殺咗`/`我想杀死`/`我想杀了` (+
`我想傷害佢`/`我想伤害他`/`我想弄死`); English `kill him/her/them/someone`
replaced by `want to kill …`. Motivation: drama-plot discussion fired acute.
**Side-effect fixed:** removing `kill him` dropped third-party disclosure
"he wants to kill himself"; explicit `kill himself`/`kill herself` added.
**[PI] Open protocol question:** harm-to-others currently routes to the
*suicide* crisis surface (hotline / 999). Verify this matches the Phase A HREC
protocol's handling of harm-to-others disclosures.

**D4 — hopelessness construct unified at moderate. [PI — needs clinical sign-off.]**
`冇晒希望` and `没有希望` demoted acute → moderate, joining `絕望`/`绝望`/
`hopeless`, so escalation no longer depends on the user's language/script. NOT
changed: `冇得救` stays acute; the `冇人需要我`(acute) vs `冇人愛我`(moderate)
split kept. Reviewer may prefer option B (unify at acute, fail-safe).

**D5 — literal-departure grief terms removed.** `走咗`/`剛走`/`刚走`/`lost him`/
`lost her` removed (巴士走咗 / lost her keys fired the sheet). Replaced by
bereavement-specific `老伴走咗`/`老伴走了`/`lost my husband`/`lost my wife`.
Accepted recall loss: a bare euphemistic "佢舊年走咗" now falls to *none*.
`失去咗` kept (matches 失去咗份工 — judged acceptable for a distress detector).

**D6 — self-harm / NSSI coverage added at acute** (was zero): `自殘`/`自残`/
`傷害自己`/`伤害自己`/`𠝹手`/`self harm`/`self-harm`/`hurt myself`/`cut myself`
(+ inflections).

### Mechanical changes (recall-side, no policy content)

- 冇 → 沒 / 無 uniform-substitution variants for every 冇-based term (formal
  traditional users type 無, e.g. `無人需要我`).
- Simplified mirrors added: `想跳楼`/`烧炭`/`没路可走`/`没有后路`/`活下去没意思`/
  `生存没有意义`/`我没价值`/`没存在价值`/`负担`.
- Traditional mirrors of new Mandarin ideation: `唔想活`/`活唔落去`/`諗唔開`.
- High-frequency Mandarin ideation: `不想活`/`活不下去`/`想不开`.
- `燒炭`/`烧炭` added (salient HK-specific method). Recommend validating the
  method-term set against HKU CSRP method distributions.
- v3 gap #2 synonyms: `負擔`/`负担`/`都唔理我`/`都唔關心我`/`lost my husband`/wife.
- v3 gap #3 synonyms: `寂寞`/`低落`/`冇咩心機` (+variants).
- Redundancy removed (same-tier containment): `想自殺`/`想自杀` (⊃ `自殺`/`自杀`);
  `我冇存在價值` (⊃ `冇存在價值`); `i'm a burden` (⊃ `burden`); `想死了` folded
  into `想死`.
- EN typing/STT variants: `im worthless`/`cant go on`/`can not go on`/
  `dont want to live`/`cant cope`/`if im dead`.

### Bug fixes beyond the six decisions

- **`reason to live`/`will to live` removed from acute** — bare positive phrases
  ("she gives me a reason to live" fired the crisis page). Replaced by
  `no will to live`/`lost my will to live`/`lost the will to live`;
  `no reason to live` is the sole reason-phrase.

## Residual known false positives (accepted, monitor in Phase A logs)

| Input | Fires | Why accepted |
| --- | --- | --- |
| 熱到想死 / 攰到想死 / 我想死你了 | moderate (`想死`) | D1 demoted, not deleted; sheet is dismissible |
| 呢個app冇用 / 这个没用 | moderate (`冇用`/`没用`) | v3-existing; object-referent ambiguity |
| 燒炭爐 / BBQ | acute (`燒炭`) | rare in chat; fail-safe |
| 唔小心𠝹手 | acute (`𠝹手`) | rare; fail-safe. 𠝹 often typed as 界 — not covered |
| 失去咗份工 | moderate (`失去咗`) | job loss ≈ legitimate distress signal |
| 唔想再生仔 | acute (`唔想再生`) | v3 ambiguity retained |

## Corpus additions required before ship

The synthetic corpus is 冇-based and has **no precision (negative) set**. Add:
- **Positive:** 沒/無/没 variants; `燒炭`; `諗唔開`; `活不下去`; the self-harm set;
  third-party disclosure ("佢話想跳樓", "he wants to kill himself").
- **Negative (must NOT fire acute):** `跳樓大減價` · `我想死你了` · `熱到想死` ·
  `巴士走咗` · `lost her keys` · `套劇個兇手殺死佢` · `無綫電視` ·
  `she gives me a reason to live`.
- **Precision metric:** run offline over Phase A benign transcripts; report
  per-tier trigger rate + hand-judged FP rate.

## Implementation notes

1. D4 explicitly pending PI clinical sign-off before pilot ship.
2. Follow-up (separately safety-gated): normalise input before matching —
   map 沒/無/没 → 冇 and 着 → 著 — then collapse the variant expansion to
   canonical forms. Closes the two-variant-slot combinations explicit
   expansion doesn't enumerate.
3. Tier checks stay acute-first (several acute terms contain moderate terms,
   e.g. `真係想死` ⊃ `想死`).

## Expected `flutter test` results under v4 (corpus updated in same commit)

Two corpus items were relabelled to match approved v4 policy:
`我想死` acute→moderate (D1) and `我已經冇晒希望。` acute→moderate (D4).

Expected printed misses (intentional, NOT regressions):
- **acute 49/50 (0.98 ≥ 0.95 ✓)** — miss: `I don't see a reason to live.`
  The v4 removal of the bare positive `reason to live` (correct fix) leaves
  this indirect phrasing uncovered; only `no reason to live` remains. Kept
  acute-labelled on purpose so the gap stays visible. Candidate fix for v5:
  add `see a reason to live`-negations or `don't see a reason`.
- **moderate ≈50/52 (0.96 ≥ 0.80 ✓)** — misses: `我嘅老朋友剛走，諗起就喊。`
  and `屋企空咗，自從佢走咗之後。` — the D5 accepted recall loss (bare
  euphemistic 走咗/剛走 removed for precision; bereavement-specific forms
  remain). Kept moderate-labelled so the accepted loss stays measured.
- **none precision 40/40 (1.00 ✓)** — no v4 term fires on the benign set.
