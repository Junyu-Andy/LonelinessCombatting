# 陪住 · With You

> **HKU Department of Data and Systems Engineering**
> 香港大學數據及系統工程學系

A Flutter + Firebase research app helping **Hong Kong older adults (60+) gently push back against loneliness**. It is the Phase A pilot deliverable for a stratified 4-cell RCT:

- **Arm A (Hybrid)** — three named LLM companions (DeepSeek-V3) layered over deterministic tools.
- **Arm B (Rule-based)** — identical UI shell with static pools and rule-based dialogue.

Surface widgets are **pixel-identical between arms** except for two sanctioned exceptions (M8 "問通通呢篇" Q&A button, M9 weekly LLM summary card). Phase A runs `forceArmA = true` for the pilot cohort.

## The three companions

| Companion | Role | Surface |
| --- | --- | --- |
| **小欣 (Siu Yan)** | Daily check-in confidante | M2 mood + reflective dialogue |
| **阿珍 / 阿伯 (Ah Jan / Ah Bak)** | Life-thread reminiscence partner — gender variant chosen during onboarding | M3 weekly reminiscence |
| **通通 (Tung Tung)** | Curious-companion grounded Q&A | M8 article Q&A, free chat with topic chips |

All three carry `contextSuffix` (avoidTopics, interests, life chapters) injected into every system prompt from the onboarding intake.

## What's inside

The app uses a four-tab Information Architecture (per Product Overview §3.2):

| Tab | Purpose |
| --- | --- |
| 🏠 **睇今日 Today** | Greeting, daily mood card, pending-prompts banner (PGIC / Weekly PR / Agent Diff), agent-tile entry to the three companions, active plan banner, missed-check-in nudge |
| 💬 **搵人傾 Talk** | Three agent rooms — Siu Yan, Ah Jan/Ah Bak, Tung Tung — each with their own room copy and quick-start chips |
| ✅ **做啲嘢 Do** | Tools: Action Loop (M7), Thought Exercise (M4), Education library (M8), Social suggestions (M6), Reflection (M5) |
| 👤 **自己 Me** | Progress (M9), profile + agent variant settings, font scale / contrast / language toggles, emergency support, weekly partner-assessment entry, FAQ + privacy |

A persistent **safety pill** floats above every screen — its label and colour shift with detected distress level (none / low / moderate / acute) and routes to the calm breathing page or emergency hotlines on tap.

## Module map

| Module | Status | What it does |
| --- | --- | --- |
| M1 Onboarding + consent | ✅ | Functional-data consent → 6-part intake (goals · important people · typical day · activities/topics · life chapters + **avoidTopics** · input mode / preferred times) → agent variant + interests |
| M2 Daily check-in (Siu Yan) | 🟡 Firebase + DeepSeek | 5-face mood card on home + reflective dialogue room with Brief PR + thumbs feedback per turn |
| M3 Reminiscence (Ah Jan/Bak) | 🟡 Firebase + DeepSeek | 4-week life thread, per-week themed session, summary editor with original/edited split, re-edit affordance |
| M4 Thought exercise | 🟡 Firebase + DeepSeek | First-visit hint, before/after thought capture, Socratic prompts (Arm A) |
| M5 Self-reflection | 🟡 Firebase + DeepSeek | Context-aware prompt (Arm A) vs. rotating static pool (Arm B) |
| M6 Social suggestions | 🟡 Firebase + DeepSeek | Personalised suggestion (Arm A) vs. 16-item pool (Arm B); accept → M7 |
| M7 Action loop | 🟡 Firebase + DeepSeek | Plan articulation (what / when / where / fallback) + 24 h follow-up reminder queue · Today banner picks the next active plan |
| M8 Education (Tung Tung) | ✅ Local read · 🟡 Arm A Q&A | Seed articles with crisis-hint footers where relevant · Arm A "問通通呢篇" grounded Q&A with thumbs feedback |
| M9 Progress | 🟡 Firebase + DeepSeek | 7-day mood bar chart (dual color+shape encoding), count tiles, weekly LLM summary card (Arm A only) |

## Measurement & feedback infra

Sprint 1–3 measurement surfaces (all client-side; no FCM yet):

| Surface | Trigger | Stored at |
| --- | --- | --- |
| **Daily mood card** | Once per day on Today | `users/{uid}/daily_mood/{YYYY-MM-DD}` |
| **Brief PR** (4 sliders: understanding / validation / caring / insensitivity) | After substantive session: ≥180 s + ≥3 exchanges, once per agent per day. **First time = anchor prompt (no skip).** | `users/{uid}/brief_pr/{auto}` |
| **Weekly PR** (12 items × N agents) | Sunday 20:00–23:59 HKT banner; agents sequenced by descending session count; no_referent doc if no agents used | `users/{uid}/weekly_pr/{auto}` |
| **PGIC** (7-point change scale) | Sunday banner → chains into Weekly PR | `users/{uid}/pgic/{auto}` |
| **Agent Diff** (usage matrix + personality + scenarios + free text) | Day 14 (W2) + Day 28 (W4) from `profile.createdAt` | `users/{uid}/agent_diff/{auto}` with `timepoint: "week2" \| "week4"` |
| **Thumbs feedback** (👍 / 👎 + 5 reason chips) | Per agent turn on M2 / M3 / M5 / M8 Q&A; re-rate supersedes prior; tap-outside = `unintentional_dismiss` | `users/{uid}/response_feedback/{auto}` |
| **Screen dwell** | NavigatorObserver enter/exit pairs | `screen_entered` / `screen_exited` analytics events |

