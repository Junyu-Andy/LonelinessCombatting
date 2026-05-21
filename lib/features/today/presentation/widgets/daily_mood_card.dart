/// Daily mood banner shown on TodayPage.
///
/// Shows a 5-face emoji picker. Once tapped, saves to
/// `users/{uid}/daily_mood/{YYYY-MM-DD}` and shows a confirmation.
/// Does not re-show if already submitted today.
///
/// Arm A: confirmation view shows a CTA to open Siu Yan (check-in).
/// Arm B: confirmation view only.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../context/presentation/pages/check_in_arm_a.dart';

class DailyMoodCard extends StatefulWidget {
  const DailyMoodCard({super.key});

  @override
  State<DailyMoodCard> createState() => _DailyMoodCardState();
}

class _DailyMoodCardState extends State<DailyMoodCard> {
  /// null = still loading, false = not submitted, true = submitted
  bool? _alreadySubmitted;
  bool _submitted = false;
  int? _selectedValue;

  static const _faces = <(int, String, String)>[
    (1, '😔', '好差'),
    (2, '🙁', '差'),
    (3, '😐', '麻麻地'),
    (4, '🙂', '幾好'),
    (5, '😊', '好好'),
  ];

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
    if (_alreadySubmitted == null) {
      _checkAlreadySubmitted();
    }
  }

  Future<void> _checkAlreadySubmitted() async {
    final profile = AppSettingsScope.read(context).profile;
    if (profile == null) {
      setState(() => _alreadySubmitted = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(profile.uid)
          .collection('daily_mood')
          .doc(_todayKey())
          .get();
      if (mounted) {
        setState(() => _alreadySubmitted = doc.exists);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _alreadySubmitted = false);
      }
    }
  }

  Future<void> _saveMood(int value) async {
    setState(() {
      _selectedValue = value;
      _submitted = true;
    });
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
        // Graceful degradation: Firebase unavailable in guest mode.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Loading state
    if (_alreadySubmitted == null) return const SizedBox.shrink();
    // Already submitted today
    if (_alreadySubmitted == true) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: _submitted ? _buildConfirmation(theme) : _buildPicker(theme),
        ),
      ),
    );
  }

  Widget _buildPicker(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '你今日感覺點呀？',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: _faces.map((face) {
            return Expanded(
              child: GestureDetector(
                onTap: () => _saveMood(face.$1),
                child: SizedBox(
                  height: 64,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(face.$2,
                          style: const TextStyle(fontSize: 32)),
                      const SizedBox(height: 4),
                      Text(
                        face.$3,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildConfirmation(ThemeData theme) {
    final selected = _faces.firstWhere(
      (f) => f.$1 == _selectedValue,
      orElse: () => _faces[2],
    );
    final isArmA = Arm.isA(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(selected.$2, style: const TextStyle(fontSize: 36)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '多謝你分享！',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '今日嘅心情：${selected.$3}',
                    style: TextStyle(
                      fontSize: 15,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (isArmA) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CheckInArmA(),
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline, size: 20),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '想同小欣傾下偈嗎？',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
