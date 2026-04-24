# Companion Demo · 陪伴型 App Demo

> Built by **HKU Department of Industrial & Manufacturing Systems Engineering**
> 香港大學工業及製造系統工程學系

## 🤝 What is this?

A mobile app that helps **older adults in Hong Kong gently push back
against loneliness**. It is not a clinical tool. Think of it as a patient,
low-pressure pocket companion that remembers who matters to the user,
nudges small daily connections, and sits next to them during rough
moments.

The app is a **Flutter design + interaction demo** — all surfaces are
interactive, auth + profile are on Firebase, the chat module talks to
DeepSeek (falls back to scripted replies if no key is configured).

## ✨ What users can do

| Inside the app | One-sentence summary |
| --- | --- |
| 🏠 **Home (首頁)** | Friendly greeting, today's vibe, a social-log (who did I talk to today?), and quick-action tiles |
| 🌿 **做點活動** | Warm, positive prompts for pleasant micro-activities — "send aunt a text", "sit in the park 15 mins" |
| 💬 **傾偈 (Chat)** | Pick an AI companion — casual **阿暖** for small-talk, serious **李醫師** for reflection. Text or voice input |
| 👤 **了解你 (About You)** | Profile + emergency contact editor, recent check-in glance, follow-up reminders & weekly progress |
| ⚙️ **Settings gear** | High-contrast mode, language (繁中 / English), boundaries, FAQ with an **「我仲有問題」AI helpdesk** |

Plus reachable from Home: quick check-in, social map, 静一静 breathing,
community resources, emergency hotlines.

## 👵 Who it's designed for

- Hong Kong older adults (60+), Cantonese-first
- Caregivers or family who set it up
- Elder-friendly by default: body text is 20 pt with 1.55 line height,
  every primary button is at least 60 px tall, optional **high-contrast
  theme** flips everything to pure black-on-white with thick borders.

## 🗺️ How the four tabs fit together

```
┌─────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│  Home   │ → │ 做點活動 │ → │  傾偈    │ → │ 了解你   │
│ greet   │   │ feel     │   │ talk     │   │ remember │
└─────────┘   └──────────┘   └──────────┘   └──────────┘
                                                    ▲
                               Settings gear ───────┘
                               (in AppBar, every tab)
```

## 🚀 Run it

```bash
flutter pub get
flutter run
```

The app **boots even without Firebase configured** — you'll land in guest
mode where the UI, theme, and language switching all work. To enable real
login + profile storage, follow **[SETUP_FIREBASE.md](./SETUP_FIREBASE.md)**.

To enable real AI chat, see the _Chat module_ section further down.

## 🧰 Tech stack

- **Flutter** (Dart 3.9+) — Android / iOS / web / macOS / Windows / Linux.
- **Material 3** with an elder-friendly base theme + a high-contrast variant (`lib/app/app_theme.dart`).
- **Firebase Auth + Cloud Firestore** for auth, profile, and analytics writes.
- **DeepSeek API** (placeholder) for the chat personas.
- **flutter_localizations** — 繁體中文 + English, switchable at runtime.
- No extra state-management package: a `ChangeNotifier` called `AppSettings` exposed through `InheritedNotifier` carries theme / locale / profile.

## 📚 Documentation map

