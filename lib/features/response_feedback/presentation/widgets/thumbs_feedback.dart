/// Thumbs up/down feedback widget rendered below agent bubbles.
///
/// Sprint 2 §2.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../data/response_feedback.dart';

class ThumbsFeedback extends StatefulWidget {
  final String agentId;
  final String moduleId;
  final String? turnRef;

  /// Stable in-memory key (e.g., the index in the turns list). Used to
  /// remember the user's chosen rating during the session and to
  /// supersede earlier feedback when re-rated.
  final String? turnKey;

  const ThumbsFeedback({
    super.key,
    required this.agentId,
    required this.moduleId,
    this.turnRef,
    this.turnKey,
  });

  @override
  State<ThumbsFeedback> createState() => _ThumbsFeedbackState();
}

class _ThumbsFeedbackState extends State<ThumbsFeedback> {
  /// In-memory per-(state-instance) record of the chosen rating.
  String? _selectedRating;

  Future<void> _supersedePriorIfAny() async {
    final profile = AppSettingsScope.read(context).profile;
    final tKey = widget.turnKey;
    if (profile == null || tKey == null) return;
    try {
      final db = FirebaseFirestore.instance;
      final query = await db
          .collection('users')
          .doc(profile.uid)
          .collection('response_feedback')
          .where('turnRef', isEqualTo: '${widget.moduleId}#$tKey')
          .where('superseded', isEqualTo: false)
          .get();
      for (final doc in query.docs) {
        await doc.reference.update({
          'superseded': true,
          'supersededAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}
  }

  Future<void> _writeFeedback({
    required String rating,
    List<String>? reasons,
    String? otherText,
    bool unintentionalDismiss = false,
  }) async {
    final profile = AppSettingsScope.read(context).profile;
    final arm = Arm.of(context)?.code ?? 'B';
    final turnRef = widget.turnKey != null
        ? '${widget.moduleId}#${widget.turnKey}'
        : widget.turnRef;
    final fb = ResponseFeedback(
      agentId: widget.agentId,
      moduleId: widget.moduleId,
      arm: arm,
      rating: rating,
      reasonCategories: reasons,
      reasonOtherText: otherText,
      turnRef: turnRef,
      submittedAt: DateTime.now(),
      unintentionalDismiss: unintentionalDismiss,
    );
    await _supersedePriorIfAny();
    if (profile != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(profile.uid)
            .collection('response_feedback')
            .add(fb.toFirestore());
      } catch (_) {}
    }
    if (mounted) {
      await AnalyticsScope.of(context).logResponseFeedbackSubmitted(
        agentId: widget.agentId,
        moduleId: widget.moduleId,
        rating: rating,
        reasons: reasons,
      );
    }
  }

  Future<void> _onThumbsUp() async {
    setState(() => _selectedRating = 'up');
    await _writeFeedback(rating: 'up');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('多謝你！'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _onThumbsDown() async {
    setState(() => _selectedRating = 'down');
    final result = await showModalBottomSheet<_DownResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // Force a warm off-white background and a neutral barrier — the
      // M3 defaults pulled in `surfaceContainerLow` which collided
      // with the chip / text colours and read as white-on-white on
      // some devices.
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      barrierColor: const Color(0x66000000),
      builder: (ctx) => const _ReasonSheet(),
    );
    if (result == null) {
      // Tap-outside dismiss.  Log it for analytics, then reset the
      // in-memory rating so the user can re-open the sheet — earlier
      // builds left the buttons disabled here, which read as a bug.
      await _writeFeedback(
        rating: 'down',
        reasons: const [],
        unintentionalDismiss: true,
      );
      if (mounted) setState(() => _selectedRating = null);
      return;
    }
    await _writeFeedback(
      rating: 'down',
      reasons: result.reasons,
      otherText: result.otherText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selectedRating;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '幫到我',
            onPressed: selected == null ? _onThumbsUp : null,
            iconSize: 22,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              selected == 'up'
                  ? Icons.thumb_up_alt
                  : Icons.thumb_up_alt_outlined,
              color: selected == 'up'
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            tooltip: '冇咁幫到',
            onPressed: selected == null ? _onThumbsDown : null,
            iconSize: 22,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              selected == 'down'
                  ? Icons.thumb_down_alt
                  : Icons.thumb_down_alt_outlined,
              color: selected == 'down'
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownResult {
  final List<String> reasons;
  final String? otherText;
  const _DownResult({required this.reasons, this.otherText});
}

class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet();

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  final Set<String> _selected = {};
  final _otherCtrl = TextEditingController();

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  // Explicit colours throughout — the M3 ChipTheme defaults
  // (white background, no explicit label colour) plus a white modal
  // background were colliding to produce white-on-white labels and
  // titles on some devices.  Hard-coding the palette here makes the
  // sheet bullet-proof regardless of the ambient theme.
  static const Color _ink = Color(0xFF3A3330);
  static const Color _inkMuted = Color(0xFF8A7D72);
  static const Color _accent = Color(0xFFC2703F);
  static const Color _chipBg = Color(0xFFF7F2EC);
  static const Color _chipSelectedBg = Color(0xFFE9D6BE);
  static const Color _chipBorder = Color(0xFFE0D6C9);
  static const Color _chipSelectedBorder = Color(0xFFC2703F);

  @override
  Widget build(BuildContext context) {
    final showOther = _selected.contains(ResponseFeedbackReasons.other);
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '咩位令你覺得唔啱？',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: _ink,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '可以揀一個或者多個。',
            style: TextStyle(fontSize: 14, color: _inkMuted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ResponseFeedbackReasons.all.map((id) {
              final selected = _selected.contains(id);
              return _ReasonChip(
                label: ResponseFeedbackReasons.labels[id] ?? id,
                selected: selected,
                onTap: () {
                  setState(() {
                    if (selected) {
                      _selected.remove(id);
                    } else {
                      _selected.add(id);
                    }
                  });
                },
              );
            }).toList(),
          ),
          if (showOther) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _otherCtrl,
              maxLines: 2,
              style: const TextStyle(fontSize: 16, color: _ink),
              decoration: const InputDecoration(
                hintText: '可以寫低你嘅感受…',
                hintStyle: TextStyle(color: _inkMuted),
                filled: true,
                fillColor: Color(0xFFFBF8F3),
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop(_DownResult(
                  reasons: _selected.toList(),
                  otherText:
                      _otherCtrl.text.trim().isEmpty ? null : _otherCtrl.text.trim(),
                ));
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: _accent,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                '完成',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ReasonChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? _ReasonSheetState._chipSelectedBg
        : _ReasonSheetState._chipBg;
    final border = selected
        ? _ReasonSheetState._chipSelectedBorder
        : _ReasonSheetState._chipBorder;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border, width: selected ? 2 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded,
                    size: 18, color: _ReasonSheetState._accent),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: _ReasonSheetState._ink,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
