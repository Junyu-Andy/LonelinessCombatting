# Capability report — Companion Demo

_Built by **HKU Department of Industrial & Manufacturing Systems Engineering**.
Snapshot: reflects the state of `main` at the time this file was written.
The app is a design + interaction demo: UI is production-quality, the data
backend is partially wired (auth + profile + analytics writes). LLM chat
backend is scaffolded with a scripted fallback; DeepSeek hookup is left as
a clearly-marked TODO._

## 1. Product surface

| Area | State | Notes |
| --- | --- | --- |
| Bottom-nav shell | ✅ | 4 tabs — Home / 做點活動 / 傾偈 / 了解你. Settings sits in the AppBar gear, reachable from every tab. Animated tab title + cross-fade body |
| Home dashboard | ✅ | Gradient greeting hero (with HKU IMSE chip), today's vibe bars, social-log card, 8-tile quick-actions grid, daily-suggestion quote, boundary card |
| 做點活動 (Activities) | ✅ | Reframed positively. Pleasant micro-activities, opener lines, activity grid colour-coded by social load |
| 傾偈 (Chat) | ✅ | Two AI personas (`阿暖` casual / `李醫師` consult) with distinct avatars, chat themes, system prompts. Animated bubbles, typing indicator, `Hero` avatar. Text input working; voice input is a stub |
| 了解你 (About You) | ✅ | Profile card with bottom-sheet editor (`AuthService.updateProfile` → Firestore), recent state glance, embedded follow-up section |
| Check-in | ✅ | Three sliders. Values flow to analytics |
| Social map / reflection | ✅ | Linked from Home grid |
| Calm / breathing | ✅ | Animated 4-4-6 box-breath cycle + grounding + tip cards |
| Community resources | ✅ | Mock elder centres, events, volunteer services |
| Crisis / emergency | ✅ | Hotlines, immediate steps |
| Settings (modal) | ✅ | Font-scale preview, high-contrast (applied), language (applied), profile + sign-out, HKU IMSE attribution |
| Auth (email/password) | ✅ | Firebase Auth, Firestore profile, sign-up captures display name / age group / emergency contact |
| Onboarding | 🟡 | Slide deck still in repo but routed out of the in-app flow (shown externally) |

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

1. Wire `DeepseekChatBackend` to the real `/chat/completions` endpoint
   (TODOs in `lib/features/chat/data/chat_backend.dart`). Pass the API key
   via `--dart-define=DEEPSEEK_API_KEY=...`. Add `http: ^1.2.0` to pubspec.
2. Replace the voice-input stub in `chat_page.dart` with `speech_to_text`
   for real STT.
3. Ship real illustrations into the `FigurePlaceholder` slots.
4. `shared_preferences` persistence for locale + high-contrast so guest
   choices survive cold restarts.
5. Local notifications for reminders (`flutter_local_notifications`).
6. Tighten Firestore security rules (template in `SETUP_FIREBASE.md`).
7. Analytics surfacing — BigQuery export or an admin view over
   `users/{uid}/events`.