| File | What's in it |
| --- | --- |
| [`README.md`](./README.md) | This file — overview + where things live |
| [`REPORT.md`](./REPORT.md) | Capability snapshot (what's shipped / missing / next) |
| [`SETUP_FIREBASE.md`](./SETUP_FIREBASE.md) | Step-by-step to turn Firebase on |

---

## 🧭 Where each feature lives

### Tabs

| Tab | Entry point | Notes |
| --- | --- | --- |
| Home | `lib/features/home/presentation/pages/home_page.dart` | Greeting hero, vibe bars, social log, quick actions |
| 做點活動 | `lib/features/action_support/presentation/pages/action_support_page.dart` | Positive reframing of old "support" tab |
| 傾偈 | `lib/features/chat/presentation/pages/chat_landing_page.dart` | Persona picker → `chat_page.dart` |
| 了解你 | `lib/features/personalization/presentation/pages/personalization_page.dart` | Profile editor + recent state + follow-up |

### Surfaces reachable from Home / Activities

| Area | Entry point |
| --- | --- |
| Auth | `lib/features/auth/` |
| Quick check-in / social map / reflection | `lib/features/context/presentation/pages/` |
| 靜一靜 breathing | `lib/features/wellbeing/presentation/pages/calm_page.dart` |
| Emergency | `lib/features/crisis/presentation/pages/emergency_support_page.dart` |
| Community resources | `lib/features/resources/presentation/pages/community_resources_page.dart` |
| Follow-up page | `lib/features/follow_up/presentation/pages/follow_up_page.dart` |

### Settings (behind the AppBar gear)

`lib/features/settings/presentation/pages/settings_page.dart` — font
scale preview, high-contrast, language, notifications, profile card,
boundaries, **FAQ** (with the "我仲有問題" AI helpdesk at the bottom),
and privacy policy (`zhaojyxs@connect.hku.hk`, 香港大學 趙先生).

## 💬 Chat module

`lib/features/chat/` — three personas, each with their own avatar,
gradient, and system prompt:

| Persona | Where it appears | Purpose |
| --- | --- | --- |
| **阿暖** — `casual` | Chat tab | Light daily small-talk, warm and short |
| **李醫師** — `consult` | Chat tab | Measured, reflection-oriented |
| **小助** — `faq` | Bottom of FAQ page | Answers questions about the app itself |

All three share the same backend pipeline:

```
ChatPage ── ChatBackend (interface)
            ├── ScriptedChatBackend   (offline, canned replies — ships today)
            └── DeepseekChatBackend   (calls DeepSeek /chat/completions)
```

To wire DeepSeek for real:

1. `flutter pub add http`
2. Pass the key at run time: `--dart-define=DEEPSEEK_API_KEY=sk-…`
3. Fill in the `TODO(deepseek)` block inside `chat_backend.dart` — POST
   to `https://api.deepseek.com/chat/completions` with
   `persona.systemPrompt` as the system message.

Voice input in `chat_page.dart` is currently a visual stub (pulses the
mic for 1s, drops a placeholder string). Wire `speech_to_text` later.

## 📊 Analytics

`AnalyticsService` (`lib/features/analytics/data/analytics_service.dart`)
records behaviour to `users/{uid}/events/` in Firestore. Guest sessions
buffer in memory and flush on sign-in.

Captured events: `session_start` / `session_end` (with
`duration_seconds`), `tab_view`, `check_in_submitted`,
`social_log_entry`, `opener_copied`, `emergency_opened`, and auth
events. No PII in payloads — the social-log event stores
`summaryLength` (int) rather than the text itself.

## 🏗️ Architecture notes

- `lib/app/` — root scaffolding (`MyApp`, `MainShell` with bottom nav,
  theme, `AppSettings` notifier + scope).
- `lib/features/<name>/data|presentation/pages|widgets/` — feature slice.
- `lib/shared/widgets/figure_placeholder.dart` — highlighted amber box
  that marks where a real illustration / photo / map should sit. The
  design brief for each placeholder is embedded in the source.
- Localization: ARBs in `lib/l10n/`; the generated Dart classes are
  checked in alongside to match project convention.

## ♿ Accessibility

- Body 20 pt, line-height 1.55, headlines 22–32 pt.
- Primary buttons ≥ 60 px tall.
- **High-contrast mode** — pure black-on-white with 2 px borders on
  cards and inputs. Controlled by `AppSettings.highContrast`, applied
  via `AppTheme.highContrast`.
- **Language** — zh / en switchable at runtime via Settings → 語言;
  choice round-trips through the Firestore profile.

## 🛣️ Roadmap

- Persist locale + high-contrast to disk for guest sessions
  (`shared_preferences`).
- Remote config for the daily suggestion, tiny steps, opener copy.
- Replace `FigurePlaceholder` boxes with real illustrations.
- Harden Firestore security rules (template in `SETUP_FIREBASE.md`).
- Real voice input (`speech_to_text`) in the chat module.

## 👥 Credits & contact

Built by the **Department of Industrial & Manufacturing Systems
Engineering, The University of Hong Kong (HKU IMSE)** as a research /
teaching prototype. 香港大學工業及製造系統工程學系。

Privacy / general contact: **zhaojyxs@connect.hku.hk** — 香港大學 趙先生.

## Licence

Not yet specified — treat as internal prototype.
