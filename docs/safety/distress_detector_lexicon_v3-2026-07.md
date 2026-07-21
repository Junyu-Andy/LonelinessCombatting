# DistressDetector — Current Lexicon (review copy)

> **For safety review, not a spec.** This is the *current* keyword list exactly
> as it ships, so a reviewer can see coverage and spot gaps (script variants,
> synonyms) before deciding what to add. Any change is safety-gated and needs
> PI sign-off.
>
> | | |
> |---|---|
> | Source | `lib/core/safety/distress_detector.dart` |
> | Wordlist version | `v3-2026-07` |
> | Detector commit | `e982d4e` |
> | Generated | 2026-07-21 |

## How matching works

Lower-cased **substring `contains`**, checked in order **acute → moderate →
low → none**; the first tier with any hit wins. No negation/sarcasm handling —
a miss is always a coverage gap, never a mis-consumed match. Substrings are
deliberately specific (e.g. `結束自己`, not `結束`) to avoid benign triggers.

Routing: **acute** → full-screen crisis page (hotline / 999). **moderate** →
soft bottom sheet (breathing / reach someone / continue). **low** → pill only,
no interruption. **none** → nothing.

---

## ACUTE (55 terms) → crisis surface

**English — ideation**
`kill myself` · `end my life` · `end it all` · `suicide` · `want to die` ·
`better off dead` · `no point living` · `no reason to live` · `can't go on` ·
`cannot go on` · `don't want to live` · `rather be dead` · `take my own life` ·
`no way out` · `taking my own life` · `only way out` · `if i'm dead` ·
`reason to live` · `will to live`

**English — worthlessness (v3)**
`i'm worthless` · `i am worthless` · `i have no worth` · `no reason to exist` ·
`nobody needs me`

**English — harm-to-others (v3)**
`kill someone` · `kill him` · `kill her` · `kill them` · `want to hurt someone`

**繁體 / 粵語 — ideation**
`自殺` · `想死` · `想自殺` · `結束自己` · `結束我嘅生命` · `了結自己` ·
`了結生命` · `跳樓` · `上吊` · `冇咗我會好啲` · `冇咗我會好過` · `冇我嘅世界` ·
`想消失` · `消失咗就好` · `冇我會好過` · `冇我會好啲` · `冇晒希望` · `冇得救` ·
`冇路可走` · `冇後路` · `唔想再生` · `不如死咗` · `再活落去都冇意思` ·
`活落去冇意思` · `生存冇意義` · `生存冇意思`

**繁體 / 粵語 — worthlessness (v3)**
`活著冇價值` · `生存冇價值` · `我冇價值` · `我冇存在價值` · `冇存在價值` ·
`我係多餘` · `我係廢人` · `冇人需要我`

**繁體 / 粵語 — harm-to-others (v3)**
`想殺人` · `想殺死` · `殺死佢` · `殺咗佢` · `想傷害人` · `想傷害佢` · `想弄死佢`

**简体 — ideation**
`自杀` · `想死了` · `想自杀` · `结束自己` · `了结自己` · `了结生命` ·
`没我会更好` · `想消失` · `消失就好` · `没有希望` · `没得救` · `没有出路` ·
`不如死了` · `没意思活下去`

**简体 — worthlessness (v3)**
`活着没价值` · `生存没有价值` · `我没有价值` · `没有存在价值` · `我是多余的` ·
`我是废人` · `没人需要我`

**简体 — harm-to-others (v3)**
`想杀人` · `想杀死` · `杀死他` · `想伤害别人` · `想弄死他`

---

## MODERATE (44 terms) → soft support sheet

**English**
`hopeless` · `burden` · `nobody cares` · `no one cares` · `i'm a burden` ·
`lost him` · `lost her` · `passed away` · `just died` · `grieving` ·
`can't cope` · `overwhelmed` · `falling apart`

**繁體 / 粵語 — distress**
`冇用` · `冇人理我` · `冇人關心` · `冇人愛我` · `拖累` · `累贅` · `負累` ·
`頂唔順` · `撐唔住` · `撐不住` · `好辛苦` · `辛苦到` · `絕望` · `孤獨到痛` ·
`崩潰` · `崩到爆`

**繁體 / 粵語 — loss / grief**
`失去咗` · `走咗` · `剛走` · `剛去世` · `過咗身` · `過世` · `離世` · `哀傷` ·
`悲痛`

**简体**
`没用` · `没人理` · `没人关心` · `没人爱我` · `拖累` · `累赘` · `撑不住` ·
`顶不住` · `好辛苦` · `绝望` · `崩溃` · `刚走` · `刚去世` · `过世` · `离世`

---

## LOW (29 terms) → pill only, never escalates

**English**
`lonely` · `alone` · `isolated` · `no one to talk to` · `empty` · `sad` ·
`feeling low` · `down today`

**繁體 / 粵語**
`孤獨` · `孤單` · `一個人` · `冇人陪` · `空虛` · `唔開心` · `好悶` · `悶悶哋` ·
`冇心機` · `冇神冇氣` · `冇精神` · `失落` · `心情差`

**简体**
`孤独` · `孤单` · `一个人` · `没人陪` · `空虚` · `不开心` · `没心情` · `没精神`

---

## Known coverage gaps (for your decision — not yet changed)

### 1. `冇` vs `沒` asymmetry — *this is the bug you hit*
The Cantonese acute/worthlessness terms are written with **`冇`** only
(`活著冇價值`, `我冇價值`, `冇存在價值`, `冇人需要我`…). A user who types the
written-standard **`沒`** (`活著沒價值`, `我沒價值`) or the simplified `没`
mixed into a traditional sentence **will not match acute**, and may fall to a
lower tier or none. The simplified `活着没价值` *is* covered, which is why
simplified escalated but your traditional-`沒` sentence did not.
**Fix direction (fail-safe):** add the `沒` variant of every `冇`-based
worthlessness/ideation term. Candidates:
`活著沒價值` · `我沒價值` · `我沒存在價值` · `沒存在價值` · `沒人需要我` ·
`活落去冇意思`→also `活落去沒意思` · etc.

### 2. Moderate synonym gaps (from the corpus analysis, v1.0 doc)
- `負擔` (burden) — only `負累`/`拖累`/`累贅` present.
- `都唔關心我` / `都唔理我` — only `冇人關心`/`冇人理我` present.
- `lost my husband` / generic-loss English phrasings — only `lost him/her`,
  `passed away`.

### 3. Low synonym gaps
- `寂寞` (very common "lonely") — only `孤獨`/`孤單`.
- `低落` (low mood) — only `失落`/`心情差`.
- Infix breakage: `冇咩心機` misses `冇心機` (the `咩` splits the substring).

### 4. Script coverage is uneven
Some terms exist in only one script (e.g. `頂唔順` trad-only; `顶不住`
simp-only). A full pass would mirror every term across 繁體 / 简体.

> **Reviewer note.** Acute recall on the synthetic corpus is already 1.000, but
> that corpus is `冇`-based and does not test `沒` variants — so it would not
> have caught gap #1. Adding `沒` variants + a few corpus items that use `沒`
> is the recommended next step, pending your review of this list.