Cross-cutting infra: 4-level `DistressDetector` + `DistressRouter` · `CrossModuleMemoryService` with ISO-week budget · `TranscriptConsentPrompter` · `IdleSessionTimer` · `AnalyticsService` (in-memory buffer, arm-tagged events, `_armRequiredEvents` assertion set) · `FeatureFlags` · `HybridOnlyMount` · `ArmScope`.

## Crisis support

`EmergencySupportPage` lists four HK hotlines with **one-tap dialling** via `url_launcher`:

- 撒瑪利亞防止自殺會 · 2382 0000 (24h suicide prevention)
- 香港撒瑪利亞會（多語）· 2896 0000 (Cantonese / Mandarin / English)
- 醫管局精神健康專線 · 2466 7350
- 999 緊急服務

Trusted-contact row reads from `UserProfile.emergencyContactName/Phone` (captured during onboarding).

## Bilingual UI

繁中 (粵語) + English across all user-facing surfaces. See `I18N_REVIEW.md` for the full Cantonese ↔ English translation table.

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

```bash
flutter run -d chrome --dart-define=FORCE_ARM=A
flutter run -d chrome --dart-define=FORCE_ARM=B
```

⚠️ **Never** ship a release build with `FORCE_ARM` set — it bypasses the randomisation transaction.

### Enable real LLM

LLM traffic goes through a `proxyDeepSeek` Cloud Function (Firebase Blaze plan required, `max_tokens 800`, `top_p 0.95`, 55 s timeout). See **[SETUP_FIREBASE.md](./SETUP_FIREBASE.md)**.

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
| Component library | `lib/shared/widgets/` |

## Key directories

| Area | Path |
| --- | --- |
| App shell & 4-tab nav | `lib/app/main_shell.dart` |
| Today + agent tiles | `lib/features/today/` |
| Three agent rooms (Talk tab) | `lib/features/talk/` · `lib/features/context/` · `lib/features/reflective_dialogue/` · `lib/features/curious_companion/` |
| Reminiscence (M3) | `lib/features/reminiscence/` · `lib/features/my_story/` |
| Tools (Do tab) | `lib/features/action_loop/` · `lib/features/thought_exercise/` · `lib/features/education/` · `lib/features/social_suggestions/` |
| Onboarding intake | `lib/features/onboarding/` |
| Measurement & feedback | `lib/features/brief_pr/` · `lib/features/weekly_pr/` · `lib/features/response_feedback/` · `lib/features/assessment/` |
| Crisis + safety | `lib/features/crisis/` · `lib/core/safety/` |
| Telemetry & scheduling | `lib/core/telemetry/` · `lib/core/scheduling/` · `lib/features/analytics/` |
| Core services (LLM, memory, distress, voice, arm) | `lib/core/` |
| Cloud Function (DeepSeek proxy) | `functions/index.js` |
| Firestore security rules | `firestore.rules` |

## Known gaps (Phase A pilot launch checklist)

See **[STATUS.md](./STATUS.md)** for full Sprint 1–3 implementation breakdown.

**Server-side / infra (intentionally deferred):**
- **FCM push notifications** — replaced by `PendingPromptsBanner` on Today; user must open the app to see Sunday / Day-14 / Day-28 prompts.
- **Cloud Functions** — 5-flag LLM tagging, audit triggers, safety-event alerting, nightly Gate 1–9 compute, weekly export (Sunday 02:00 HKT) all stubbed.
- **App Check enforcement** — `proxyDeepSeek` runs with `enforceAppCheck: false` for dev. Flip before pilot launch.
- **Researcher dashboard** — page scaffold exists; 12 spec'd views not aggregated.

**Client-side gaps:**
- **Voice input on intake long-text fields** (Part 3 on-mind, Part 5 avoidTopics) — current `TextField`s use `onChanged` only; needs controller refactor.
- **Daily mood skip persistence** (3-day reduce / 7-day pause) — Sprint 1 §2 throttle not implemented.
- **Per-turn metadata persistence** (model, systemPromptHash, latencyMs, input_modality) — Sprint 3 §5.1.
- **Distress corpus** — `test/distress_corpus_test.dart` ships 190 synthetic items; pilot launch needs the dissertation co-design annotated set merged in.
- **Parity goldens** — harness exists; goldens not yet baselined (`tool/parity_audit.sh --update`).

**Research-side dependencies:**
- Cognitive interview validation of Weekly PR Cantonese strings before deployment.
- HK place gazetteer for 5-flag NER (`anchor_named_entity`).
- M8 content authoring expansion (target ~15 articles) + cultural-advisor sign-off on M5/M6 pools.

## Docs

| File | What's in it |
| --- | --- |
| `README.md` | This file |
| `STATUS.md` | Sprint 1–3 implementation status — done / deferred / blocked |
| `I18N_REVIEW.md` | Full Cantonese ↔ English translation table for review |
| `SETUP_FIREBASE.md` | Step-by-step Firebase + Cloud Function deployment |
| `REPORT.md` | Capability snapshot |
| `IMAGES.md` | Image-prompt checklist for the eventual illustration swap-in |
| `firestore.rules` | Per-uid owner read/write + RCT counter increment-by-one rule |

---

**Contact / privacy:** zhaojyxs@connect.hku.hk — 香港大學 趙先生
