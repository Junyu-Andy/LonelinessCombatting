import 'package:flutter/material.dart';

/// T17 — bottom bar for one-item-per-screen surveys: 上一頁 · 跳過 · 下一頁.
class SurveyNavBar extends StatelessWidget {
  const SurveyNavBar({
    super.key,
    required this.isEn,
    required this.showBack,
    required this.showSkip,
    required this.onBack,
    required this.onSkip,
    required this.onNext,
    this.nextLabel,
    this.busy = false,
  });

  final bool isEn;
  final bool showBack;
  final bool showSkip;
  final VoidCallback onBack;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  /// Defaults to 下一頁 / Next.
  final String? nextLabel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const pad = EdgeInsets.symmetric(vertical: 12);
    const text = TextStyle(fontSize: 18);
    // Narrow side padding so 上一頁 stays on one line on a 360-px phone.
    final tight = ButtonStyle(
      padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 6)),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          if (showBack) ...[
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('survey_back'),
                style: tight,
                onPressed: busy ? null : onBack,
                child: Padding(
                  padding: pad,
                  child: Text(isEn ? 'Back' : '上一頁',
                      style: text, maxLines: 1, softWrap: false),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (showSkip) ...[
            Expanded(
              child: TextButton(
                key: const ValueKey('survey_skip'),
                style: tight,
                onPressed: busy ? null : onSkip,
                child: Padding(
                  padding: pad,
                  child: Text(isEn ? 'Skip' : '跳過', style: text),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            flex: 2,
            child: FilledButton(
              key: const ValueKey('survey_next'),
              onPressed: busy ? null : onNext,
              child: Padding(
                padding: pad,
                child: Text(nextLabel ?? (isEn ? 'Next' : '下一頁'),
                    style: text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline "please answer" line shown just above [SurveyNavBar].
class SurveyHint extends StatelessWidget {
  const SurveyHint({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('survey_hint'),
      width: double.infinity,
      color: cs.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Text(text,
          style: TextStyle(fontSize: 17, color: cs.onErrorContainer)),
    );
  }
}
