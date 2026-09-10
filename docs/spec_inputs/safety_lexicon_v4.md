# Spec input — safety lexicon `v4-2026-07` (full term inventory)

> **GENERATED FILE — do not edit by hand.**
> Produced by `tool/export_spec_inputs.py` from:
>   - `lib/core/safety/distress_detector.dart` — the terms, source of truth
>   - `docs/safety/distress_detector_lexicon_v4-2026-07.md` — the v3→v4 policy record
>
> Source commit `c80a2ab` · exported 2026-09-10.
> Edit the sources and re-run the exporter; edits made here are lost
> and, worse, make the spec disagree with what actually ships.

The policy narrative — why each v3→v4 change was made, which are approved and
which are not — lives in `docs/safety/distress_detector_lexicon_v4-2026-07.md`
and is **not** duplicated here. This file is the enumerated list, so the spec
can state coverage without anyone retyping 269 terms.

## Matching semantics

- Input lower-cased, then plain **substring `contains`**. No tokenisation, no
  word boundaries, no negation or sarcasm handling, no normalisation of
  script variants at match time.
- Tiers are checked **acute → moderate → low → none**; first tier with any hit
  wins. This order is load-bearing: several acute terms contain moderate terms
  (`真係想死` ⊃ `想死`), and reversing the order would silently downgrade them.
- Only the *first* matched term is recorded (`DistressMatch.matchedTerm`), for
  analytics and audit. It is never shown to the participant.
- Deterministic and identical in both arms, by design — safety equivalence
  between Arm A and Arm B requires the trigger not to depend on the LLM.
- 冇-based terms are explicitly enumerated in three script forms (冇 / 沒 / 無),
  with 没 forms in the simplified sections. Over-generation is deliberate: an
  unnatural variant is a substring that never occurs, so it costs list size,
  not precision.

## Tier sizes

| Tier | Terms | Routing |
| --- | --- | --- |
| acute | 160 | full-screen crisis page (hotline / 999); LLM call short-circuited; research team notified within 24 h |
| moderate | 67 | soft bottom sheet after the reply; flagged for weekly research review |
| low | 42 | pill only; copy may soften; no escalation |
| none | — | nothing |

## Open items that block a final spec

1. **D4 — hopelessness tier is not signed off.** `冇晒希望` / `没有希望` were
   demoted acute → moderate so escalation does not depend on which script the
   participant types. This is applied in code *for testing*, pending PI
   clinical sign-off, and the reviewer may instead choose option B (unify at
   acute, fail-safe). The spec cannot state a final hopelessness rule until
   that comes back. Everything downstream of it — expected acute recall,
   crisis-page trigger rate — moves with the decision.
2. **D3 — harm-to-others routes to the suicide crisis surface.** First-person
   harm-to-others terms currently open the same hotline / 999 page as suicidal
   ideation. Whether that matches the Phase A HREC protocol's handling of
   harm-to-others disclosure is unverified.
3. **No precision (negative) set in the corpus.** Recall is measured; the
   false-positive rate is not. The required negative set is listed in the
   policy doc under "Corpus additions required before ship".
4. **Accepted residual false positives** (also in the policy doc): `熱到想死`
   → moderate, `燒炭爐` → acute, `失去咗份工` → moderate, `唔小心𠝹手` → acute.
   These are deliberate fail-safe choices, not bugs, and the spec should say so
   explicitly rather than leave a reviewer to rediscover them.

---

## Full term inventory

### Acute — 160 terms

Self-harm / suicidal ideation. Optimised for recall — a false negative is the unsafe outcome.

**EN — ideation** (26)

- `kill myself`
- `end my life`
- `end it all`
- `suicide`
- `want to die`
- `better off dead`
- `no point living`
- `no reason to live`
- `no will to live`
- `lost my will to live`
- `lost the will to live`
- `can't go on`
- `cant go on`
- `cannot go on`
- `can not go on`
- `don't want to live`
- `dont want to live`
- `rather be dead`
- `take my own life`
- `taking my own life`
- `no way out`
- `only way out`
- `if i'm dead`
- `if im dead`
- `kill himself`
- `kill herself`

**EN — worthlessness** (7)

- `i'm worthless`
- `i am worthless`
- `im worthless`
- `i have no worth`
- `no reason to exist`
- `nobody needs me`
- `no one needs me`

**EN — self-harm (v4)** (7)

- `self harm`
- `self-harm`
- `harm myself`
- `hurt myself`
- `hurting myself`
- `cut myself`
- `cutting myself`

**EN — harm-to-others** (5)

- `want to kill someone`
- `want to kill him`
- `want to kill her`
- `want to kill them`
- `want to hurt someone`

**繁體/粵語 — ideation** (54)

