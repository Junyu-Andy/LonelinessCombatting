import 'package:flutter/widgets.dart';

import '../features/auth/data/user_profile.dart';

/// Single source of truth for user-facing preferences that need to apply
/// app-wide (locale, high-contrast, current signed-in profile).
///
/// Lives above [MaterialApp] via [ChangeNotifierProvider]-style inheritance
/// (see [AppSettingsScope]) so any widget can listen without pulling in
/// `provider` / `riverpod`.
/// P4.1 — supported MediaQuery text scale multipliers for the
/// elderly-friendly font sizing toggle in Settings. Stays inside a
/// safe layout range (1.0–1.30) so existing pages don't reflow into
/// a broken state at the largest setting.
enum AppFontScale { standard, large, xLarge }

extension AppFontScaleX on AppFontScale {
  double get multiplier => switch (this) {
        AppFontScale.standard => 1.0,
        AppFontScale.large => 1.15,
        AppFontScale.xLarge => 1.30,
      };
}

class AppSettings extends ChangeNotifier {
  AppSettings({
    Locale locale = const Locale('zh'),
    bool highContrast = false,
    AppFontScale fontScale = AppFontScale.standard,
    UserProfile? profile,
  })  : _locale = locale,
        _highContrast = highContrast,
        _fontScale = fontScale,
        _profile = profile;

  Locale _locale;
  bool _highContrast;
  AppFontScale _fontScale;
  UserProfile? _profile;

  Locale get locale => _locale;
  bool get highContrast => _highContrast;
  AppFontScale get fontScale => _fontScale;
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

  set fontScale(AppFontScale value) {
    if (_fontScale == value) return;
    _fontScale = value;
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
