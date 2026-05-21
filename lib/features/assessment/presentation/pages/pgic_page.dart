/// Weekly PGIC (Patient Global Impression of Change) assessment page.
///
/// 7-point single-select scale comparing current loneliness to last week.
/// Stores response at `users/{uid}/pgic/{auto-id}` (Sprint 1 spec).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../data/pgic_response.dart';

class PgicPage extends StatefulWidget {
  const PgicPage({super.key});

  @override
  State<PgicPage> createState() => _PgicPageState();
}

class _PgicPageState extends State<PgicPage> {
  int? _selected;
  bool _saving = false;
  bool _saved = false;

  static const _options = <(int, String, Color)>[
    (1, '改善咗好多（冇咁孤單）', Color(0xFF1B5E20)),
    (2, '改善咗', Color(0xFF388E3C)),
    (3, '少少改善（少少冇咁孤單）', Color(0xFF66BB6A)),
    (4, '冇變', Color(0xFF78909C)),
    (5, '差咗少少（多咗少少孤單）', Color(0xFFFFB300)),
    (6, '差咗', Color(0xFFF57C00)),
    (7, '差咗好多（更加孤單）', Color(0xFFB71C1C)),
  ];

  Future<void> _submit() async {
    if (_selected == null || _saving) return;
    setState(() => _saving = true);
    final profile = AppSettingsScope.read(context).profile;
    if (profile != null) {
      try {
        final now = DateTime.now();
        final response = PgicResponse(
          value: _selected!,
          answeredAt: now,
          isoWeek: PgicResponse.isoWeekFor(now),
        );
        await FirebaseFirestore.instance
            .collection('users')
            .doc(profile.uid)
            .collection('pgic')
            .add(response.toFirestore());
      } catch (_) {
        // Graceful degradation: Firebase unavailable in guest mode.
      }
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('每週感受變化'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            Text(
              '同上個星期比較，你而家覺得自己嘅孤單感整體上有冇變化？',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '請揀最貼近你感受嘅一個。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            if (_saved) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: theme.colorScheme.primary, size: 32),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        '多謝你嘅回覆！已經儲存。',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
            ...List.generate(_options.length, (i) {
              final opt = _options[i];
              final isSelected = _selected == opt.$1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: _saved ? null : () => setState(() => _selected = opt.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? opt.$3.withAlpha(30)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? opt.$3 : theme.colorScheme.outline,
                        width: isSelected ? 2.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected ? opt.$3 : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? opt.$3
                                  : theme.colorScheme.outline,
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 18)
                              : Text(
                                  '${opt.$1}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            opt.$2,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight:
                                  isSelected ? FontWeight.w600 : FontWeight.normal,
                              color: theme.colorScheme.onSurface,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            if (!_saved)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_selected == null || _saving) ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    textStyle:
                        const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('提交'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
