/// 1020c §1(3) — what the App does to a 小讀本 HTML file before showing it,
/// and which links the reader lets through.  Pure Dart, unit-tested
/// (test/reader_test.dart); the WebView itself only calls these.
///
/// Network block, layer 1 (decision NNNN-html-readers-webview): the App
/// puts a strict Content-Security-Policy at the very top of `<head>`, so a
/// unit can load nothing from outside even if a file slips past layer 2
/// (tool/check_reader_html.js in CI).  The page is shown with
/// `loadHtmlString` and no base URL, so it has no origin to load relative
/// files from either: a unit must carry its CSS, JS and pictures inline.
library;

import '../../../core/usage/usage_event_recorder.dart' show kReaderIdPattern;

/// Everything external is refused: only the file's own inline styles and
/// scripts, and `data:` pictures / fonts / media.
const String kReaderCsp = "default-src 'none'; "
    "script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
    'img-src data:; font-src data:; media-src data:; '
    "connect-src 'none'; frame-src 'none'; child-src 'none'; "
    "worker-src 'none'; object-src 'none'; manifest-src 'none'; "
    "form-action 'none'; base-uri 'none'";

/// No pinch or double-tap zoom (1020c: elders lose their place).
const String kReaderViewport = 'width=device-width, initial-scale=1, '
    'maximum-scale=1, user-scalable=no';

/// The JavaScript channel the section script posts to.
const String kReaderJsChannel = 'PeizhuReader';

/// Reports each `data-section` once, when its top has come up to about
/// two thirds of the screen (or the page is scrolled to the end with the
/// section on screen).  Posts only the attribute value; the App accepts it
/// only if it is a well-formed id that occurs in this file.  Plain ES5 so
/// older Android WebViews run it.
const String kReaderSectionScript = '''
(function(){
  var seen={},els=[],queued=false;
  function send(id){try{var c=window.$kReaderJsChannel;if(c&&c.postMessage){c.postMessage(String(id));}}catch(e){}}
  function check(){
    queued=false;
    var d=document.documentElement;
    var h=window.innerHeight||d.clientHeight;
    var y=window.pageYOffset||d.scrollTop||0;
    var atEnd=y+h>=d.scrollHeight-4;
    for(var i=0;i<els.length;i++){
      var id=els[i].getAttribute('data-section');
      if(!id||seen[id]){continue;}
      var top=els[i].getBoundingClientRect().top;
      if(top<h*0.65||(atEnd&&top<h)){seen[id]=1;send(id);}
    }
  }
  function queue(){if(!queued){queued=true;(window.requestAnimationFrame||setTimeout)(check);}}
  function start(){
    els=document.querySelectorAll('[data-section]');
    check();
    window.addEventListener('scroll',queue,{passive:true});
    window.addEventListener('resize',queue);
  }
  if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',start);}else{start();}
})();
''';

/// The `--fs` value: the App's own text scale, two decimals.
String readerFontScaleCss(double scale) =>
    (scale.isFinite ? scale.clamp(0.5, 3.0) : 1.0).toStringAsFixed(2);

final RegExp _headOpen = RegExp(r'<head(\s[^>]*)?>', caseSensitive: false);
final RegExp _headClose = RegExp(r'</head\s*>', caseSensitive: false);
final RegExp _htmlOpen = RegExp(r'<html(\s[^>]*)?>', caseSensitive: false);
final RegExp _bodyClose = RegExp(r'</body\s*>', caseSensitive: false);

