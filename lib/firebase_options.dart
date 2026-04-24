// PLACEHOLDER — replace with the file produced by `flutterfire configure`.
//
// Run from the project root:
//   dart pub global activate flutterfire_cli
//   firebase login
//   flutterfire configure
//
// That command will overwrite this file with platform-specific Firebase
// options pulled from your Firebase project. See SETUP_FIREBASE.md for the
// full walkthrough.
//
// Until that's done, [FirebaseBootstrap.initialize] in main.dart catches the
// failure and the app boots in "guest mode" (no login, but high-contrast and
// language settings still work).

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'DefaultFirebaseOptions.currentPlatform has not been configured. '
      'Run `flutterfire configure` — see SETUP_FIREBASE.md.',
    );
  }
}
