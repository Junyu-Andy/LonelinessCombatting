/// 1020o 第三节 (decision 0066) — 「安靜時段」, the window the elder sets in
/// 自己 → 我的設定 (「由」 / 「到」, no on/off switch).  Stored on
/// `users/{uid}.quietHoursStart` / `quietHoursEnd` as Hong Kong "HH:mm";
/// the push senders (functions/quiet_hours.js) hold personal pushes inside
/// it until it ends.
///
/// The allowed range (Junyu 10/20, decided).  Change it HERE and in
/// `functions/quiet_hours.js` (RANGE) and in `firestore.rules`
/// (`quietStartValues` / `quietEndValues`); `functions/test/
/// quiet_hours_1020o_test.js` fails while the three differ.  The research
/// pushes at 08:30, 10:00 and 19:00 stay outside every allowed window.
library;

class QuietHoursRange {
  QuietHoursRange._();

  /// 「由」: 20:00 … 23:00.
  static const String startEarliest = '20:00';
  static const String startLatest = '23:00';

  /// 「到」: 06:00 … 08:00.
  static const String endEarliest = '06:00';
  static const String endLatest = '08:00';

  /// Half-hour steps.
  static const int stepMinutes = 30;

  /// Shown until the elder picks: the global window's default
  /// (`app_config/reminders`, functions/quiet_hours.js DEFAULT_START /
  /// DEFAULT_END), which the server uses for anyone without own values.
  static const String defaultStart = '22:00';
  static const String defaultEnd = '08:00';

  /// The 「由」 choices, earliest first.
  static List<String> get startOptions => _steps(startEarliest, startLatest);

  /// The 「到」 choices, earliest first.
  static List<String> get endOptions => _steps(endEarliest, endLatest);

  static final RegExp _hhmm = RegExp(r'^([01][0-9]|2[0-3]):([0-5][0-9])$');

  /// Minutes since midnight; null when [v] is not "HH:mm".
  static int? minutesOf(String? v) {
    final m = v == null ? null : _hhmm.firstMatch(v);
    if (m == null) return null;
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  static String format(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  static List<String> _steps(String from, String to) => [
        for (var m = minutesOf(from)!;
            m <= minutesOf(to)!;
            m += stepMinutes)
          format(m),
      ];

  /// What the server uses for a stored 「由」: the value moved into the
  /// range, or [defaultStart] when it is missing or malformed.
  static String effectiveStart(String? stored) =>
      _clamp(stored, startEarliest, startLatest) ?? defaultStart;

  /// What the server uses for a stored 「到」 (see [effectiveStart]).
  static String effectiveEnd(String? stored) =>
      _clamp(stored, endEarliest, endLatest) ?? defaultEnd;

  static String? _clamp(String? v, String lo, String hi) {
    final m = minutesOf(v);
    if (m == null) return null;
    return format(m.clamp(minutesOf(lo)!, minutesOf(hi)!));
  }
}
