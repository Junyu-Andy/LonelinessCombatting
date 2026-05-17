# Companion Demo · 陪伴型 App Demo

> **HKU Department of Data and Systems Engineering**
> 香港大學數據及系統工程學系

A Flutter research app that helps **older adults in Hong Kong gently push back against loneliness**. It is the deliverable for a 2-arm RCT pilot:

- **Arm A (hybrid)** — LLM-augmented dialogue across check-in, life review, reflection, suggestion, action loop, and progress.
- **Arm B (rule-based)** — identical UI shell with deterministic templates / static pools.

The split lives inside each module's controller; the surface widgets are **pixel-identical between arms** except for two sanctioned exceptions (M8 "問下呢篇" Q&A button, M9 weekly LLM summary card).

## What's inside

| Tab | Purpose |
| --- | --- |
| 🏠 **Today** (今日) | Greeting, mood check-in (M2), micro-actions into reflection (M5) and social suggestion (M6), today's active plan banner (M7), absence nudge (P3.2) |
| 📖 **My Story** (人生點滴) | M3 4-week reminiscence: current-week hero, session history, life-thread timeline |
| 👤 **Me** (我) | Education library (M8), action loop list (M7), progress (M9), social suggestions (M6), reflection (M5), emergency support, personalization |
| ⚙️ **Settings** (設定) | Font scale (1.0 / 1.15 / 1.30×), high-contrast, language (繁中 / English), notifications, transcript-retention toggle, FAQ, privacy policy |

A persistent **safety pill** sits above every screen — its label and colour shift with detected distress level (none / low / moderate / acute) and routes to the calm breathing page or emergency line on tap.

## Module map

| Module | Status | What it does |
| --- | --- | --- |
| M1 Onboarding + consent | ✅ Local only | 1-required-agreement consent + 3 explanatory info cards (P5.3 copy) |
| M2 Daily check-in | 🟡 Firebase + (Arm A) DeepSeek | 6-face mood + 3 MCQ + free note (Arm B) · LLM turn-by-turn reflection (Arm A) |
| M3 Reminiscence (4 weeks) | 🟡 Firebase + (Arm A) DeepSeek | Per-week themed session, turn-by-turn (Arm A) or one-shot capture (Arm B), end-of-session summary editor (Arm A) with original/edited split, re-edit affordance in detail page |
| M4 Cognitive restructure | 🟡 Firebase + (Arm A) DeepSeek | Thought record, Socratic prompts (Arm A), hand-off to M7 |
| M5 Self-reflection | 🟡 Firebase + (Arm A) DeepSeek | Context-aware prompt (Arm A) vs. rotating static pool (Arm B) |
| M6 Social suggestions | 🟡 Firebase + (Arm A) DeepSeek | Personalised suggestion (Arm A) vs. 16-item pool (Arm B), accept routes to M7 |
| M7 Action loop | 🟡 Firebase + (Arm A) DeepSeek | Plan articulation (when/where/who/fallback) + 24 h follow-up reminder queue · Today banner picks the next active plan |
| M8 Education | ✅ Local read · 🟡 Arm A dialogue | 4 seed articles (target 15) · Arm A "問下呢篇" grounded LLM Q&A |
| M9 Progress | 🟡 Firebase + (Arm A) DeepSeek | 7-day mood bar chart with dual color+shape encoding (P4.3), count tiles, weekly LLM summary card (Arm A only) |

Cross-cutting infra: 4-level `DistressDetector` + `DistressRouter` (P3.4) · `CrossModuleMemoryService` with ISO-week budget (P3.6 / P2.1) · `NavigationTelemetry` for the Day-3 / Day-7 retention protocol (P5.1) · `TranscriptConsentPrompter` (P3.3) · in-app analytics with offline buffering.

## Run it locally

```bash
flutter pub get
flutter gen-l10n
flutter run -d chrome          # web — fast iteration, no LLM (CORS)
# or
flutter run                    # mobile / desktop device
```

