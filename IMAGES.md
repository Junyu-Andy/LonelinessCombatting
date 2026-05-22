# Illustration MVP brief

Goal: a small, **drop-in static pool** that warms up the app without any
runtime LLM image generation. Generate once (Midjourney / DALL·E /
Firefly / human illustrator), drop the PNG/WebP into `assets/images/`,
swap the placeholder in code. No backend needed.

## Style guide (prepend to every prompt)

> Soft, warm, gentle illustration for a Hong Kong elderly-friendly
> wellbeing app. Warm earth tones — terracotta, sand, cream, dusty rose,
> sage. Hand-drawn watercolour or soft flat-shaded style. No embedded
> text. No identifiable faces unless specified. Calm and unhurried.

Target palette (matches the new app theme tokens):
- Primary terracotta `#C2703F`
- Warm off-white `#F7F5F1`
- Warm ink `#3A3330`
- Agent rings: `#E0A98E` (Siu Yan) · `#B3ACDE` (Ah Jan/Ah Bak) · `#7FCBAE` (Tung Tung)

Export at **2× display size** so retina/HiDPI looks crisp.

---

## Tier 1 — Agent personas (highest impact, 6 images)

The three companions need illustrated avatars instead of the current
icon-in-circle. Two variants for Ah Jan/Ah Bak (gender choice in
onboarding). Drop into `assets/images/agents/`.

| Path | Agent | Prompt |
|---|---|---|
| `agents/siu_yan.png` | 小欣 (Siu Yan) — daily check-in confidante | Round portrait, kind young-adult Hong Kong woman with a soft warm smile, terracotta blouse, neutral sand-cream background, watercolour. 512×512, square. |
| `agents/ah_jan.png` | 阿珍 — reminiscence partner (female variant) | Round portrait, warm middle-aged Hong Kong auntie with short permed hair and reading glasses, light lavender blouse, dusty rose background, watercolour. 512×512, square. |
| `agents/ah_bak.png` | 阿伯 — reminiscence partner (male variant) | Round portrait, warm middle-aged Hong Kong uncle with greying hair and gentle eyes, slate-grey collared shirt, dusty rose background, watercolour. 512×512, square. |
| `agents/tung_tung.png` | 通通 — curious companion | Round portrait, friendly mascot-style character (animal or stylised) in sage green, big curious eyes, holding a small notebook or a tea cup, cream background, watercolour. 512×512, square. |
| `agents/siu_yan_listening.png` | Siu Yan reaction — listening | Same character/style as `siu_yan.png`, slight head tilt, hand to chin, attentive expression. |
| `agents/tung_tung_thinking.png` | Tung Tung reaction — thinking | Same character/style as `tung_tung.png`, finger to lip, looking up, thought-bubble feel. |

**Swap location:** `lib/core/agents/agent_avatar.dart` — replace the
`Icon(...)` fallback in `AgentAvatar` with `Image.asset('assets/images/agents/${agent.id}.png', fit: BoxFit.cover)`. (Reaction variants are used by the chat bubble code, optional v2.)

---

## Tier 2 — Hero time-of-day (5 images)

The UI restyle spec wants a warm gradient hero with optional inline
illustration accent. Drop into `assets/images/hero/`.

| Path | When | Prompt |
|---|---|---|
| `hero/morning.png` | 05:00–10:59 | Soft watercolour scene — first sunlight through a kitchen window, steam rising from a tea cup on a wooden table, terracotta and golden-honey palette, no people. 1200×400, landscape banner. |
| `hero/day.png` | 11:00–17:59 | Soft watercolour — sunlit park bench with one warm cushion, a folded newspaper, cream and sand palette. 1200×400. |
| `hero/evening.png` | 18:00–21:59 | Soft watercolour — warm lamp glow inside a window, dusk sky in dusty rose, a single armchair silhouette. 1200×400. |
| `hero/night.png` | 22:00–04:59 | Soft watercolour — crescent moon over a quiet HK street, warm-lit single window, deep ink-blue with dusty-rose accents. 1200×400. |
| `hero/rest_today.png` | 「今日休息」 | Soft watercolour — closed blinds, a soft cushion, a folded blanket, all in warm cream tones. 1200×400. |

**Swap location:** `lib/features/today/presentation/widgets/greeting_hero.dart` — overlay as a low-opacity background image inside the gradient container, OR use as a side accent image (whichever the restyle agent settles on).

---

## Tier 3 — Onboarding journey (4 images)

The intake flow is 6 parts long and feels like a form. Add an
illustration at the top of Parts 1, 3, 5, and the Done screen to soften
it. Drop into `assets/images/onboarding/`.

