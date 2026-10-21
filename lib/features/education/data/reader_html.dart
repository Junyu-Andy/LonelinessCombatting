/// 1020c §1(3) — what the App does to a 小讀本 HTML file before showing it,
/// and which links the reader lets through.  Pure Dart, unit-tested
/// (test/reader_test.dart); the WebView itself only calls these.
///
/// Network block, layer 1 (decision 0056-html-readers-webview): the App
/// puts a strict Content-Security-Policy at the very top of `<head>`, so a
/// unit can load nothing from outside even if a file slips past layer 2
/// (tool/check_reader_html.js in CI).  The page is shown with
/// `loadHtmlString` and no base URL, so it has no origin to load relative
/// files from either: a unit must carry its CSS, JS and pictures inline.
library;

import 'dart:convert';

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

/// The JavaScript channel the App's page script posts to.
const String kReaderJsChannel = 'PeizhuReader';

/// The App's script at the end of the page (plain ES5, so older Android
/// WebViews run it).  It posts two kinds of message to [kReaderJsChannel]:
///   - a bare `data-section` id, once per section, when that section is on
///     screen and its top has come up to about two thirds of the screen (or
///     the page is scrolled to the end) — the `reader_section` event.
///     Hidden sections (1021: the page shows one section at a time) are
///     skipped until they are shown;
///   - 1021 T-R2 (3) / T-R3: on every `peizhu:view` event of the page, and
///     once at the start, `{"view":"toc"|<section id>,"index":n,"total":n,
///     "read":[ids]}` — where the reader is (the native top bar's title)
///     and `window.peizhuReader.readIds()` (what has been read).
/// No page text is ever posted (the event's own `title` is not sent).  The
/// App accepts only well-formed ids that occur in this file.
const String kReaderSectionScript = '''
(function(){
  var seen={},els=[],queued=false;
  function post(s){try{var c=window.$kReaderJsChannel;if(c&&c.postMessage){c.postMessage(String(s));}}catch(e){}}
  function shown(el){try{return el.getClientRects().length>0;}catch(e){return true;}}
  function check(){
    queued=false;
    var d=document.documentElement;
    var h=window.innerHeight||d.clientHeight;
    var y=window.pageYOffset||d.scrollTop||0;
    var atEnd=y+h>=d.scrollHeight-4;
    for(var i=0;i<els.length;i++){
      var id=els[i].getAttribute('data-section');
      if(!id||seen[id]||!shown(els[i])){continue;}
      var top=els[i].getBoundingClientRect().top;
      if(top<h*0.65||(atEnd&&top<h)){seen[id]=1;post(id);}
    }
  }
  function queue(){if(!queued){queued=true;(window.requestAnimationFrame||setTimeout)(check);}}
  function view(v){
    var r=[];
    try{var p=window.peizhuReader;if(p&&p.readIds){r=p.readIds()||[];}}catch(e){}
    try{post(JSON.stringify({view:String(v&&v.view),index:+(v&&v.index)||0,total:+(v&&v.total)||0,read:r}));}catch(e){}
  }
  function start(){
    els=document.querySelectorAll('[data-section]');
    check();
    window.addEventListener('scroll',queue,{passive:true});
    window.addEventListener('resize',queue);
    window.addEventListener('peizhu:view',function(e){view(e&&e.detail);queue();});
    try{var p=window.peizhuReader;if(p&&p.current){view(p.current());}}catch(e){}
  }
  if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',start);}else{start();}
})();
''';

/// 1021 T-R3 (2): give the page the sections read last time
/// (`window.peizhuReader.setRead(ids)`), right after the page's own script
/// has set `peizhuReader` up (or at DOMContentLoaded if it is not there
/// yet).  [ids] are already validated.
String readerSetReadScript(Iterable<String> ids) => '''
(function(ids){
  function go(){try{var r=window.peizhuReader;if(r&&r.setRead){r.setRead(ids);}}catch(e){}}
  if(window.peizhuReader){go();}else{document.addEventListener('DOMContentLoaded',go);}
})(${jsonEncode(ids.toList())});
''';

/// 1021 T-R2 (1): the native top bar replaces the page's own
/// (`data-chrome="app"`); the Hybrid arm also gets `data-ask="on"` (the
/// page then shows its one line pointing at the 「?」 — registry C08).
/// `data-explain` is never set: the per-card explanations are not built.
String readerChromeScript({required bool ask}) =>
    "(function(d){d.setAttribute('data-chrome','app');"
    "${ask ? "d.setAttribute('data-ask','on');" : ''}"
    '})(document.documentElement);';

/// The `--fs` value: the App's own text scale, two decimals.
String readerFontScaleCss(double scale) =>
    (scale.isFinite ? scale.clamp(0.5, 3.0) : 1.0).toStringAsFixed(2);