**Boots without Firebase.** Guest mode keeps theme, font scale, language, mood encoding, distress detection, all UI flows fully usable. Arm A LLM calls fall back to scripted acknowledgements.

### Test split without sign-in

Use a dart-define to force an arm:

```bash
flutter run -d chrome --dart-define=FORCE_ARM=A
flutter run -d chrome --dart-define=FORCE_ARM=B
```

⚠️ **Never** ship a release build with `FORCE_ARM` set — it bypasses the randomisation transaction.

### Enable real LLM

LLM traffic goes through a `proxyDeepSeek` Cloud Function (Firebase Blaze plan required). See **[SETUP_FIREBASE.md](./SETUP_FIREBASE.md)**.

### Run tests

```bash
flutter test                                # all unit + widget tests
flutter test test/distress_corpus_test.dart # 190-item P5.4 corpus + recall/precision asserts
tool/parity_audit.sh --update               # regenerate goldens
tool/parity_audit.sh                        # CI mode — verify no drift
```

## Design system

| Token | Where |
| --- | --- |
| Typography (Material 3 textTheme + 1.4–1.5× line heights, `AppFontScale` multipliers) | `lib/app/app_theme.dart`, `lib/app/app_settings.dart` |
| Spacing & touch targets (≥ 56 pt) | `lib/theme/app_spacing.dart` |
| Mood color + shape encoding | `lib/theme/app_mood_encoding.dart` |
| Component library (`AppButton` / `AppModal` / `AppLoadingIndicator` / `AppStepper` / `showAppConfirm`) | `lib/shared/widgets/` |

## Key directories

| Area | Path |
| --- | --- |
| App shell & 4-tab nav | `lib/app/main_shell.dart` |
| Today | `lib/features/today/` |
| My Story | `lib/features/my_story/` · `lib/features/reminiscence/` |
| Me hub | `lib/features/me/` |
| Settings | `lib/features/settings/` |
| Auth + consent | `lib/features/auth/` · `lib/features/consent/` |
| Core services (LLM, memory, distress, voice) | `lib/core/` |
| Analytics + navigation telemetry | `lib/features/analytics/` |
| Theme + components | `lib/app/app_theme.dart` · `lib/theme/` · `lib/shared/widgets/` |
| Cloud Function (DeepSeek proxy) | `functions/index.js` |
| Firestore security rules | `firestore.rules` |

## Known gaps

- **Push notification delivery** — `ReminderQueue` writes to Firestore; FCM transport is unimplemented. The follow-up UI exists but won't fire from a notification yet.
- **Voice input on Web** — `speech_to_text` plugin doesn't run reliably in browsers; button is visible but disabled with a tooltip. Mobile real devices work.
- **Content authoring** — M8 has 4 seed articles (target ~15), M5 prompt pool / M6 suggestion pool / M3 opening prompts await cultural-advisor sign-off.
- **Distress corpus** — `test/distress_corpus_test.dart` ships 190 synthetic items meeting `acute recall ≥ 0.95`. Pilot launch criterion is to supplement with the dissertation co-design annotated set.
- **Parity goldens** — `test/parity/parity_harness.dart` defines the harness; goldens themselves haven't been generated. Run `tool/parity_audit.sh --update` once to baseline.
- **App Check** — `proxyDeepSeek` runs with `enforceAppCheck: false` for dev. Flip to `true` before pilot launch + wire the mobile SDK.
- **i18n beyond `zh_Hant_HK` + `en`** — ARB scaffolding is in place but no third locale shipped.

## Docs

| File | What's in it |
| --- | --- |
| `README.md` | This file |
| `SETUP_FIREBASE.md` | Step-by-step Firebase + Cloud Function deployment |
| `REPORT.md` | Capability snapshot |
| `IMAGES.md` | Image-prompt checklist for the eventual illustration swap-in |
| `firestore.rules` | Per-uid owner read/write + RCT counter increment-by-one rule |

---

**Contact / privacy:** zhaojyxs@connect.hku.hk — 香港大學 趙先生
