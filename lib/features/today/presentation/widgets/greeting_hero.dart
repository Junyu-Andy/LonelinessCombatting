import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../context/presentation/pages/check_in_arm_a.dart';
import '../../data/mood_recorder.dart';

/// Top-of-Today greeting band (Home Layout Spec §1–2).
///
/// Warm gradient by time-of-day, deep-brown text, bottom-only rounded
/// corners.  Embeds the 5-face mood pad directly in the hero per
/// Home Layout Spec §2 — always visible, one-tap, supports multiple
/// entries per day (first = `is_primary`, rest = `supplementary`).
class GreetingHero extends StatefulWidget {
  const GreetingHero({super.key});

  @override
  State<GreetingHero> createState() => _GreetingHeroState();
}

class _GreetingHeroState extends State<GreetingHero> {
  final _recorder = MoodRecorder();
  int? _selectedMood;
  bool _hasPrimaryToday = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadTodayMood();
  }

  Future<void> _loadTodayMood() async {
    final profile = AppSettingsScope.read(context).profile;
    if (profile == null) return;
    final entry = await _recorder.latestForDate(
      uid: profile.uid,
      dateIso: MoodRecorder.dateIsoFor(DateTime.now()),
    );
    if (!mounted || entry == null) return;
    setState(() {
      _selectedMood = entry.mood;
      _hasPrimaryToday = true;
    });
  }

  Future<void> _onPick(int value, bool isEn) async {
    if (_busy) return;
    final profile = AppSettingsScope.read(context).profile;
    final isArmA = Arm.isA(context);
    setState(() {
      _selectedMood = value;
      _busy = true;
    });
    if (profile != null) {
      try {
        await _recorder.record(
          uid: profile.uid,
          mood: value,
          arm: isArmA ? 'A' : 'B',
          sourceSurface: 'home_hero',
        );
      } catch (_) {
        // Guest mode / offline — UI state already updated optimistically.
      }
    }
    if (!mounted) return;
    final wasSupplementary = _hasPrimaryToday;
    setState(() {
      _hasPrimaryToday = true;
      _busy = false;
    });
    _showRecordedToast(isEn);
    // Sprint logging: mood is now a stream of entries — the first-of-
    // day still feeds the existing daily_mood_submitted analytics event
    // so existing dashboards stay accurate; supplementary entries get
    // their own variant to avoid double-counting.
    final analytics = AnalyticsScope.of(context);
    if (wasSupplementary) {
      // Reuse the existing skip event family for now — a dedicated
      // supplementary event can be added without breaking the wire.
      analytics.logEvent('daily_mood_supplementary', {
        'mood': value,
        'source_surface': 'home_hero',
      });
    } else {
      analytics.logDailyMoodSubmitted(mood: value);
    }
    if (isArmA && !wasSupplementary && mounted) {
      _showSiuYanCta(isEn, value);
    }
  }

  void _showRecordedToast(bool isEn) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isEn ? 'Noted ☺︎' : '記低咗 ☺︎'),
        duration: const Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSiuYanCta(bool isEn, int moodValue) {
    // Arm A only: nudge to expand a few sentences with Siu Yan.  Lives
    // inside the SnackBar action so it never blocks the home surface.
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isEn
              ? 'Want to share a bit more with Siu Yan?'
              : '想同小欣講多兩句？',
        ),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: isEn ? 'Open' : '好',
          onPressed: () {
            if (!mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CheckInArmA(initialMoodValue: moodValue),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final now = DateTime.now();
    final profile = AppSettingsScope.of(context).profile;
    final displayName = profile?.displayName.trim();

    final hour = now.hour;
    final String greetingBase;
    if (hour >= 5 && hour < 11) {
      greetingBase = l10n.greetingMorning;
    } else if (hour >= 11 && hour < 18) {
      greetingBase = l10n.greetingAfternoon;
    } else if (hour >= 18 && hour < 23) {
      greetingBase = l10n.greetingEvening;
    } else {
      greetingBase = l10n.greetingNight;
    }

    final List<Color> gradient;
    if (hour >= 5 && hour < 11) {
      gradient = const [Color(0xFFF0DCC4), Color(0xFFEBCDB8)];
    } else if (hour >= 11 && hour < 18) {
      gradient = const [Color(0xFFE9D6BE), Color(0xFFE2C7B6)];
    } else {
      gradient = const [Color(0xFFE6D0BD), Color(0xFFD6B5B6)];
    }

    final greeting = displayName != null && displayName.isNotEmpty
        ? (isEn ? '$greetingBase, $displayName' : '$greetingBase，$displayName')
        : greetingBase;

    final weekdayNames = isEn
        ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        : const ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final dateLine = isEn
        ? '${weekdayNames[now.weekday - 1]}, ${now.month}/${now.day}'
        : '${now.month} 月 ${now.day} 日　${weekdayNames[now.weekday - 1]}';

    const Color primaryInk = Color(0xFF5A4334);
    const Color secondaryInk = Color(0xFF836A55);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 26),
      decoration: BoxDecoration(
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(34)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateLine,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: secondaryInk,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            greeting,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: primaryInk,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          _MoodPad(
            isEn: isEn,
            selectedMood: _selectedMood,
            onPick: (v) => _onPick(v, isEn),
            primaryInk: primaryInk,
            secondaryInk: secondaryInk,
          ),
        ],
      ),
    );
  }
}

class _MoodPad extends StatelessWidget {
  final bool isEn;
  final int? selectedMood;
  final void Function(int) onPick;
  final Color primaryInk;
  final Color secondaryInk;

  const _MoodPad({
    required this.isEn,
    required this.selectedMood,
    required this.onPick,
    required this.primaryInk,
    required this.secondaryInk,
  });

  static const _faces = <int, String>{
    1: '😔',
    2: '🙁',
    3: '😐',
    4: '🙂',
    5: '😊',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.62),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEn
                ? "How are you today? (you can log again anytime)"
                : '今日感覺點？（隨時可以再記）',
            style: TextStyle(
              fontSize: 13,
              color: const Color(0xFF6E5642),
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              for (final entry in _faces.entries)
                Expanded(
                  child: _FaceTap(
                    emoji: entry.value,
                    selected: selectedMood == entry.key,
                    onTap: () => onPick(entry.key),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FaceTap extends StatelessWidget {
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  const _FaceTap({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color.fromRGBO(194, 112, 63, 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(emoji, style: const TextStyle(fontSize: 28)),
        ),
      ),
    );
  }
}
