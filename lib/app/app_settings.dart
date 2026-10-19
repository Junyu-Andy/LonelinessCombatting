import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/auth/data/user_profile.dart';

/// Single source of truth for user-facing preferences that need to apply
/// app-wide (locale, high-contrast, font scale, the two notification
/// switches, current signed-in profile).
///
/// Lives above [MaterialApp] via [ChangeNotifierProvider]-style inheritance
/// (see [AppSettingsScope]) so any widget can listen without pulling in
/// `provider` / `riverpod`.
///
/// T37: the display settings (font scale, high contrast) and the two
/// notification switches (安靜時段, 語音讀出內容) are kept on the device with
/// `shared_preferences`.  [restore] reads them in `main()` before the first
/// frame; every setter writes its value back.  Before T37 they lived only
/// in memory and reset to the defaults each time the App was closed.
/// P4.1 — supported MediaQuery text scale multipliers for the
/// elderly-friendly font sizing toggle in Settings.
///
/// 10/19: five even steps (Junyu) — 標準 1.06 · 稍大 1.12 · 大 1.18 ·
/// 較大 1.24 · 特大 1.30.  Nothing above 1.30, the size every page is
/// checked at.  Enum names are stored on the phone: the old three keep
/// theirs (標準 1.0 → 1.06, 大 1.15 → 1.18, 特大 1.30 unchanged).
enum AppFontScale { standard, slightlyLarge, large, larger, xLarge }

extension AppFontScaleX on AppFontScale {
  double get multiplier => switch (this) {
        AppFontScale.standard => 1.06,
        AppFontScale.slightlyLarge => 1.12,
        AppFontScale.large => 1.18,
        AppFontScale.larger => 1.24,
        AppFontScale.xLarge => 1.30,
      };
}

/// The text scale the App applies: phone setting × the App level.  10/15
/// pilot: a big phone setting × 大字 overflowed the cards, so the result
/// stays between 0.8 and 1.30 (特大).
double combinedTextScale(double system, AppFontScale app) =>
    (system * app.multiplier).clamp(0.8, AppFontScale.xLarge.multiplier);

class AppSettings extends ChangeNotifier {
  AppSettings({
    Locale locale = const Locale('zh'),
    bool highContrast = false,
    AppFontScale fontScale = AppFontScale.standard,
    bool quietHours = true,
    bool voiceReadback = false,
    UserProfile? profile,
    SharedPreferences? store,
  })  : _locale = locale,
        _highContrast = highContrast,
        _fontScale = fontScale,
        _quietHours = quietHours,
        _voiceReadback = voiceReadback,
        _profile = profile,
        _store = store;

  /// T37 — keys in the device store.  Font scale is stored by enum name
  /// (`standard` / `large` / `xLarge`), the rest as booleans.
  static const String keyFontScale = 'display.fontScale';
  static const String keyHighContrast = 'display.highContrast';
  static const String keyQuietHours = 'notifications.quietHours';
  static const String keyVoiceReadback = 'notifications.voiceReadback';

  /// T37 — build the settings from what the device stored.  Never throws:
  /// a missing or unreadable store, or an unknown value, gives that
  /// setting's default.  Called once in `main()` before the first frame.
  static Future<AppSettings> restore({
    Locale locale = const Locale('zh'),
  }) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      if (kDebugMode) debugPrint('[AppSettings] restore failed: $e');
    }
    return AppSettings.fromStore(prefs, locale: locale);
  }

  /// The pure part of [restore]: read every persisted setting from
  /// [prefs] (null = nothing stored, use the defaults) and keep [prefs]
  /// so later changes are written back.
  factory AppSettings.fromStore(
    SharedPreferences? prefs, {
    Locale locale = const Locale('zh'),
  }) {
    bool readBool(String key, bool fallback) {
      try {
        return prefs?.getBool(key) ?? fallback;
      } catch (_) {
        return fallback;
      }
    }

    AppFontScale readFontScale() {
      try {
        final name = prefs?.getString(keyFontScale);
        for (final scale in AppFontScale.values) {
          if (scale.name == name) return scale;
        }
      } catch (_) {}
      return AppFontScale.standard;
    }

    return AppSettings(
      locale: locale,
      highContrast: readBool(keyHighContrast, false),
      fontScale: readFontScale(),
      quietHours: readBool(keyQuietHours, true),
      voiceReadback: readBool(keyVoiceReadback, false),
      store: prefs,
    );
  }

  Locale _locale;
  bool _highContrast;
  AppFontScale _fontScale;
  bool _quietHours;
  bool _voiceReadback;
  UserProfile? _profile;
  final SharedPreferences? _store;

  /// Pilot decision: the English UI doesn't lay out well (long strings
  /// overflow the elderly-friendly large-type cards), so the app is
  /// Cantonese-only for now.  Flip to true to bring English back — the
  /// language pickers in Settings / Login are also gated on this.
  static const bool englishEnabled = false;

  /// Forced to zh while [englishEnabled] is false, so every `isEn` check
  /// across the app resolves to Cantonese regardless of any stored or
  /// profile-supplied preference.
  Locale get locale => englishEnabled ? _locale : const Locale('zh');
  bool get highContrast => _highContrast;
  AppFontScale get fontScale => _fontScale;

  /// 「通知 → 安靜時段」 (default on).  T37: persisted; not yet read by the
  /// reminder code — the switch is the same as before, only remembered.
  bool get quietHours => _quietHours;

  /// 「通知 → 語音讀出內容」 (default off).  T37: persisted, same as above.
  bool get voiceReadback => _voiceReadback;
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
    _persist((p) => p.setBool(keyHighContrast, value));
    notifyListeners();
  }

  set fontScale(AppFontScale value) {
    if (_fontScale == value) return;
    _fontScale = value;
    _persist((p) => p.setString(keyFontScale, value.name));
    notifyListeners();
  }

  set quietHours(bool value) {
    if (_quietHours == value) return;
    _quietHours = value;
    _persist((p) => p.setBool(keyQuietHours, value));
    notifyListeners();
  }

  set voiceReadback(bool value) {
    if (_voiceReadback == value) return;
    _voiceReadback = value;
    _persist((p) => p.setBool(keyVoiceReadback, value));
    notifyListeners();
  }

  set profile(UserProfile? value) {
    _profile = value;
    if (value?.preferredLanguage != null) {
      _locale = Locale(value!.preferredLanguage!);
    }
    // T37: nothing in the App writes `users.highContrast` today, so this
    // never overrides the value saved on the phone; if it ever does, the
    // profile value wins at sign-in and is then saved locally too.
    if (value?.highContrast != null) {
      _highContrast = value!.highContrast!;
      _persist((p) => p.setBool(keyHighContrast, _highContrast));
    }
    notifyListeners();
  }

  /// Write one setting to the device store.  Fire-and-forget: a store
  /// failure must never block the UI or surface to the participant.
  void _persist(Future<bool> Function(SharedPreferences store) write) {
    final store = _store;
    if (store == null) return;
    try {
      write(store).catchError((Object e) {
        if (kDebugMode) debugPrint('[AppSettings] persist failed: $e');
        return false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[AppSettings] persist failed: $e');
    }
  }
}