final RegExp _headOpen = RegExp(r'<head(\s[^>]*)?>', caseSensitive: false);
final RegExp _headClose = RegExp(r'</head\s*>', caseSensitive: false);
final RegExp _htmlOpen = RegExp(r'<html(\s[^>]*)?>', caseSensitive: false);
final RegExp _bodyClose = RegExp(r'</body\s*>', caseSensitive: false);

/// The HTML the WebView loads:
///   - right after `<head>`: charset and the CSP (must come before
///     anything that could load), then [readerChromeScript];
///   - just before `</head>` (after the unit's own CSS, so it wins): the
///     no-zoom viewport and `:root{--fs:X}`, plus no text inflation, no
///     long-press text selection or link callout;
///   - just before `</body>`: [readerSetReadScript] (when [readIds] is not
///     empty) and [kReaderSectionScript].
/// A file without `<head>` / `</body>` still gets all of it.  [ask] is
/// true only for the Hybrid arm; [readIds] must be well-formed section ids
/// of this unit (others are dropped).
String prepareReaderHtml(
  String raw, {
  required double fontScale,
  bool ask = false,
  Iterable<String> readIds = const [],
}) {
  final top = '<meta charset="utf-8">'
      '<meta http-equiv="Content-Security-Policy" content="$kReaderCsp">'
      '<script>${readerChromeScript(ask: ask)}</script>';
  final end = '<meta name="viewport" content="$kReaderViewport">'
      '<style id="peizhu-reader">:root{--fs:${readerFontScaleCss(fontScale)}}'
      'html{-webkit-text-size-adjust:100%;text-size-adjust:100%;'
      '-webkit-user-select:none;user-select:none;'
      '-webkit-touch-callout:none;touch-action:pan-x pan-y;}</style>';
  final ids = [
    for (final id in readIds)
      if (kReaderIdPattern.hasMatch(id)) id,
  ];
  final script = '${ids.isEmpty ? '' : '<script>${readerSetReadScript(ids)}</script>'}'
      '<script>$kReaderSectionScript</script>';

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

/// The action buttons (1020c §1(4); 1021 T-R4 (3) adds 小欣).
enum ReaderCta {
  smallAction('small_action'),
  plan('plan'),
  thought('thought'),

  /// 1021 T-R4 (3): 「同小欣講吓…」 — the 小欣 chat, both arms.
  chatSiuYan('chat_siu_yan');

  const ReaderCta(this.code);

  /// `peizhu://cta/<code>`, and the `cta` value of `reader_cta`.
  final String code;

  /// `peizhu://cta/small_action` etc.; anything else is null.
  static ReaderCta? fromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'peizhu') return null;
    if (uri.host.toLowerCase() != 'cta') return null;
    if (uri.hasQuery) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length != 1) return null;
    for (final c in values) {
      if (c.code == segments.single) return c;
    }
    return null;
  }
}

/// 1021 T-R4b: `peizhu://reader/open?id=<unit id>` (「讀下一篇」) → the
/// unit id, or null for anything else.
String? readerOpenUnitId(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.scheme.toLowerCase() != 'peizhu') return null;
  if (uri.host.toLowerCase() != 'reader') return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length != 1 || segments.single != 'open') return null;
  if (uri.queryParametersAll.length != 1) return null;
  final ids = uri.queryParametersAll['id'];
  if (ids == null || ids.length != 1) return null;
  return kReaderIdPattern.hasMatch(ids.single) ? ids.single : null;
}

/// `peizhu://explain?card=…` — the per-card 「?」 explanations.  Not built
/// this time (1021): the page shows those buttons only with
/// `data-explain="on"`, which the App never sets, so they cannot be
/// tapped; if one ever were, it is blocked like any unknown link.
bool isReaderExplainUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  return uri != null &&
      uri.scheme.toLowerCase() == 'peizhu' &&
      uri.host.toLowerCase() == 'explain';
}

enum ReaderNavAction { allow, block, cta, openUnit }

/// What the reader does with one navigation request.
class ReaderNavDecision {
  const ReaderNavDecision._(this.action, [this.cta, this.unitId]);

  static const allow = ReaderNavDecision._(ReaderNavAction.allow);
  static const block = ReaderNavDecision._(ReaderNavAction.block);

  final ReaderNavAction action;
  final ReaderCta? cta;

  /// [ReaderNavAction.openUnit]: the unit to show instead.
  final String? unitId;

  @override
  String toString() =>
      'ReaderNavDecision(${action.name}, ${cta?.code}, $unitId)';
}

