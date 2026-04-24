# Image asset checklist

Every amber-bordered `FigurePlaceholder` box in the app is a slot waiting
for a real illustration or photograph. This file lists every slot, a
drop-in file path, an image-generation prompt, and step-by-step
instructions for wiring the asset in.

## How to replace a placeholder (quick guide)

1. **Generate / export the image.** Use the prompt from the table below
   with any tool (DALL·E, Midjourney, Stable Diffusion, Firefly, human
   illustrator). Export as `.png` or `.webp` at **2x the display size**
   in the table — Flutter will scale it down crisply on high-DPI devices.
2. **Save it to `assets/images/`.** Use the suggested filename (left
   column of the table). The folder is already declared in
   `pubspec.yaml`:
   ```yaml
   flutter:
     assets:
       - assets/images/
   ```
   So any file you drop in there is picked up on the next `flutter pub
   get` + hot-restart.
3. **Swap the placeholder for `Image.asset`.** In the Dart file listed in
   the table, replace the `FigurePlaceholder(...)` block with:
   ```dart
   ClipRRect(
     borderRadius: BorderRadius.circular(16),
     child: Image.asset(
       'assets/images/<filename>',
       height: 130,          // keep the same height as the placeholder
       width: double.infinity,
       fit: BoxFit.cover,
     ),
   )
   ```
   Keep the surrounding padding and spacing the same. If you want to
   preserve the "briefed" tooltip in source, leave a single-line comment
   referencing the prompt.
4. **If you no longer use `FigurePlaceholder` anywhere**, delete the
   import line for `figure_placeholder.dart` and remove
   `lib/shared/widgets/figure_placeholder.dart`. Safe to do only after
   every slot on this page is replaced.
5. **Test both themes.** Toggle high-contrast mode in Settings — images
   should still read well on a pure-white background with black borders.
6. **Test both languages.** No image should contain embedded text;
   captions live in the Dart code above / below.

> Tip: if you're using an LLM image tool, prepend every prompt with
> "Soft, warm, gentle illustration for an elderly-friendly Hong Kong
> wellbeing app. Avoid text in the image. 16:9 aspect unless stated."

---

## Slots to fill

| # | Suggested path | Used in | Size (h × w) | Prompt |
| - | --- | --- | --- | --- |
| 1 | `assets/images/home_hero.png` | `lib/features/home/presentation/pages/home_page.dart` (around line 135, the `FigurePlaceholder` under the greeting hero) | 110 × full-width | Two warm, minimalist silhouettes smiling at each other across smartphones, soft gradient background in teal and cream, gentle hand-drawn texture. Conveys "a short greeting already feels warm." No text. |
| 2 | `assets/images/action_support_hero.png` | `lib/features/action_support/presentation/pages/action_support_page.dart` (around line 136, under the tab heading) | 130 × full-width | Sunlight streaming through a window onto a wooden table with a steaming cup of tea and an open book. Calm, mid-afternoon palette, watercolour feel, cosy and unhurried. No people, no text. |
| 3 | `assets/images/follow_up_hero.png` | `lib/features/follow_up/presentation/pages/follow_up_page.dart` (around line 24) | 110 × full-width | A stylised wall calendar with a few small hand-drawn flowers blooming across the dates, soft pastel colours, evokes "small habits growing slowly each week". Flat illustration, minimal. No text. |
| 4 | `assets/images/community_map.png` | `lib/features/resources/presentation/pages/community_resources_page.dart` (around line 32) | 130 × full-width | Friendly hand-drawn map thumbnail of a Hong Kong neighbourhood with three warm coloured dots marking nearby elderly community centres and one pulse dot marking the user location. Streets drawn as soft curves, not grid. Warm pastel. No labels. |
| 5 | `assets/images/onboarding_welcome.png` | `lib/features/onboarding/presentation/pages/onboarding_page.dart` (first slide, line ~49) | 130 × full-width | Two hands gently supporting each other, warm earth tones, minimalist line-art with soft shading, symbolising companionship and patience. No text, no faces. |
| 6 | `assets/images/onboarding_help.png` | `lib/features/onboarding/presentation/pages/onboarding_page.dart` (second slide, line ~55) | 130 × full-width | Four small circular icons connected by a soft dotted path: a heart (check-in), people (social map), a lightbulb (small action), a calendar (follow-up). Warm palette, friendly flat style. No text. |

---

## Optional extras (nice-to-have, no current placeholder)

These aren't blocking, but would warm the app up further. Add them after
the six above are in place.

| Purpose | Suggested path | Prompt |
| --- | --- | --- |
| Launch / splash graphic | `assets/images/splash.png` | A sunrise scene over the Hong Kong skyline with a single warm-lit apartment window, soft brushstrokes, conveys "gentle start to the day". |
| HKU DSE wordmark badge | `assets/images/hku_dse_badge.png` | Compact dark-red circular badge with "HKU DSE" in clean sans-serif. Flat vector. (Replaces the inline `HKU` text chip in `_GreetingHero` and `_AboutCard`.) |
| 阿暖 persona avatar | `assets/images/persona_casual.png` | Warm, round illustrated portrait of a kind middle-aged Hong Kong auntie character, soft pastel background, friendly smile. Square. |
| 李醫師 persona avatar | `assets/images/persona_consult.png` | Calm, steady illustrated portrait of a middle-aged male doctor with glasses and a gentle expression, neutral blue background. Square. |
| 小助 persona avatar | `assets/images/persona_faq.png` | Friendly chat-bubble character mascot in teal, rounded shapes, waving, feels helpful and approachable. Square. |

For persona avatars, the swap lives in
`lib/features/chat/presentation/widgets/persona_avatar.dart` — replace
the `Icon(...)` inside the gradient circle with
`Image.asset('assets/images/persona_xxx.png', fit: BoxFit.cover)`.

---

## Quick test checklist after a swap

- [ ] `flutter pub get`
- [ ] `flutter run` — hot-restart (not just reload) so the asset bundle
      refreshes
- [ ] Toggle high-contrast in Settings → image still reads cleanly
- [ ] Toggle 繁中 / English → layout doesn't break (image height is fixed)
- [ ] On a small screen (e.g. iPhone SE width) the image doesn't push
      cards off-screen

## Where the slots live in source

If you ever need to re-discover all placeholder locations, run:

```bash
grep -rn "FigurePlaceholder(" lib/
```

Each match is a slot on this list. The `description:` field inside each
placeholder carries the brief for designers/illustrators — keep it in
sync with this file if you change a prompt.
