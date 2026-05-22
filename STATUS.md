# Sprint 1–3 implementation status

Snapshot of what was wired in this push and what is intentionally
deferred. Branch: `claude/sprint-1-implementation-Dfscd`.

## ✅ Implemented in this push

### Sprint 1 — storage paths
- `users/{uid}/pgic` (already correct in `pgic_page.dart`).
- `users/{uid}/agent_diff/{auto}` with `timepoint: "week2"|"week4"`
  (already correct in `agent_diff_response.dart`).
- `users/{uid}/onboarding/intake` (already correct in
  `intake_repository.dart`).

### Sprint 1 §3 — Brief PR
- `lib/features/brief_pr/data/brief_pr_response.dart` — model + Firestore mapping.
- `lib/features/brief_pr/data/brief_pr_gate.dart` — `shouldSurfaceBriefPr`
  (180 s × 3 exchanges, once/day per agent) and `isAnchorPromptFor`.
- `lib/features/brief_pr/presentation/pages/brief_pr_page.dart` — 4-slider
  modal (0–100, centred at 50, no numeric label, divider before
  reverse-coded slider). Submit enabled once all 4 sliders touched
  (`Set<int>` of touched indices). Skip button appears after 3 s and is
  suppressed when `isAnchorPrompt == true`.
- Wired surface at session end in:
  - `check_in_arm_a.dart` — `_saveSession` → `_maybeSurfaceBriefPr`.
  - `reflective_dialogue_page.dart` — `PopScope` on back nav.
  - `tung_tung_page.dart` — `PopScope` on back nav. (Uses gender variant
    display name for Ah Jan / Ah Bak.)

### Sprint 1 §4 — Weekly PR
- `lib/features/weekly_pr/data/weekly_pr_response.dart` — model + 12-item
  spec (u1/u2/u3/v1/v2/v3/c1/c2/c3/i1/i2/i3) with `〈AGENT〉` placeholder.
  Includes ISO-week helper (`currentWeekIso()`).
- `lib/features/weekly_pr/data/weekly_pr_trigger.dart` — last-7-day agents,
  ordered by descending session count, plus `hasSubmittedThisWeek` and
  `writeNoReferent`.
- `lib/features/weekly_pr/presentation/pages/weekly_pr_page.dart` — agent
  sequencer with `Companion X / N` header, randomised 12 items
  (`問題 X / 12`), 7-point Likert as large tap buttons, skip per agent.
- Entry in `SettingsPage` → 關於我 → 「每週夥伴評估」. Empty week writes
  a `no_referent` doc and shows toast.

### Sprint 2 §2 — Response feedback (thumbs)
- `lib/features/response_feedback/data/response_feedback.dart` — model
  with `superseded`, `supersededAt`, `unintentionalDismiss`.
- `lib/features/response_feedback/presentation/widgets/thumbs_feedback.dart`
  — thumbs up writes immediately + toast; thumbs down opens modal sheet
  with 5 reason chips + optional 其他 text. Tap-outside dismiss records
  `unintentionalDismiss: true` with empty reasons. Supersedes prior
  feedback for the same `turnRef` (`moduleId#turnKey`).
- Rendered below agent message bubbles in `check_in_arm_a.dart`,
  `reflective_dialogue_page.dart`, `tung_tung_page.dart`, and
  `education_article_page.dart` (Q&A mode).

### Sprint 2 §3.2 — module-level analytics events
Added to `analytics_service.dart`:
- `logSessionStart` (extended), `logSessionEnd` (extended).
- `logM2CheckInStarted/Abandoned`, `logTungTungChat{Started,Ended}`,
  `logTungTungTopicChipTapped`.
- `logResponseFeedbackSubmitted`, `logBriefPrSubmitted/Skipped`,
  `logWeeklyPrSubmitted/Skipped`, `logPgicSubmitted/Skipped`,
  `logDailyMoodSubmitted/Skipped`, `logAgentDiff{Started,Completed}`.
- `logSafetyPillTapped`, `logCrisisResourcesOpened`,
  `logDistressDetected`, `logTranscriptConsentToggled`.
- `logScreenEntered`, `logScreenExited`.

### Sprint 2 §3.3 — per-screen dwell time
- `lib/core/telemetry/screen_dwell_tracker.dart` — singleton, tracks
  entry timestamps, exposes `enter` / `exit` / `backgroundAll`.
