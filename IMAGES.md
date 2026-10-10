# 插图清单

**结论**：三位陪伴者的形象已经定稿并在用（见下面第 1 部分），是圆头机械人，不是真人。第 2–5 部分（首页、入门、文章、心情脸）还没有图，只是出图要求。

## 第 1 部分：陪伴者形象（已在用）

四个角色、每个两张图，放在 `assets/agents/`。阿珍和阿伯是同一个陪伴者，老人选了哪个就只看到哪个。

| 角色 | 定位 | 形象 | 主题色（代码） | 图片 |
|---|---|---|---|---|
| 小欣 | 日常陪伴 | 珊瑚橙色机械人；天线顶是一颗心，胸口心形；双手捧一杯花纹茶杯；大眼睛、笑 | 珊瑚 `#F0997B` | `siu_yan_avatar.png`、`siu_yan_fullbody.png` |
| 阿珍 | 听你讲往事（女版） | 藕紫色身体，耳朵和胸口淡粉；胸前小花刺绣；拿一把淡粉折扇；天线是扇形；眼神温和、微微侧头 | 藕紫 `#C4A3CE` | `ah_jan_avatar.png`、`ah_jan_fullbody.png` |
| 阿伯 | 听你讲往事（男版） | 灰紫色身体，方形脸屏；一手拿笔、一手拿笔记本；天线像一卷书轴；表情沉稳 | 藕紫 `#C4A3CE` | `ah_bak_avatar.png`、`ah_bak_fullbody.png` |
| 通通 | 好奇的街坊 | 薄荷绿身体配黄边；天线顶是一本打开的书；一手放大镜、一手拿书；胸口灯泡和问号；张嘴笑 | 薄荷 `#5DCAA5` | `tung_tung_avatar.png`、`tung_tung_fullbody.png` |

**在哪里用**

- 头像（`*_avatar.png`）：首页卡片、聊天页、入门介绍、第一次自我介绍、转介卡片、每周问卷、ADA。代码在 `lib/core/agents/agent_avatar.dart`（`AgentAvatar`）和 `lib/features/ada/presentation/ada_widgets.dart`，路径登记在 `lib/core/agents/agent_registry.dart`。
- 全身图（`*_fullbody.png`）：陪伴者介绍页顶部。路径在 `lib/features/agent_profile/data/agent_profile_content.dart`。
- 图片找不到时，头像显示主题色圆圈加名字第一个字。

**图片规格**

- 1254×1254 正方形 PNG，**透明背景**（RGBA）。2026-10-10 起：原图把灰白格子画在了图里（并不透明），已用 `tool/assets/remove_checker_background.py` 去掉。
- 换新图时直接覆盖同名文件，必须是真正的透明背景，不要带格子或白底。放到深色和橙色底上各看一次，边缘不能有白边。
- 头像会被裁成圆形（`BoxFit.cover`），所以头和上半身要在画面中间。

**颜色**

- 2026-10-10 起阿珍、阿伯改成紫色系（决策 0031），原来阿珍是薄荷绿、阿伯是灰蓝，和通通撞色。只改了色相，深浅不变，用的是 `tool/assets/recolor_hue.py`。
- 以后重画或调色：通通保持绿色，阿珍/阿伯保持紫色系，**不要把颜色调浅**（调浅后胸口和扇子像半透明）。
- 改了图的颜色，代码里的主题色也要一起改：`agent_registry.dart`、`agent_profile_content.dart`、`agent_tile_row.dart`、`continue_chat_card.dart`。

---

## 第 2–5 部分：未做的插图（出图要求，英文原稿）

下面是早期写的出图要求，还没有做。风格要求：

> Soft, warm, gentle illustration for a Hong Kong elderly-friendly
> wellbeing app. Warm earth tones — terracotta, sand, cream, dusty rose,
> sage. Hand-drawn watercolour or soft flat-shaded style. No embedded
> text. No identifiable faces unless specified. Calm and unhurried.

Target palette: primary terracotta `#C2703F`, warm off-white `#F7F5F1`,
warm ink `#3A3330`. Export at **2× display size**.

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

Tier 1 (agent personas) is done (see 第 1 部分). Next: Tier 2 (hero). Tier 3-5 are
polish.
