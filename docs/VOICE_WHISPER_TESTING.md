# Voice input (Whisper fallback) — testing guide

The mic button now has two paths, chosen automatically:

- **Native on-device STT** (`speech_to_text`) — used when the device has an OS
  speech recogniser (iOS always; most Google-services Android). Tap to start /
  stop.
- **Whisper "hold to talk"** — used when there is **no** OS recogniser (many
  Chinese-ROM Android phones). Long-press to record, release to transcribe via
  the `transcribeAudio` Cloud Function. This is the WhatsApp-style path.

To force the Whisper path on any device for testing, set
`_forceWhisper = true` in `lib/core/voice/voice_input_button.dart` (ship as
`false`).

---

## One-time server setup (required before Whisper works)

```bash
# 1. Install the new Flutter deps
flutter pub get

# 2. Set the Whisper API key (OpenAI). Paste the key when prompted.
firebase functions:secrets:set OPENAI_API_KEY

# 3. Deploy the new function
firebase deploy --only functions
```

Until the secret is set + deployed, the button records but shows
"聲音轉文字喺伺服器嗰邊仲未設定好" (server not configured) — that's expected.

---

## Android test flow (Windows + phone, you can do this now)

1. `flutter pub get`, then the three server steps above.
2. `flutter run` on the Android phone (keep the console visible for logs).
3. Sign in (a tester account is fine).
4. Open any input with a mic — e.g. tap **小欣**, or the "計劃一個小行動" note
   field.
5. On the Chinese-ROM phone the mic is now the **hold-to-talk** button
   (tooltip: 「按住講」). A plain tap shows "按住個掣講嘢，講完放手".
6. **Long-press** the mic → the icon turns red (recording) → say a Cantonese
   sentence → **release**.
7. A spinner shows briefly (uploading + transcribing), then the transcript
   drops into the text field.
8. First use will ask for microphone permission — allow it.
9. Send the message / save as normal.

### What "good" looks like
- Cantonese speech comes back as reasonable Chinese text (Whisper transcribes
  Cantonese acceptably; it may render some words in written Chinese).
- Recording → text round-trip takes ~2–5s depending on clip length + network.

### If it doesn't work — where to look
| Symptom | Cause / check |
|---|---|
| "聲音轉文字…仲未設定好" | `OPENAI_API_KEY` not set or function not deployed. Redo server setup. |
| "聽唔到喎 — 按住個掣再講多次" | Empty clip or Whisper returned nothing / errored. Check console + `firebase functions:log --only transcribeAudio`. |
| Asks for mic permission repeatedly | Deny → grant in Android app settings. |
| Button is tap-to-toggle (not hold) | This phone HAS a native recogniser, so it's using on-device STT, not Whisper. Set `_forceWhisper = true` to test the Whisper path. |
| Build error after pull | You didn't run `flutter pub get` (new deps: record, path_provider). |

Function logs: `firebase functions:log --only transcribeAudio`
(look for `whisper 4xx/5xx` lines = API errors, e.g. bad key or quota).

---

## iOS test plan (rough — hand this to an LLM to expand step-by-step)

You can't connect an iPhone right now; here's the outline for later. iOS has a
working native recogniser, so **by default iOS uses on-device STT, not
Whisper**. Test both.

**A. Build & install on the iPhone/iPad (needs a Mac + Xcode, or Codemagic):**
1. `flutter pub get`.
2. Open `ios/Runner.xcworkspace` in Xcode; set the Team / signing; confirm the
   bundle id matches Firebase (`GoogleService-Info.plist`).
3. `flutter run` with the device plugged in (or archive → TestFlight).
4. `Info.plist` already has `NSMicrophoneUsageDescription` +
   `NSSpeechRecognitionUsageDescription`, so no plist edits needed.

**B. Test the native on-device path (default on iOS):**
1. Open a chat, tap the mic, allow mic + speech-recognition permission.
2. Speak Cantonese; confirm it transcribes on-device (works offline in
   airplane mode if the iOS Cantonese pack is installed).

**C. Test the Whisper path on iOS (optional, to confirm the fallback):**
1. Set `_forceWhisper = true` in
   `lib/core/voice/voice_input_button.dart`, rebuild.
2. Complete the server setup (OPENAI_API_KEY + deploy) if not done.
3. The mic becomes hold-to-talk; long-press → speak → release → transcript.
4. Set `_forceWhisper` back to `false` before shipping.

**Things an assisting LLM should help you with:** Xcode signing / provisioning
profiles, adding the device as a test device, reading `flutter run` /
Console.app logs if the mic or the function call fails, and interpreting
`firebase functions:log` output.