- `lib/core/telemetry/screen_dwell_observer.dart` — `NavigatorObserver`
  firing enter/exit on `didPush` / `didPop` / `didReplace`.
- Wired into `MyApp` (registered as `navigatorObservers` on
  `MaterialApp`). Tracker bound to `AnalyticsService` in `initState`;
  app-lifecycle paused → `backgroundAll()`.

### Sprint 3 §6.3 — cross-referral UI
- Verified `core/cross_referral/referral_suggestion_card.dart` already
  renders accept/decline with appropriate copy and fires
  `cross_referral_offered/accepted/declined` events. No changes needed.

### Sprint 1 §7 — onboarding intake
- Storage path already correct.

### Sprint 3 §7.3 — crisis resources
- `emergency_support_page.dart` updated with the four spec'd HK
  hotlines (撒瑪利亞防止自殺會 2382 0000, 香港撒瑪利亞會 2896 0000,
  醫管局精神健康專線 2466 7350, 999). Copy-to-clipboard remains the
  one-tap behaviour pending `url_launcher` dependency.

### Sprint 1 §9 — trigger orchestration (banner-based)
- `lib/core/scheduling/pending_prompts_service.dart` — computes flags
  for pgic / weekly_pr / agent_diff_w2 / agent_diff_w4.
- `lib/features/today/presentation/widgets/pending_prompts_banner.dart`
  — renders banner with tap-throughs; Sunday flow chains PGIC → Weekly PR.
- Mounted between `QuietTodayBanner` and `DailyMoodCard` on `TodayPage`.

## ⏸ Deferred — require server infrastructure

- **Cloud Functions** — 5-flag tagging, audit triggers, safety event
  alerting, Weekly PR / PGIC scheduler, Tung Tung web search proxy.
  These remain stubbed; the client uses local heuristics or
  `SearchRepository` only when Firebase is available.
- **FCM push notifications** — replaced for Phase A by the client-only
  `PendingPromptsBanner`. The user must open 屋企 to see the prompt;
  no background push.
- **App Check enforcement flip** — `firestore.rules` and App Check
  configuration not changed in this push.
- **Researcher dashboard** — page exists at
  `lib/features/researcher_dashboard/...` as a stub; no analytics
  aggregation or hosted dashboard.
- **Tung Tung web-search Cloud Function** — `SearchRepository` still
  routes through the existing callable; if the function isn't deployed,
  the unavailable hint surfaces gracefully.

## ⚠️ Needs research-side input before activation

- **Weekly PR Cantonese strings** — the 12-item wording in
  `weekly_pr_response.dart` follows Sprint 1 §4.1 verbatim but has not
  been through cognitive-interview verification. Update the
  `WeeklyPrItems.items` list if wording changes.
- **HK gazetteer / place lookup** — not in this push.
- **Voice input on intake long-text fields** — the intake `TextField`s
  use `onChanged` (no controller) so dropping in `VoiceInputButton`
  requires refactoring to controllers. Held off this push; tracker item.

## Files created

- `lib/features/brief_pr/data/brief_pr_response.dart`
- `lib/features/brief_pr/data/brief_pr_gate.dart`
- `lib/features/brief_pr/presentation/pages/brief_pr_page.dart`
- `lib/features/weekly_pr/data/weekly_pr_response.dart`
- `lib/features/weekly_pr/data/weekly_pr_trigger.dart`
- `lib/features/weekly_pr/presentation/pages/weekly_pr_page.dart`
- `lib/features/response_feedback/data/response_feedback.dart`
- `lib/features/response_feedback/presentation/widgets/thumbs_feedback.dart`
- `lib/core/telemetry/screen_dwell_tracker.dart`
- `lib/core/telemetry/screen_dwell_observer.dart`
- `lib/core/scheduling/pending_prompts_service.dart`
- `lib/features/today/presentation/widgets/pending_prompts_banner.dart`
- `STATUS.md`

## Files modified

- `lib/features/analytics/data/analytics_service.dart`
- `lib/app/app.dart`
- `lib/features/today/presentation/pages/today_page.dart`
- `lib/features/settings/presentation/pages/settings_page.dart`
- `lib/features/crisis/presentation/pages/emergency_support_page.dart`
- `lib/features/context/presentation/pages/check_in_arm_a.dart`
- `lib/features/reflective_dialogue/presentation/pages/reflective_dialogue_page.dart`
- `lib/features/curious_companion/presentation/pages/tung_tung_page.dart`
- `lib/features/education/presentation/pages/education_article_page.dart`
