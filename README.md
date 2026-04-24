# Companion Demo (陪伴型 App Demo)

A Flutter-based demo of a companion app designed to help older adults
navigate everyday loneliness. The product wraps four cooperating modules —
**trust building → context understanding → action support → steady
follow-up** — around a gentle, low-pressure interface with elder-friendly
type sizes, big tap targets, and optional high-contrast theming.

> Status: design + interaction demo. Most interactions log events but the
> backend (Firestore) is only wired up for auth and profile today. See the
> Roadmap section.

---

## Quick start

```bash
flutter pub get
flutter run
```

The app boots in **guest mode** when Firebase isn't configured, so you can
explore the UI without credentials. Language and high-contrast toggles
still work; the login page shows an amber "guest mode" banner.

To turn real email/password auth on, follow **[SETUP_FIREBASE.md](./SETUP_FIREBASE.md)**.

## Tech stack

- **Flutter** (Dart 3.9+) targeting Android, iOS, web, macOS, Windows, Linux.
- **Material 3** theming with a custom elder-friendly base theme
  (large type, tall buttons, comfortable density) and a high-contrast variant.
- **Firebase Auth** (email/password) and **Cloud Firestore** for profile +
  analytics persistence.
- **flutter_localizations** + generated `AppLocalizations` (繁體中文 / English).
- No external state-management package — a small `ChangeNotifier`
  (`AppSettings`) surfaced through `InheritedNotifier` keeps theme, locale
  and the current profile in sync across the tree.

## Feature map

| Module | File entry point | Purpose |
| --- | --- | --- |
| Auth | `lib/features/auth/` | Email/password sign-in & sign-up, profile capture, guest-mode fallback |
| Home | `lib/features/home/presentation/pages/home_page.dart` | Greeting hero, today's vibe, social-log card, quick actions |
| Context | `lib/features/context/presentation/pages/` | Quick check-in, social map, reflection |
| Action support | `lib/features/action_support/presentation/pages/action_support_page.dart` | Tiny next steps, opener lines, activity suggestions |
| Follow-up | `lib/features/follow_up/presentation/pages/follow_up_page.dart` | Reminders, weekly progress, pace adjustment, celebrations |
| Wellbeing | `lib/features/wellbeing/presentation/pages/calm_page.dart` | Guided breathing + 5-4-3-2-1 grounding |
| Crisis | `lib/features/crisis/presentation/pages/emergency_support_page.dart` | Hotlines + immediate help |
| Resources | `lib/features/resources/presentation/pages/community_resources_page.dart` | Elder centres, events, volunteer services |
| Settings | `lib/features/settings/presentation/pages/settings_page.dart` | Font scale, high-contrast, language, profile, sign-out |

## Architecture notes

- `lib/app/` holds the root-level scaffolding: `MyApp`, `MainShell` (bottom
  nav), theme, and the `AppSettings` notifier plus its inherited scope.
- Each feature follows `lib/features/<name>/data|presentation/pages|widgets/`.
- `lib/shared/widgets/figure_placeholder.dart` is a highlighted box that
  marks where a real illustration / photo / map should eventually sit. The
  design brief for each placeholder is embedded in the source.
- Localization: strings live in `lib/l10n/app_{en,zh}.arb`; the Dart
  classes in `lib/l10n/app_localizations*.dart` are also committed to the
  repo (matching existing project convention).

## Accessibility

- Base body text size 20px with 1.55 line-height; headlines from 22–32px.
- Buttons are minimum 56–60px tall.
- **High-contrast mode** (Settings → 顯示設定): swaps to pure black-on-white
  with 2px borders. Controlled by `AppSettings.highContrast`, applied via
  `AppTheme.highContrast`.
- **Language switcher** (Settings → 語言): toggles between 繁體中文 and
  English; takes effect immediately. Persisted per-user in Firestore.

## Analytics / data collection

User behaviour is recorded through `AnalyticsService`
(`lib/features/analytics/data/analytics_service.dart`). Every signed-in
session writes events to `users/{uid}/events/`; guest sessions are buffered
in memory and printed in debug builds.

What's captured today:

- **Session lifecycle** — `session_start`, `session_end` with
  `duration_seconds` (app foreground/background time).
- **Tab dwell time** — `tab_view` with `tab` + `duration_seconds` as the
  user moves around the bottom nav.
- **Check-in submissions** — mood / loneliness / social-energy values.
- **Social log entries** — who the user said they reached out to, the
  written summary length, and the feeling chip selected.
- **Conversation openers** — which opener was copied and to whom.
- **Navigation into crisis surfaces** — when the emergency / calm / resources
  pages are opened.
- **Auth events** — sign-up, sign-in, sign-out.

See **[REPORT.md](./REPORT.md)** for a snapshot of current capabilities and
what's missing.

## Roadmap (short-term)

- Persist locale + high-contrast to disk for guest sessions
  (`shared_preferences`).
- Remote config for the daily suggestion, tiny steps, and opener copy.
- Replace the `FigurePlaceholder` boxes with real illustrations.
- Harden Firestore rules (see `SETUP_FIREBASE.md`).

## Licence

Not yet specified — treat as internal prototype.
