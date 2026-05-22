import 'package:flutter/material.dart';

/// Renders chat-bubble text that may contain a small subset of markdown
/// (`**bold**`, `*italic*`, leading `#` headings) without dragging in a
/// full markdown package.  LLM replies often arrive with these markers
/// even after the prompt asks for plain text, and raw asterisks read as
/// noise to older users.
class RichChatText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign? textAlign;

  const RichChatText({
    super.key,
    required this.text,
    required this.style,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: _parse(text, style)),
      textAlign: textAlign,
    );
  }
}

List<InlineSpan> _parse(String input, TextStyle baseStyle) {
  final cleaned = _stripBlockMarkers(input);
  final spans = <InlineSpan>[];
  // Lazy single-pass tokeniser for **bold** / *italic*.  Bold is tried
  // first so `**` doesn't get swallowed by italic.
  int i = 0;
  final buf = StringBuffer();

  void flushText() {
    if (buf.isEmpty) return;
    spans.add(TextSpan(text: buf.toString(), style: baseStyle));
    buf.clear();
  }

  while (i < cleaned.length) {
    final remaining = cleaned.length - i;
    if (remaining >= 4 && cleaned[i] == '*' && cleaned[i + 1] == '*') {
      final closeRel = cleaned.indexOf('**', i + 2);
      if (closeRel != -1 && closeRel > i + 2) {
        flushText();
        spans.add(TextSpan(
          text: cleaned.substring(i + 2, closeRel),
          style: baseStyle.copyWith(fontWeight: FontWeight.w700),
        ));
        i = closeRel + 2;
        continue;
      }
    }
    if (cleaned[i] == '*') {
      final closeRel = cleaned.indexOf('*', i + 1);
      if (closeRel != -1 && closeRel > i + 1 && !_isAdjacentStar(cleaned, i, closeRel)) {
        flushText();
        spans.add(TextSpan(
          text: cleaned.substring(i + 1, closeRel),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
        i = closeRel + 1;
        continue;
      }
    }
    buf.write(cleaned[i]);
    i++;
  }
  flushText();
  if (spans.isEmpty) {
    spans.add(TextSpan(text: cleaned, style: baseStyle));
  }
  return spans;
}

bool _isAdjacentStar(String s, int open, int close) {
  // Reject "* word *" with leading/trailing space — these are usually
  // bullet points or stray punctuation, not italic markers.
  if (open + 1 >= s.length || close - 1 < 0) return true;
  final inner = s.substring(open + 1, close);
  if (inner.startsWith(' ') || inner.endsWith(' ')) return true;
  return false;
}

String _stripBlockMarkers(String input) {
  final lines = input.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('#')) {
      var j = 0;
      while (j < trimmed.length && trimmed[j] == '#') {
        j++;
      }
      final rest = trimmed.substring(j).trimLeft();
      lines[i] = rest;
    }
  }
  return lines.join('\n');
}
