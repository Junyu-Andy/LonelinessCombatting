# Firebase setup

This project uses **Firebase Auth** for email/password login and **Cloud
Firestore** for storing the user profile (name, age group, emergency
contact, preferred language, high-contrast preference).

Until Firebase is configured, the app still boots — the `AuthService`
reports `available = false`, the Login page shows an amber "guest mode"
banner, and the AuthGate lets you into `MainShell` without authentication.
Language and high-contrast settings continue to work.

Finish the steps below to turn real auth on.

## 1. Create a Firebase project

1. Go to <https://console.firebase.google.com/>.
2. Click **Add project** → give it a name (e.g. `companion-demo-dev`).
3. Disable Google Analytics for now (optional).

## 2. Enable the services

In the Firebase console for your new project:

- **Build → Authentication → Get started → Sign-in method → Email/Password** → enable.
- **Build → Firestore Database → Create database**
  - Start in **test mode** during development. Remember to tighten the rules before shipping (example below).
  - Pick a region close to your users (`asia-east2` for Hong Kong).

## 3. Install the FlutterFire CLI

On your development machine:

```bash
dart pub global activate flutterfire_cli
# If `firebase` CLI is not installed yet:
curl -sL https://firebase.tools | bash
firebase login
```

## 4. Configure this repo

From the project root (`LonelinessCombatting/`):

```bash
flutterfire configure
```

Pick the project you created, select the platforms you need (Android + iOS
at minimum, macOS/Windows/Web optional). The command will:

- Overwrite `lib/firebase_options.dart` with real keys.
- Drop `android/app/google-services.json`.
- Drop `ios/Runner/GoogleService-Info.plist` (and macos equivalent).

## 5. Install deps & run

```bash
flutter pub get
flutter run
```

The app should now show the login / sign-up flow. The first sign-up writes
a document at `users/{uid}` with the fields defined in
`UserProfile.toMap()`.

## 6. Firestore security rules (before shipping)

A ready-to-publish rules file lives at the repo root: **`firestore.rules`**.
It covers:

- `users/{uid}/**` — owner read/write only (profile, events, memory,
  action_plans, thought_records).
- `meta/arm_counter` — any signed-in user may read; writes must be
  exactly an `aCount` or `bCount` increment-by-one (the
  `ArmAssigner.assign` transaction).

To publish:

```bash
# Once, from the project root:
firebase deploy --only firestore:rules
```

Or paste the file's contents into the Firebase Console →
Firestore → Rules → Publish.

### Collections produced by this app

| Path | Written by | Purpose |
| --- | --- | --- |
| `users/{uid}` | `AuthService` | Profile, arm, consent flags |
| `users/{uid}/events/{id}` | `AnalyticsService` | Session + module events |
| `users/{uid}/memory/{moduleId}/entries/{id}` | `MemoryStore` | M2/M3/M5 summaries (gated by `consent.transcriptRetention`) |
| `users/{uid}/action_plans/{id}` | M7 + M4/M6 hand-offs | If-then plans, follow-up outcomes |
| `users/{uid}/thought_records/{id}` | M4 | Cognitive restructuring records, optional `linkedActionPlanId` |
| `meta/arm_counter` | `ArmAssigner` (txn) | 1:1 balanced RCT randomisation |

## Troubleshooting

- **"DefaultFirebaseOptions.currentPlatform has not been configured"** on
  startup → you haven't run `flutterfire configure` yet. The placeholder in
  `lib/firebase_options.dart` throws this deliberately; `main.dart` catches
  it and falls back to guest mode.
- **iOS build fails on `GoogleService-Info.plist`** → make sure the file is
  added to the Runner target in Xcode (not just copied into the folder).
- **`permission-denied` on Firestore** → your rules are too strict; start
  with the example above and iterate.
