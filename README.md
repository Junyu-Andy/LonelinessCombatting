# Companion Demo · 陪伴型 App Demo

> **HKU Department of Data and Systems Engineering**
> 香港大學數據及系統工程學系

A Flutter demo app that helps **older adults in Hong Kong gently push back against loneliness** — not a clinical tool, but a low-pressure companion for daily connection.

## What's inside

| Tab | Purpose |
| --- | --- |
| 🏠 **Home** | Greeting, today's vibe, social log, quick actions |
| 🌿 **Activities** (做點活動) | Positive micro-activity cards, opener lines, community shortcuts |
| 💬 **Chat** (傾偈) | Two AI personas: casual 阿暖 and reflective 李醫師 |
| 👤 **About You** (了解你) | Profile, recent check-ins, follow-up reminders |

Settings (gear icon in AppBar on every tab): high-contrast, language (繁中 / English), FAQ with AI helpdesk 小助.

## Run it

```bash
flutter pub get
flutter run
```

Boots without Firebase — guest mode keeps UI, theme, and language switching fully functional. For real auth/storage see **[SETUP_FIREBASE.md](./SETUP_FIREBASE.md)**.

To enable DeepSeek chat:

```bash
flutter run --dart-define=DEEPSEEK_API_KEY=sk-...
```

## Tech stack

- **Flutter** (Dart 3.9+) · Material 3 · elder-friendly base theme (body 20 pt, buttons ≥ 60 px)
- **High-contrast mode** — pure black-on-white with thick borders (`AppTheme.highContrast`)
- **Firebase Auth + Firestore** — email/password auth, profile storage, analytics events
- **DeepSeek API** — chat backend; falls back to scripted replies when no key is set
- **flutter_localizations** — 繁體中文 + English, switchable at runtime
- `AppSettings` ChangeNotifier + `InheritedNotifier` — reactive theme / locale / profile

## Key files

| Area | Path |
| --- | --- |
| App shell & nav | `lib/app/` |
| Home | `lib/features/home/` |
| Activities | `lib/features/action_support/` |
| Chat | `lib/features/chat/` |
| About You / Follow-up | `lib/features/personalization/` · `lib/features/follow_up/` |
| Settings / FAQ / Privacy | `lib/features/settings/` |
| Calm / Breathing | `lib/features/wellbeing/` |
| Analytics | `lib/features/analytics/` |

## TODO

- [ ] **Voice input** — wire `speech_to_text` package in `chat_page.dart` (`_toggleVoice`)
- [ ] **Illustrations** — replace `FigurePlaceholder` amber boxes with real artwork. See **[IMAGES.md](./IMAGES.md)** for prompts and drop-in instructions.
- [ ] **Guest persistence** — save locale + high-contrast to `shared_preferences` for guest sessions
- [ ] **Remote content** — move daily suggestions, tiny steps, and opener lines to remote config
- [ ] **Local notifications** — follow-up reminders via `flutter_local_notifications`
- [ ] **Firestore rules** — harden security rules (template in `SETUP_FIREBASE.md`)
- [ ] **Community resources** — replace demo data with real HK elder-service listings
- [ ] **Scripted chat English** — add English scripted replies to `ScriptedChatBackend`

## Docs

| File | What's in it |
| --- | --- |
| `README.md` | This file |
| `REPORT.md` | Capability snapshot |
| `SETUP_FIREBASE.md` | Firebase setup steps |
| `IMAGES.md` | Image-prompt checklist for illustration swap-in |

---

**Contact / privacy:** zhaojyxs@connect.hku.hk — 香港大學 趙先生
