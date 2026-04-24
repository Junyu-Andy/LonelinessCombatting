# Capability report — Companion Demo

_Snapshot: reflects the state of `main` at the time this file was written.
The app is a design + interaction demo: UI is production-quality, the data
backend is partially wired (auth + profile + analytics writes). No ML /
LLM components yet._

## 1. Product surface

| Area | State | Notes |
| --- | --- | --- |
| Home dashboard | ✅ | Gradient greeting hero, today's vibe bars, social-log card with inline entries, 8-tile quick-actions grid, daily-suggestion quote, boundary card |
| Check-in | ✅ | Three sliders (mood / loneliness / social energy). Values flow to analytics |
| Social map | ✅ | Static mock of close ties + acquaintance circles |
| Reflection (互動反思) | ✅ | Prompt cards — no LLM follow-up yet |
| Action support | ✅ | Tiny steps (effort + purpose chips), opener cards, activity grid colour-coded by social load |
| Follow-up | ✅ | Reminder toggles, weekly progress bar, pace picker with dot meter, celebration list |
| Calm / breathing | ✅ | Animated 4-4-6 box-breath cycle + grounding + tip cards |
| Community resources | ✅ | Mock elder centres, events, volunteer services, link tiles |
| Crisis / emergency | ✅ | Hotlines and immediate steps |
| Settings | ✅ | Font scale (preview only), high-contrast (applied), language (applied), quiet hours + voice readback (toggle stubs), profile, sign-out |
| Auth (email/password) | ✅ | Firebase Auth, Firestore profile, sign-up captures display name / age group / emergency contact |
| Onboarding | 🟡 | Slide deck exists but routed out of the app flow so it can be shown externally |

## 2. Platform & runtime

- **Flutter 3.9+** — Dart 3 syntax (records, `switch` expressions). Targets
  Android, iOS, web, macOS, Windows, Linux (the desktop targets are
  auto-generated; no platform-specific code lives outside the standard
  runners).
- **Firebase** — `firebase_core ^3.6`, `firebase_auth ^5.3`,
  `cloud_firestore ^5.4`. Initialisation fails gracefully to guest mode
  when `firebase_options.dart` is still the placeholder. See
  `SETUP_FIREBASE.md`.

## 3. Data collected today

| Event | Where emitted | Payload |
| --- | --- | --- |
| `session_start` | App resume | `sessionId`, `platform` |
| `session_end` | App pause / app stop | `sessionId`, `durationSeconds` |
| `tab_view` | Every tab change & app leave | `tab`, `durationSeconds` |
| `check_in_submitted` | `CheckInPage` save | `mood`, `loneliness`, `socialEnergy` |
| `social_log_entry` | Home social-log save | `hasPerson`, `summaryLength`, `feeling` |
| `opener_copied` | Action support opener copy | `audience` |
| `emergency_opened` | Opening Emergency / Calm pages | `from` |
| `auth_signed_up` / `auth_signed_in` / `auth_signed_out` | `AuthService` | `uid` only (no PII in payload) |

All events go to `users/{uid}/events/{autoId}` with
`{name, params, timestamp, sessionId, locale, highContrast}`. Guest-mode
events stay in an in-memory queue and are flushed if / when the user signs
in.

## 4. Accessibility highlights

- Body text 20px / headline max 32px, 1.55 line-height.
- All primary buttons min-height 60px, outline buttons 60px with 2px border.
- High-contrast: black ink on white, 2px outlines on cards + inputs, black
  indicator on the bottom nav. Controlled globally via `AppSettings`.
- Language: 繁體中文 (default) ↔ English via Settings radio. Preference
  round-trips through the Firestore profile.

## 5. Visible design debts

- Real illustrations aren't wired yet — six `FigurePlaceholder` boxes
  highlight where art is expected (each box carries the design brief).
- No persistence for guest-mode preferences (high-contrast / locale reset
  on cold start).
- Reminder add / delete and quiet-hours scheduling are visual stubs only —
  no OS notifications fired.
- The reflection / daily-suggestion / tiny-steps copy is hand-coded; no
  remote config yet.

## 6. What's next

1. Ship real illustrations or stock imagery into the `FigurePlaceholder`
   slots and remove the amber boxes.
2. Add `shared_preferences` persistence for locale and high-contrast so
   guest-mode choices survive restarts.
3. Schedule local notifications for reminders on `flutter_local_notifications`.
4. Firestore security rules (template in `SETUP_FIREBASE.md`).
5. Analytics dashboard — either BigQuery export or a small admin view that
   reads `users/{uid}/events`.
6. LLM-assisted reflection (optional, behind a flag) once the core loop
   is validated with real users.
