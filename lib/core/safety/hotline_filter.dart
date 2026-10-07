/// T7 — hotline outbound filter, App side (Hybrid arm; decision 0018).
///
/// The server (`functions/hotline_filter.js`) already replaces every phone
/// number in a `proxyDeepSeek` reply with [kHotlineToken] and logs it.
/// This is the second pass, run by [LlmGateway] on what comes back
/// (switch: `PhaseAConfig.hotlineFilterClient`, default on), plus the
/// widget that turns the token into a link to the crisis page.
///
/// The patterns mirror the server's; both are tested against the same list
/// (`test/fixtures/hotline_filter_cases.json`).  Arm B never shows AI text,
/// so the filter only ever runs on Hybrid replies.
library;

import 'package:flutter/material.dart';

import '../../features/crisis/presentation/pages/emergency_support_page.dart';
import '../../l10n/app_localizations.dart';

/// Stands in for a phone number in an AI reply.  The prompt rule
/// (`functions/prompts/hotline_rule.v1.txt`) asks the model to write it,
/// and the filters put it where a number was.
const String kHotlineToken = '【緊急熱線】';

const _digit = '[0-9\\uFF10-\\uFF19]';
const _sep = '[ \\t\\u00A0\\u3000\\-\\u2010\\u2011\\u2013\\u2014\\uFF0D]';
const _seps = '$_sep{0,2}';
const _prefix = '(?:[+\\uFF0B]\\s?)?(?:[(\\uFF08]\\s?)?'
    '(?:852|\\uFF18\\uFF15\\uFF12)(?:\\s?[)\\uFF09])?$_seps';
const _left = '(?<![0-9\\uFF10-\\uFF19\$\\uFF04.,])';
const _right = '(?![0-9\\uFF10-\\uFF19]|[.\\uFF0E,][0-9\\uFF10-\\uFF19]|'
    '\\s?[%\\uFF05\\u5143\\u868A\\u5E74\\u6708\\u65E5\\u865F\\u53F7'
    '\\u6B72\\u5C81\\u500B\\u4E2A\\u4EBA\\u9EDE\\u70B9:\\uFF1A])';

final List<(String, RegExp)> _patterns = [
  (
    'hk8',
    RegExp('$_left(?:$_prefix)?[2-9\\uFF12-\\uFF19]$_digit{3}$_seps$_digit{4}'
        '$_right'),
  ),
  (
    'hk_tollfree',
    RegExp('$_left(?:$_prefix)?(?:800|\\uFF18\\uFF10\\uFF10)$_seps$_digit{3}'
        '$_seps$_digit{3}$_right'),
  ),
  (
    'cn_mobile',
    RegExp('$_left(?:[+\\uFF0B]?86$_seps)?1[3-9]$_digit$_seps$_digit{4}'
        '$_seps$_digit{4}$_right'),
  ),
  ('emergency', RegExp('$_left(?:999|\\uFF19\\uFF19\\uFF19)$_right')),
  (
    'short_service',
    RegExp(
        '(?<=(?:\\u6253|\\u64A5|\\u64A5\\u6253|\\u81F4\\u96FB|\\u96FB\\u8A71|'
        '\\u71B1\\u7DDA|\\u70ED\\u7EBF|call|dial|phone|hotline)'
        '[\\s:\\uFF1A]{0,2})'
        '1$_digit{2,4}$_right',
        caseSensitive: false),
  ),
];

String _digitsOf(String s) => s
    .replaceAllMapped(RegExp('[\\uFF10-\\uFF19]'),
        (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xFF10 + 48))
    .replaceAll(RegExp('[^0-9]'), '');

bool _isYearRange(String m) {
  final parts =
      m.split(RegExp('$_sep+')).where((p) => p.isNotEmpty).toList();
  if (parts.length != 2) return false;
  return parts.every((p) {
    final d = _digitsOf(p);
    final y = int.tryParse(d) ?? 0;
    return d.length == 4 && y >= 1900 && y <= 2099;
  });
}

bool _isCompactDate(String m) {
  if (!RegExp('^[0-9\\uFF10-\\uFF19]{8}\$').hasMatch(m)) return false;
  final d = _digitsOf(m);
  final y = int.parse(d.substring(0, 4));
  final mo = int.parse(d.substring(4, 6));
  final day = int.parse(d.substring(6, 8));
  return y >= 1900 && y <= 2099 && mo >= 1 && mo <= 12 && day >= 1 &&
      day <= 31;
}

/// Result of [filterHotlines]: the text with numbers replaced and how many.
class HotlineFilterResult {
  final String text;
  final int count;
  const HotlineFilterResult(this.text, this.count);
}

/// Replace every phone number in [text] with [kHotlineToken].  Dates,
/// times, amounts, counts and years are left alone.
HotlineFilterResult filterHotlines(String text) {
  if (text.isEmpty) return HotlineFilterResult(text, 0);
  var out = text;
  var count = 0;
  for (final (kind, re) in _patterns) {
    out = out.replaceAllMapped(re, (m) {
      final s = m[0]!;
      if (kind == 'hk8' && (_isYearRange(s) || _isCompactDate(s))) return s;
      count++;
      return kHotlineToken;
    });
  }
  return HotlineFilterResult(out, count);
}

/// Inline link shown where [kHotlineToken] appears in a chat bubble.  The
/// label is the existing crisis-line string (`safetyPillAcute`:
/// 緊急熱線 / Crisis line); tapping opens the same [EmergencySupportPage]
/// the acute route uses, with the PI-verified numbers.
class HotlineLink extends StatelessWidget {
  final TextStyle style;
  const HotlineLink({super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final label = AppLocalizations.of(context)?.safetyPillAcute ??
        (isEn ? 'Crisis line' : '緊急熱線');
    final color = Theme.of(context).colorScheme.error;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => const EmergencySupportPage(from: 'hotline_link'),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.phone_in_talk_outlined,
                  size: (style.fontSize ?? 16) * 1.1, color: color),
              const SizedBox(width: 2),
              Text(
                label,
                style: style.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