/// The HTML the WebView loads:
///   - right after `<head>`: charset and the CSP (must come before
///     anything that could load);
///   - just before `</head>` (after the unit's own CSS, so it wins): the
///     no-zoom viewport and `:root{--fs:X}`, plus no text inflation, no
///     long-press text selection or link callout;
///   - just before `</body>`: [kReaderSectionScript].
/// A file without `<head>` / `</body>` still gets all of it.
String prepareReaderHtml(String raw, {required double fontScale}) {
  final top = '<meta charset="utf-8">'
      '<meta http-equiv="Content-Security-Policy" content="$kReaderCsp">';
  final end = '<meta name="viewport" content="$kReaderViewport">'
      '<style id="peizhu-reader">:root{--fs:${readerFontScaleCss(fontScale)}}'
      'html{-webkit-text-size-adjust:100%;text-size-adjust:100%;'
      '-webkit-user-select:none;user-select:none;'
      '-webkit-touch-callout:none;touch-action:pan-x pan-y;}</style>';
  const script = '<script>$kReaderSectionScript</script>';

  var html = raw;
  final open = _headOpen.firstMatch(html);
  if (open != null) {
    html = html.replaceRange(open.end, open.end, top);
    final close = _headClose.firstMatch(html);
    final at = close?.start ?? open.end + top.length;
    html = html.replaceRange(at, at, end);
  } else {
    final block = '<head>$top$end</head>';
    final h = _htmlOpen.firstMatch(html);
    html = h != null
        ? html.replaceRange(h.end, h.end, block)
        : '$block$html';
  }
  final bodyEnds = _bodyClose.allMatches(html);
  if (bodyEnds.isEmpty) return '$html$script';
  final at = bodyEnds.last.start;
  return html.replaceRange(at, at, script);
}

final RegExp _sectionAttr =
    RegExp(r'''data-section\s*=\s*["']([^"']*)["']''', caseSensitive: false);

/// The well-formed `data-section` ids in a unit file.  Only these are
/// accepted from the JavaScript channel.
Set<String> readerSectionIds(String raw) => {
      for (final m in _sectionAttr.allMatches(raw))
        if (kReaderIdPattern.hasMatch(m.group(1)!.trim())) m.group(1)!.trim(),
    };

/// The three action buttons (1020c §1(4)).
enum ReaderCta {
  smallAction('small_action'),
  plan('plan'),
  thought('thought');

  const ReaderCta(this.code);

  /// `peizhu://cta/<code>`, and the `cta` value of `reader_cta`.
  final String code;

  /// `peizhu://cta/small_action` etc.; anything else is null.
  static ReaderCta? fromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'peizhu') return null;
    if (uri.host.toLowerCase() != 'cta') return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length != 1) return null;
    for (final c in values) {
      if (c.code == segments.single) return c;
    }
    return null;
  }
}

enum ReaderNavAction { allow, block, cta }

/// What the reader does with one navigation request.
class ReaderNavDecision {
  const ReaderNavDecision._(this.action, [this.cta]);

  static const allow = ReaderNavDecision._(ReaderNavAction.allow);
  static const block = ReaderNavDecision._(ReaderNavAction.block);

  final ReaderNavAction action;
  final ReaderCta? cta;

  @override
  String toString() => 'ReaderNavDecision(${action.name}, ${cta?.code})';
}

/// 1020c §1(3): only the initial load and `peizhu://` links pass.
///   - `peizhu://cta/<one of three>` → handled by the App (never loaded);
///   - the page's own first load (`about:blank` / `data:` in the main
///     frame, before it has finished loading once) → allowed;
///   - everything else — web links, `tel:`, `mailto:`, other `peizhu://`,
///     in-page `#` jumps, frames — is blocked and opens nothing.
ReaderNavDecision decideReaderNavigation(
  String url, {
  required bool isMainFrame,
  required bool initialLoadPending,
}) {
  final cta = ReaderCta.fromUrl(url);
  if (cta != null) return ReaderNavDecision._(ReaderNavAction.cta, cta);
  final u = url.trim().toLowerCase();
  if (initialLoadPending &&
      isMainFrame &&
      (u == 'about:blank' || u.startsWith('data:'))) {
    return ReaderNavDecision.allow;
  }
  return ReaderNavDecision.block;
}
