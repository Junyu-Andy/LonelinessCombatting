import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../context/presentation/pages/check_in_arm_a.dart';

/// Top-of-Today greeting band, warm-restyle pass.
///
/// Warm gradient by time-of-day, deep-brown text (not white), bottom-only
/// rounded corners. Hosts an inline "today mood" row that lets the user
/// pick one of three emoji shortcuts; tapping any shortcut saves the
/// mood for today and opens the Siu Yan check-in (Arm A) with that
/// value pre-selected. The inline row hides itself once today's mood
/// has been recorded.
class GreetingHero extends StatefulWidget {
  const GreetingHero({super.key});

  @override
  State<GreetingHero> createState() => _GreetingHeroState();
}

class _GreetingHeroState extends State<GreetingHero> {
  // null = unknown / loading, false = not submitted, true = submitted today.
  bool? _moodSubmittedToday;

  String _todayKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_moodSubmittedToday == null) {
      _checkSubmitted();
    }
  }

  Future<void> _checkSubmitted() async {
    final profile = AppSettingsScope.read(context).profile;
    if (profile == null) {
      if (mounted) setState(() => _moodSubmittedToday = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(profile.uid)
          .collection('daily_mood')
          .doc(_todayKey())
          .get();
      if (mounted) setState(() => _moodSubmittedToday = doc.exists);
    } catch (_) {
      if (mounted) setState(() => _moodSubmittedToday = false);
    }
  }

  Future<void> _saveAndOpen(int value) async {
    final profile = AppSettingsScope.read(context).profile;
    if (profile != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(profile.uid)
            .collection('daily_mood')
            .doc(_todayKey())
            .set({
          'value': value,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Graceful degradation: guest mode / offline.
      }
    }
    if (!mounted) return;
    setState(() => _moodSubmittedToday = true);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CheckInArmA(initialMoodValue: value),
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
    // Research Review v2 Item 7: 4-branch greeting schedule.
    if (hour >= 5 && hour < 11) {
      greetingBase = l10n.greetingMorning;
    } else if (hour >= 11 && hour < 18) {
      greetingBase = l10n.greetingAfternoon;
    } else if (hour >= 18 && hour < 23) {
      greetingBase = l10n.greetingEvening;
    } else {
      greetingBase = l10n.greetingNight;
    }

    // Warm gradient palette by time-of-day.
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
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
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
          const SizedBox(height: 8),
          Text(
            // Research Review v2 Item 3: tagline in l10n for trademark swap.
            l10n.greetingTagline,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: secondaryInk,
              height: 1.35,
            ),
          ),
          if (_moodSubmittedToday == false) ...[
            const SizedBox(height: 18),
            _InlineMoodRow(
              isEn: isEn,
              primaryInk: primaryInk,
              secondaryInk: secondaryInk,
              onPick: _saveAndOpen,
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineMoodRow extends StatelessWidget {
  final bool isEn;
  final Color primaryInk;
  final Color secondaryInk;
  final void Function(int value) onPick;

  const _InlineMoodRow({
    required this.isEn,
    required this.primaryInk,
    required this.secondaryInk,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.mood, color: primaryInk, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isEn
                  ? "How's today? Tap one to tell me"
                  : '今日感覺點？撳一撳話我知',
              style: TextStyle(
                fontSize: 14,
                color: primaryInk,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _EmojiChip(emoji: '🙁', onTap: () => onPick(2)),
          const SizedBox(width: 6),
          _EmojiChip(emoji: '😐', onTap: () => onPick(3)),
          const SizedBox(width: 6),
          _EmojiChip(emoji: '🙂', onTap: () => onPick(4)),
        ],
      ),
    );
  }
}

class _EmojiChip extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;

  const _EmojiChip({required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.7),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(
            child: Text(emoji, style: const TextStyle(fontSize: 22)),
          ),
        ),
      ),
    );
  }
}