- `自殺`
- `好想死`
- `真係想死`
- `真想死`
- `結束自己`
- `結束我嘅生命`
- `了結自己`
- `了結生命`
- `想跳樓`
- `上吊`
- `燒炭`
- `冇咗我會好啲`
- `沒咗我會好啲`
- `無咗我會好啲`
- `冇咗我會好過`
- `沒咗我會好過`
- `無咗我會好過`
- `冇我嘅世界`
- `沒我嘅世界`
- `無我嘅世界`
- `想消失`
- `消失咗就好`
- `冇我會好過`
- `沒我會好過`
- `無我會好過`
- `冇我會好啲`
- `沒我會好啲`
- `無我會好啲`
- `冇得救`
- `沒得救`
- `無得救`
- `冇路可走`
- `沒路可走`
- `無路可走`
- `冇後路`
- `沒後路`
- `無後路`
- `唔想再生`
- `不如死咗`
- `再活落去都冇意思`
- `再活落去都沒意思`
- `再活落去都無意思`
- `活落去冇意思`
- `活落去沒意思`
- `活落去無意思`
- `生存冇意義`
- `生存沒意義`
- `生存無意義`
- `生存冇意思`
- `生存沒意思`
- `生存無意思`
- `唔想活`
- `活唔落去`
- `諗唔開`

**繁體/粵語 — worthlessness** (17)

- `活著冇價值`
- `活著沒價值`
- `活著無價值`
- `生存冇價值`
- `生存沒價值`
- `生存無價值`
- `我冇價值`
- `我沒價值`
- `我無價值`
- `冇存在價值`
- `沒存在價值`
- `無存在價值`
- `我係多餘`
- `我係廢人`
- `冇人需要我`
- `沒人需要我`
- `無人需要我`

**繁體/粵語 — self-harm (v4)** (3)

- `自殘`
- `傷害自己`
- `𠝹手`

**繁體/粵語 — harm-to-others** (6)

- `想殺人`
- `我想殺死`
- `我想殺咗`
- `想傷害人`
- `我想傷害佢`
- `我想弄死`

**简体 — ideation** (19)

- `自杀`
- `真的想死`
- `结束自己`
- `了结自己`
- `了结生命`
- `想跳楼`
- `烧炭`
- `没我会更好`
- `没得救`
- `没有出路`
- `没路可走`
- `没有后路`
- `不如死了`
- `没意思活下去`
- `活下去没意思`
- `不想活`
- `活不下去`
- `想不开`
- `生存没有意义`

**简体 — worthlessness** (9)

- `活着没价值`
- `生存没有价值`
- `我没有价值`
- `我没价值`
- `没有存在价值`
- `没存在价值`
- `我是多余的`
- `我是废人`
- `没人需要我`

**简体 — self-harm (v4)** (2)

- `自残`
- `伤害自己`

**简体 — harm-to-others** (5)

- `想杀人`
- `我想杀死`
- `我想杀了`
- `想伤害别人`
- `我想伤害他`

### Moderate — 67 terms

Hopelessness, burden cognitions, recent loss / grief. Balances recall and precision — over-triggering pesters.

**EN** (13)

- `hopeless`
- `burden`
- `nobody cares`
- `no one cares`
- `lost my husband`
- `lost my wife`
- `passed away`
- `just died`
- `grieving`
- `can't cope`
- `cant cope`
- `overwhelmed`
- `falling apart`

**繁體/粵語 — distress** (30)

- `冇用`
- `沒用`
- `無用`
- `冇人理我`
- `沒人理我`
- `無人理我`
- `冇人關心`
- `沒人關心`
- `無人關心`
- `冇人愛我`
- `沒人愛我`
- `無人愛我`
- `都唔理我`
- `都唔關心我`
- `拖累`
- `累贅`
- `負累`
- `負擔`
- `頂唔順`
- `撐唔住`
- `撐不住`
- `好辛苦`
- `辛苦到`
- `絕望`
- `冇晒希望`
- `沒晒希望`
- `無晒希望`
- `孤獨到痛`
- `崩潰`
- `崩到爆`

**繁體/粵語 — ideation-adjacent (D1: demoted from acute)** (1)

- `想死`

**繁體/粵語 — loss / grief** (8)

- `失去咗`
- `老伴走咗`
- `剛去世`
- `過咗身`
- `過世`
- `離世`
- `哀傷`
- `悲痛`

**简体** (15)

- `没用`
- `没人理`
- `没人关心`
- `没人爱我`
- `累赘`
- `负担`
- `撑不住`
- `顶不住`
- `绝望`
- `没有希望`
- `崩溃`
- `老伴走了`
- `刚去世`
- `过世`
- `离世`

### Low — 42 terms

Persistent loneliness, sadness, isolation. Precision-leaning; never escalates.

**EN** (8)

- `lonely`
- `alone`
- `isolated`
- `no one to talk to`
- `empty`
- `sad`
- `feeling low`
- `down today`

**繁體/粵語** (26)

- `孤獨`
- `孤單`
- `寂寞`
- `一個人`
- `冇人陪`
- `沒人陪`
- `無人陪`
- `空虛`
- `唔開心`
- `好悶`
- `悶悶哋`
- `冇心機`
- `沒心機`
- `無心機`
- `冇咩心機`
- `沒咩心機`
- `無咩心機`
- `冇神冇氣`
- `沒神沒氣`
- `無神無氣`
- `冇精神`
- `沒精神`
- `無精神`
- `失落`
- `低落`
- `心情差`

**简体** (8)

- `孤独`
- `孤单`
- `一个人`
- `没人陪`
- `空虚`
- `不开心`
- `没心情`
- `没精神`
