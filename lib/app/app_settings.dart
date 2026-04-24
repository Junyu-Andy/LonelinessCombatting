import 'package:flutter/widgets.dart';

import '../features/auth/data/user_profile.dart';

/// Single source of truth for user-facing preferences that need to apply
/// app-wide (locale, high-contrast, current signed-in profile).
///
/// Lives above [MaterialApp] via [ChangeNotifierProvider]-style inheritance
/// (see [AppSettingsScope]) so any widget can listen without pulling in
/// `provider` / `riverpod`.
class AppSettings extends ChangeNotifier {
  AppSettings({
    Locale locale = const Locale('zh'),
    bool highContrast = false,
    UserProfile? profile,
  })  : _locale = locale,
        _highContrast = highContrast,
        _profile = profile;

  Locale _locale;
  bool _highContrast;
  UserProfile? _profile;

  Locale get locale => _locale;
  bool get highContrast => _highContrast;
  UserProfile? get profile => _profile;
  bool get isSignedIn => _profile != null;

  set locale(Locale value) {
    if (_locale == value) return;
    _locale = value;
    notifyListeners();
  }

  set highContrast(bool value) {
    if (_highContrast == value) return;
    _highContrast = value;
    notifyListeners();
  }

  set profile(UserProfile? value) {
    _profile = value;
    if (value?.preferredLanguage != null) {
      _locale = Locale(value!.preferredLanguage!);
    }
    if (value?.highContrast != null) {
      _highContrast = value!.highContrast!;
    }
    notifyListeners();
  }
}
