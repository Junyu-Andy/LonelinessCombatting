/// Weekly PGIC (Patient Global Impression of Change) assessment page.
///
/// 7-point single-select scale comparing current loneliness with before the
/// elder started using the App (1020f: the approved questionnaire package,
/// appendix B.5, word for word; values unchanged, 1 = 好咗好多).  The same
/// page serves the bundle part and the W5–W7 stand-alone PGIC.
/// Stores response at `users/{uid}/pgic/{auto-id}` (Sprint 1 spec).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../weekly_bundle/presentation/weekly_part_header.dart';
import '../../../weekly_pr/data/weekly_pr_response.dart';
import '../../data/pgic_response.dart';

class PgicPage extends StatefulWidget {
  /// M-2 — ISO week being rated (e.g. `2026-W37`).  Inside the Sun 20:00 →
  /// Tue 23:59 window a Monday answer rates the *previous* week, so the
  /// banner passes it explicitly; `isoWeek` alone would mislabel it.
  final String? weekIso;

  /// T24 — inside the weekly bundle: the record is `users/{uid}/pgic/{bundle}`
  /// with a `bundle` field, the page shows 「第 n 部分，共 m 部分」 and pops
  /// `true` once saved.  Null = the Sunday-window page, unchanged.
  final String? bundle;
  final WeeklyPartPosition? part;

  /// 10/19 — tester preview of the weekly bundle: same page, nothing saved.
  final bool preview;

  const PgicPage(
      {super.key, this.weekIso, this.bundle, this.part, this.preview = false});

  @override
  State<PgicPage> createState() => _PgicPageState();
}

class _PgicPageState extends State<PgicPage> {
  int? _selected;
  bool _saving = false;
  bool _saved = false;

  static const _optionsZh = <(int, String, Color)>[
    (1, '好咗好多', Color(0xFF1B5E20)),
    (2, '好咗', Color(0xFF388E3C)),
    (3, '好咗少少', Color(0xFF66BB6A)),
    (4, '冇變', Color(0xFF78909C)),
    (5, '差咗少少', Color(0xFFFFB300)),
    (6, '差咗', Color(0xFFF57C00)),
    (7, '差咗好多', Color(0xFFB71C1C)),
  ];

  static const _optionsEn = <(int, String, Color)>[
    (1, 'Much better', Color(0xFF1B5E20)),
    (2, 'Better', Color(0xFF388E3C)),
    (3, 'A little better', Color(0xFF66BB6A)),
    (4, 'No change', Color(0xFF78909C)),
    (5, 'A little worse', Color(0xFFFFB300)),
    (6, 'Worse', Color(0xFFF57C00)),
    (7, 'Much worse', Color(0xFFB71C1C)),
  ];

  Future<void> _submit() async {
    if (_selected == null || _saving) return;
    setState(() => _saving = true);
    final profile =
        widget.preview ? null : AppSettingsScope.read(context).profile;
    if (profile != null) {
      try {
        final now = DateTime.now();
        final response = PgicResponse(
          value: _selected!,
          answeredAt: now,
          isoWeek: PgicResponse.isoWeekFor(now),
        );
        final col = FirebaseFirestore.instance
            .collection('users')
            .doc(profile.uid)
            .collection('pgic');
        final data = {
          ...response.toFirestore(),
          'weekIso': widget.weekIso ?? WeeklyPrResponse.currentWeekIso(now),
        };
        final bundle = widget.bundle;
        if (bundle != null) {
          // T24: one record per bundle; a retry overwrites the same doc.
          await col.doc(bundle).set({...data, 'bundle': bundle}, SetOptions(merge: true));
        } else {
          await col.add(data);
        }
      } catch (_) {
        // Graceful degradation: Firebase unavailable in guest mode.
      }
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
    });
    if (widget.bundle != null) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final options = isEn ? _optionsEn : _optionsZh;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Compared with when you started' : '同開始用嗰時比較'),
      ),
      body: SafeArea(
        child: Column(children: [
          if (widget.part != null) WeeklyPartHeader(part: widget.part!),
          Expanded(child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            Text(
              isEn
                  ? 'Compared with before you started using this app, how is your loneliness now?'
                  : '同你開始用呢個 app 之前比較，你嘅孤獨感而家點？',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isEn ? 'Choose the one that best matches how you feel.' : '請揀最貼近你感受嘅一個。',
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
                        isEn ? 'Thank you for your reply! Saved.' : '多謝你嘅回覆！已經儲存。',
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
            ...List.generate(options.length, (i) {
              final opt = options[i];
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
                      : Text(isEn ? 'Submit' : '提交'),
                ),
              ),
          ],
        )),
        ]),
      ),
    );
  }
}
