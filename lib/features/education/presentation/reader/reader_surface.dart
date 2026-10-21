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
    required this.onMessage,
    required this.onCta,
    required this.onOpenUnit,
    required this.bridge,
    required this.background,
  });

  /// Already prepared ([prepareReaderHtml]: CSP, `data-chrome` /
  /// `data-ask`, viewport, `--fs`, read state, the App's page script).
  /// A new value (「讀下一篇」, T-R4b) loads in the same view.
  final String html;

  /// Raw message from the App's page script ([parseReaderMessage]; the
  /// page validates it).
  final ValueChanged<String> onMessage;

  /// One of the `peizhu://cta/…` links was tapped.
  final ValueChanged<ReaderCta> onCta;

  /// 1021 T-R4b: `peizhu://reader/open?id=<id>` was tapped.
  final ValueChanged<String> onOpenUnit;

  /// 1021 T-R2 / T-R3: the view attaches its JavaScript runner here, so
  /// the page can call `window.peizhuReader.back()` / `readIds()`.
  final ReaderJsBridge bridge;

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
        onMessageReceived: (m) => widget.request.onMessage(m.message),
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
            case ReaderNavAction.openUnit:
              widget.request.onOpenUnit(d.unitId!);
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
    widget.request.bridge.attach(_controller.runJavaScriptReturningResult);
    // No base URL: the page has no origin to load relative files from.
    _controller.loadHtmlString(widget.request.html);
  }

  @override
  void didUpdateWidget(_WebViewReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.request.bridge, widget.request.bridge)) {
      oldWidget.request.bridge.detach();
      widget.request.bridge.attach(_controller.runJavaScriptReturningResult);
    }
    // 「讀下一篇」 (T-R4b): another unit in the same view.
    if (oldWidget.request.html != widget.request.html) {
      _initialLoadPending = true;
      _controller.loadHtmlString(widget.request.html);
    }
  }

  @override
  void dispose() {
    widget.request.bridge.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
