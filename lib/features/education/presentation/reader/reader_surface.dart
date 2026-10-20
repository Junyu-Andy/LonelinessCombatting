/// 1020c §1(3) — the view that shows a prepared 小讀本 page.
///
/// The reader page talks to a [ReaderSurface], not to the WebView, the
/// same way voice input talks to `VoiceRecorder`: the App uses
/// [WebViewReaderSurface]; widget tests pass a fake (a platform view does
/// not render in `flutter test`).  This file is the only one that imports
/// `webview_flutter`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../data/reader_html.dart';

/// What the reader page hands the view.
@immutable
class ReaderSurfaceRequest {
  const ReaderSurfaceRequest({
    required this.html,
    required this.onSection,
    required this.onCta,
    required this.background,
  });

  /// Already prepared ([prepareReaderHtml]: CSP, viewport, `--fs`,
  /// section script).
  final String html;

  /// Raw message from the page's section script (the page validates it).
  final ValueChanged<String> onSection;

  /// One of the three `peizhu://cta/…` links was tapped.
  final ValueChanged<ReaderCta> onCta;

  final Color background;
}

abstract class ReaderSurface {
  const ReaderSurface();

  Widget build(BuildContext context, ReaderSurfaceRequest request);
}

/// The real view: `webview_flutter` (WKWebView on iPhone, the system
/// WebView on Android).
class WebViewReaderSurface extends ReaderSurface {
  const WebViewReaderSurface();

  @override
  Widget build(BuildContext context, ReaderSurfaceRequest request) =>
      _WebViewReader(request: request);
}

class _WebViewReader extends StatefulWidget {
  const _WebViewReader({required this.request});

  final ReaderSurfaceRequest request;

  @override
  State<_WebViewReader> createState() => _WebViewReaderState();
}

class _WebViewReaderState extends State<_WebViewReader> {
  late final WebViewController _controller;

  /// True until the page has finished its first load: only then may the
  /// page's own `about:blank` load through ([decideReaderNavigation]).
  bool _initialLoadPending = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..setBackgroundColor(widget.request.background)
      ..addJavaScriptChannel(
        kReaderJsChannel,
        onMessageReceived: (m) => widget.request.onSection(m.message),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final d = decideReaderNavigation(
            request.url,
            isMainFrame: request.isMainFrame,
            initialLoadPending: _initialLoadPending,
          );
          switch (d.action) {
            case ReaderNavAction.allow:
              return NavigationDecision.navigate;
            case ReaderNavAction.cta:
              widget.request.onCta(d.cta!);
              return NavigationDecision.prevent;
            case ReaderNavAction.block:
              if (kDebugMode) debugPrint('[Readers] blocked ${request.url}');
              return NavigationDecision.prevent;
          }
        },
        onPageFinished: (_) => _initialLoadPending = false,
      ));
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      // Only `--fs` sizes the text, not the phone's font setting on top.
      platform.setTextZoom(100);
      platform.setAllowFileAccess(false);
      platform.setAllowContentAccess(false);
    }
    if (platform is WebKitWebViewController) {
      // No long-press link preview / "open" menu.
      platform.setAllowsLinkPreview(false);
      platform.setAllowsBackForwardNavigationGestures(false);
    }
    // No base URL: the page has no origin to load relative files from.
    _controller.loadHtmlString(widget.request.html);
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
