/// Usage-frequency copy read from Firestore (T20, decision 0028).
///
/// Research side (10/7): recommend daily use, at least 5 times a week,
/// never compulsory.  The final wording comes after the ICF is signed
/// off, so every participant-facing line that talks about how often to
/// use the app reads from the `app_config/usage_copy` document instead
/// of being hard-coded.
///
/// Until the research team writes a final line, nothing changes: a
/// missing document, a failed read, a missing or empty field, or a
/// value still carrying the 【占位】 marker all fall back to the text the
/// app shows today (passed in by the caller).  Both arms read the same
/// document and get the same text — there is no arm check here.
///
/// Only the keys in [keys] are honoured.  Each key has a `_zh` and an
/// `_en` field, e.g. `siu_yan_tile_subtitle_zh`.
///
/// Pure Dart (no Firestore) so the agent registry can use it;
/// `usage_copy_loader.dart` reads the document once at startup.
library;

class UsageCopy {
  const UsageCopy([this._values = const {}]);

  final Map<String, String> _values;

  /// Firestore document holding the copy.  Read-only for clients.
  static const String remotePath = 'app_config/usage_copy';

  /// Same marker as the rule-reply pool (T15): a value containing it is
  /// treated as not yet written.
  static const String placeholderMarker = '【占位】';

  // Sites that mention how often to use the app (T20 report §1).
  static const String siuYanFirstIntro = 'siu_yan_first_intro';
  static const String siuYanTileSubtitle = 'siu_yan_tile_subtitle';
  static const String siuYanProfileOpening = 'siu_yan_profile_opening';
  static const String siuYanProfileMoodCapability =
      'siu_yan_profile_mood_capability';
  static const String ahJanAhBakProfileWeeklyCapability =
      'ah_jan_ah_bak_profile_weekly_capability';

  /// `{weeks}` in the configured text is replaced with the theme count.
  static const String reminiscenceLandingIntro = 'reminiscence_landing_intro';
  static const String faqSkipCheckinAnswer = 'faq_skip_checkin_answer';

  static const List<String> keys = [
    siuYanFirstIntro,
    siuYanTileSubtitle,
    siuYanProfileOpening,
    siuYanProfileMoodCapability,
    ahJanAhBakProfileWeeklyCapability,
    reminiscenceLandingIntro,
    faqSkipCheckinAnswer,
  ];

  /// The active copy: empty — so every site shows today's text — until
  /// `UsageCopyLoader.load` reads the document.  Tests set it directly.
  static UsageCopy current = const UsageCopy();

  /// Pure parse used by the loader and tests.  Keeps only known keys whose
  /// value is a non-empty string without the placeholder marker.
  static UsageCopy fromMap(Map<String, dynamic> map) {
    final values = <String, String>{};
    for (final key in keys) {
      for (final lang in const ['zh', 'en']) {
        final field = '${key}_$lang';
        final value = map[field];
        if (value is String &&
            value.trim().isNotEmpty &&
            !value.contains(placeholderMarker)) {
          values[field] = value;
        }
      }
    }
    return UsageCopy(values);
  }

  /// The configured text for [key], or [fallback] (today's text).
  String text(String key, {required bool isEn, required String fallback}) =>
      _values['${key}_${isEn ? 'en' : 'zh'}'] ?? fallback;
}