| Path | When | Prompt |
|---|---|---|
| `onboarding/welcome.png` | Welcome screen | Soft watercolour — two open palms cupping a small warm light, warm earth tones, symbolises companionship. 800×400, landscape. |
| `onboarding/people.png` | Part 2 (important people / reconnect) | Soft watercolour — three abstract human silhouettes holding hands in a gentle curve, warm cream and dusty rose. 800×400. |
| `onboarding/typical_day.png` | Part 3 (typical day) | Soft watercolour — a clock face with a tea cup at noon and a lamp at evening, warm palette. 800×400. |
| `onboarding/done.png` | Done screen | Soft watercolour — small seedling sprouting through warm soil, gentle morning light. 800×400. |

---

## Tier 4 — Education article heroes (10 images, optional)

Each `EducationArticle` could carry an optional `heroImage` field. Drop
into `assets/images/articles/{article_id}.png`. The article IDs already
exist in `lib/features/education/data/education_library.dart`.

| Article ID | Prompt |
|---|---|
| `what_loneliness_is` | Soft watercolour — single tea cup on a window sill at dusk, warm light inside, blue dusk outside. 1200×400. |
| `thoughts_and_feelings` | Soft watercolour — two leaves connected by a fine line, one warm-toned and one cool-toned, gentle gradient. 1200×400. |
| `small_actions_help` | Soft watercolour — a small stone path with three pebbles leading toward warm light. 1200×400. |
| `hk_resources` | Soft watercolour — folded HK skyline map with a warm pin-mark. 1200×400. |
| `why_loneliness_matters_health` | Soft watercolour — a soft heart shape woven from warm threads. 1200×400. |
| `sleep_and_loneliness` | Soft watercolour — a folded blanket and a moon, soft lamp glow. 1200×400. |
| `talking_with_family` | Soft watercolour — three tea cups on a round table, one steam wisp connecting two of them. 1200×400. |
| `friendship_later_life` | Soft watercolour — two pairs of hands gently shelling peas at a table, warm afternoon light. 1200×400. |
| `pets_comfort` | Soft watercolour — a sleeping cat curled next to an open book, warm lamp. 1200×400. |
| `grief_and_loneliness` | Soft watercolour — a single white chrysanthemum in a quiet vase, soft window light. 1200×400. (⚠️ sensitive — keep extremely understated.) |

To wire: add `final String? heroImage;` to `EducationArticle`, render it
above the article body in `education_article_page.dart`.

---

## Tier 5 — Mood face alternatives (5 images, optional)

The current 5-face mood picker uses emoji (😔🙁😐🙂😊). Emojis render
differently across platforms. Optional: replace with hand-drawn faces
for visual consistency. Drop into `assets/images/mood/`.

| Path | Value | Prompt |
|---|---|---|
| `mood/1.png` | 1 = 好差 | Hand-drawn circular face, downturned mouth, soft sad eyes, warm terracotta. 256×256. |
| `mood/2.png` | 2 = 差 | Hand-drawn circular face, slight frown, neutral eyes. 256×256. |
| `mood/3.png` | 3 = 麻麻地 | Hand-drawn circular face, straight mouth, soft neutral expression. 256×256. |
| `mood/4.png` | 4 = 幾好 | Hand-drawn circular face, slight smile, warm eyes. 256×256. |
| `mood/5.png` | 5 = 好好 | Hand-drawn circular face, full warm smile, eye crinkles. 256×256. |

**Swap:** `lib/features/today/presentation/widgets/daily_mood_card.dart` — replace `Text(face.$2)` (the emoji) with `Image.asset('assets/images/mood/${face.$1}.png', width: 32, height: 32)`.

---

## Generation tips

- **Midjourney:** prepend `--style raw --ar 16:9` for hero banners and `--ar 1:1` for portraits and mood faces.
- **DALL·E 3 / Firefly:** set "natural" style (not "vivid") to keep the soft warm tone.
- **Consistency:** generate all of one tier in a single batch session using the same seed/style reference so the visual language matches.

## Wiring checklist

```bash
# 1. Drop files into assets/images/<tier>/
# 2. pubspec.yaml already declares - assets/images/  (recursive picks up subfolders)
# 3. flutter clean && flutter pub get
# 4. Hot RESTART (not reload) so the asset bundle refreshes
# 5. Toggle high-contrast mode — images must still read well
```

## Priority order for MVP

If budget / time is limited, do **Tier 1 (agent personas)** first — that
alone transforms how the app feels. Then Tier 2 (hero). Tier 3-5 are
polish.