/// 1020c §1(3): only the initial load and `peizhu://` links pass.
///   - `peizhu://cta/<one of four>` → handled by the App (never loaded);
///   - `peizhu://reader/open?id=<id>` → the App shows that unit (T-R4b);
///   - the page's own first load (`about:blank` / `data:` in the main
///     frame, before it has finished loading once) → allowed;
///   - everything else — web links, `tel:`, `mailto:`, other `peizhu://`
///     (incl. `peizhu://explain`, never shown), in-page `#` jumps, frames
///     — is blocked and opens nothing.
ReaderNavDecision decideReaderNavigation(
  String url, {
  required bool isMainFrame,
  required bool initialLoadPending,
}) {
  final cta = ReaderCta.fromUrl(url);
  if (cta != null) return ReaderNavDecision._(ReaderNavAction.cta, cta);
  final open = readerOpenUnitId(url);
  if (open != null) {
    return ReaderNavDecision._(ReaderNavAction.openUnit, null, open);
  }
  final u = url.trim().toLowerCase();
  if (initialLoadPending &&
      isMainFrame &&
      (u == 'about:blank' || u.startsWith('data:'))) {
    return ReaderNavDecision.allow;
  }
  return ReaderNavDecision.block;
}

/// One message from the App's page script ([kReaderSectionScript]).
sealed class ReaderPageMessage {
  const ReaderPageMessage();
}

/// A section came on screen (→ `reader_section`).
class ReaderSectionReached extends ReaderPageMessage {
  const ReaderSectionReached(this.sectionId);
  final String sectionId;
}

/// 1021: the page's `peizhu:view` — where the reader is, and what has been
/// read so far (`peizhuReader.readIds()`).
class ReaderViewChanged extends ReaderPageMessage {
  const ReaderViewChanged({
    required this.sectionId,
    required this.index,
    required this.total,
    required this.readIds,
  });

  /// Null at the contents (目錄).
  final String? sectionId;

  /// 1-based section number, 0 at the contents.
  final int index;
  final int total;
  final Set<String> readIds;

  bool get atContents => sectionId == null;
}

/// Parse one channel message.  Anything malformed → null (ignored).  Only
/// ids pass; the page's text never does.
ReaderPageMessage? parseReaderMessage(String raw) {
  final m = raw.trim();
  if (m.startsWith('{')) {
    Object? decoded;
    try {
      decoded = jsonDecode(m);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final view = decoded['view'];
    if (view is! String) return null;
    final isToc = view == 'toc';
    if (!isToc && !kReaderIdPattern.hasMatch(view)) return null;
    int number(Object? v) => v is num && v.isFinite ? v.toInt().clamp(0, 99) : 0;
    final read = decoded['read'];
    return ReaderViewChanged(
      sectionId: isToc ? null : view,
      index: isToc ? 0 : number(decoded['index']),
      total: number(decoded['total']),
      readIds: {
        if (read is List)
          for (final r in read.take(99))
            if (r is String && kReaderIdPattern.hasMatch(r)) r,
      },
    );
  }
  if (!kReaderIdPattern.hasMatch(m)) return null;
  return ReaderSectionReached(m);
}

/// Runs a script in the page and returns what the platform gives back
/// (`WebViewController.runJavaScriptReturningResult`).
typedef ReaderJsEvaluator = Future<Object?> Function(String javaScript);

const String _backJs = '(function(){try{var r=window.peizhuReader;'
    "if(r&&r.back){return r.back()?'stay':'close';}}catch(e){}"
    "return 'none';})()";

const String _readIdsJs = '(function(){try{var r=window.peizhuReader;'
    'if(r&&r.readIds){return JSON.stringify(r.readIds()||[]);}}catch(e){}'
    "return '[]';})()";

/// 1021 T-R2 (2) / T-R3 — the App's calls into `window.peizhuReader`.
/// The view attaches an evaluator once the page exists; until then (or
/// for a page without `peizhuReader`) [back] is false — the App closes —
/// and [readIds] is null.
class ReaderJsBridge {
  ReaderJsEvaluator? _eval;

  void attach(ReaderJsEvaluator eval) => _eval = eval;

  void detach() => _eval = null;

  bool get isAttached => _eval != null;

  /// `peizhuReader.back()`: true = the page went from a section back to
  /// its contents (stay); false = it is at its contents, or has no
  /// `peizhuReader`, or did not answer within [timeout] (close).
  Future<bool> back({Duration timeout = const Duration(seconds: 2)}) async {
    final eval = _eval;
    if (eval == null) return false;
    try {
      return _plain(await eval(_backJs).timeout(timeout)) == 'stay';
    } catch (_) {
      return false;
    }
  }

  /// `peizhuReader.readIds()`, well-formed ids only; null when it cannot
  /// be read.
  Future<Set<String>?> readIds(
      {Duration timeout = const Duration(seconds: 2)}) async {
    final eval = _eval;
    if (eval == null) return null;
    try {
      Object? v = await eval(_readIdsJs).timeout(timeout);
      // Android hands back the JSON of the string; iOS the string itself.
      for (var i = 0; i < 2; i++) {
        final s = v;
        if (s is! String) break;
        try {
          v = jsonDecode(s);
        } catch (_) {
          break;
        }
      }
      if (v is! List) return null;
      return {
        for (final r in v.take(99))
          if (r is String && kReaderIdPattern.hasMatch(r)) r,
      };
    } catch (_) {
      return null;
    }
  }

  static String _plain(Object? v) {
    var s = '$v'.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    return s;
  }
}
