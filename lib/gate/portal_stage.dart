import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/alert_relay.dart';
import '../core/local_vault.dart';
import '../core/net_probe.dart';
import '../core/user_agent_client.dart';
import 'offline_notice_stage.dart';

// Optional hook; unused today. Left here for the deferred import
// signature so the caller can `content.prepareForContent()` before
// showing the WebView. Also useful as a warm-up point if we ever
// want to pre-inflate `WebViewPlatform`.
Future<void> prepareForContent() async {}

class PortalStage extends StatefulWidget {
  final String targetUrl;
  final LocalVault vault;
  final AlertRelay alerts;
  final NetProbe netProbe;

  const PortalStage({
    super.key,
    required this.targetUrl,
    required this.vault,
    required this.alerts,
    required this.netProbe,
  });

  @override
  State<PortalStage> createState() => _PortalStageState();
}

class _PortalStageState extends State<PortalStage>
    with WidgetsBindingObserver {
  late final WebViewController _web;
  bool _busy = true;
  bool _routedOffline = false;
  String? _lastMainFrameUrl;
  int _redirectRetries = 0;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _offlineDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Portal supports both orientations.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _applyImmersive();
    _buildController();
    _wireConnectivity();
    widget.alerts.onUrl = _onPushUrl;
  }

  void _applyImmersive() {
    // Immersive-sticky hides both status bar and nav bar; auto-restores
    // on gesture. Reapplied when the app comes back from background.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _applyImmersive();
  }

  void _onPushUrl(String url) {
    if (!mounted) return;
    _web.loadRequest(Uri.parse(url));
  }

  void _wireConnectivity() {
    // 700 ms debounce absorbs the transient "none" burst that
    // connectivity_plus emits while a VPN tunnel comes up.
    _connSub = widget.netProbe.changes.listen((snapshot) {
      final gone = snapshot.every((s) => s == ConnectivityResult.none);
      if (!gone) {
        _offlineDebounce?.cancel();
        return;
      }
      _offlineDebounce?.cancel();
      _offlineDebounce = Timer(const Duration(milliseconds: 700), () {
        _hardOffline();
      });
    });
  }

  void _buildController() {
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(uaClient.userAgent)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _busy = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _busy = false);
          _redirectRetries = 0;
          _dropSafeAreaInsets();
          _installKeyboardHelper();
        },
        onWebResourceError: _onWebViewError,
        onNavigationRequest: _decide,
      ))
      ..enableZoom(false);

    _configureAndroidExtras();
    _web.loadRequest(Uri.parse(widget.targetUrl));
  }

  void _configureAndroidExtras() {
    if (!Platform.isAndroid) return;
    if (_web.platform is! AndroidWebViewController) return;
    final ctrl = _web.platform as AndroidWebViewController;
    ctrl.setMediaPlaybackRequiresUserGesture(false);
    ctrl.setOnShowFileSelector(_pickFilesForWeb);

    final cookies = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookies.setAcceptThirdPartyCookies(ctrl, true);
  }

  Future<List<String>> _pickFilesForWeb(FileSelectorParams params) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: FileType.any,
      );
      if (picked == null || picked.files.isEmpty) return const [];
      return picked.files
          .where((f) => f.path != null)
          .map((f) => Uri.file(f.path!).toString())
          .toList();
    } catch (_) {
      return const [];
    }
  }

  NavigationDecision _decide(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    const inWebViewSchemes = {'http', 'https', 'about', 'data', 'blob'};
    if (inWebViewSchemes.contains(uri.scheme)) {
      if (request.isMainFrame) _lastMainFrameUrl = request.url;
      return NavigationDecision.navigate;
    }
    _launchExternally(uri);
    return NavigationDecision.prevent;
  }

  void _onWebViewError(WebResourceError err) {
    if (err.isForMainFrame != true) return;

    // Cover the WebView with our loading spinner IMMEDIATELY so the
    // native "cannot connect" chrome never gets a chance to render.
    if (mounted) setState(() => _busy = true);

    final blurb = err.description.toLowerCase();
    final isRedirectLoop = blurb.contains('too_many_redirects') ||
        blurb.contains('too many redirects') ||
        err.errorCode == -1007 ||
        err.errorCode == -9;
    if (isRedirectLoop &&
        _lastMainFrameUrl != null &&
        _redirectRetries < 3) {
      _redirectRetries++;
      _web.loadRequest(Uri.parse(_lastMainFrameUrl!));
      return;
    }

    final isDnsOrNetwork = blurb.contains('name_not_resolved') ||
        blurb.contains('err_name_not_resolved') ||
        blurb.contains('internet_disconnected') ||
        blurb.contains('network_changed') ||
        err.errorCode == -105 ||
        err.errorCode == -106 ||
        err.errorCode == -21;
    if (isDnsOrNetwork) {
      _hardOffline();
    } else {
      _softOfflineCheck();
    }
  }

  Future<void> _softOfflineCheck() async {
    if (_routedOffline) return;
    if (await widget.netProbe.isLive()) return;
    _hardOffline();
  }

  Future<void> _hardOffline() async {
    if (_routedOffline || !mounted) return;
    _routedOffline = true;
    final current = await _web.currentUrl() ?? widget.targetUrl;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OfflineNoticeStage(
          onRetry: (ctx) => PortalStage(
            targetUrl: current,
            vault: widget.vault,
            alerts: widget.alerts,
            netProbe: widget.netProbe,
          ),
        ),
      ),
    );
  }

  Future<void> _launchExternally(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // ── JS helpers ────────────────────────────────────────

  void _installKeyboardHelper() {
    // Uses `behavior:'auto'` (never 'smooth' — see gray_part_pitfalls #3)
    // and a single 350 ms setTimeout to avoid piling up scrolls.
    _web.runJavaScript(r'''
(function() {
  if (window.__akbInit) return;
  window.__akbInit = true;

  function isEditable(el) {
    return el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA'
                  || el.isContentEditable);
  }
  function reveal() {
    var el = document.activeElement;
    if (!isEditable(el)) return;
    var vp = window.visualViewport;
    if (vp) {
      var rect = el.getBoundingClientRect();
      var bottom = vp.offsetTop + vp.height;
      if (rect.bottom > bottom - 20 || rect.top < vp.offsetTop) {
        el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
      }
    } else {
      el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
    }
  }
  document.addEventListener('focusin', function(e) {
    if (isEditable(e.target)) setTimeout(reveal, 350);
  });
  if (window.visualViewport) {
    var prev = window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function() {
      var now = window.visualViewport.height;
      if (now < prev) setTimeout(reveal, 120);
      prev = now;
    });
  }
})();
''');
  }

  void _dropSafeAreaInsets() {
    // Removes the site's own safe-area padding on notched devices
    // so we don't end up with a black band under the notch.
    // Skips re-applying while the keyboard is up (would trigger a
    // WebKit layout re-flow during keyboard animation).
    _web.runJavaScript(r'''
(function() {
  if (window.__atsaRunning) return;
  window.__atsaRunning = true;

  var STYLE_ID = '__ats_style';
  var CSS = ':root{'
    + '--safe-area-inset-top:0px!important;'
    + '--safe-area-inset-right:0px!important;'
    + '--safe-area-inset-bottom:0px!important;'
    + '--safe-area-inset-left:0px!important;'
    + '--sat:0px!important;--sar:0px!important;'
    + '--sab:0px!important;--sal:0px!important;'
    + '--safe-top:0px!important;--safe-right:0px!important;'
    + '--safe-bottom:0px!important;--safe-left:0px!important;}'
    + 'html,body,#__nuxt,#__layout,#app,#root{'
    + 'padding-top:0!important;padding-left:0!important;'
    + 'padding-right:0!important;margin-top:0!important;}';

  function kbUp() {
    if (!window.visualViewport) return false;
    return window.visualViewport.height < window.innerHeight * 0.75;
  }
  function apply() {
    if (kbUp()) return; // don't reflow during keyboard animation
    var head = document.head || document.documentElement;
    if (!head) return;
    var meta = document.querySelector('meta[name="viewport"]');
    if (meta && !/viewport-fit\s*=\s*contain/i.test(meta.getAttribute('content') || '')) {
      var current = (meta.getAttribute('content') || '')
        .replace(/,?\s*viewport-fit\s*=\s*\w+/ig, '').trim();
      meta.setAttribute('content', current + (current ? ', ' : '') + 'viewport-fit=contain');
    }
    var el = document.getElementById(STYLE_ID);
    if (!el) {
      el = document.createElement('style');
      el.id = STYLE_ID;
      head.appendChild(el);
    }
    if (el.textContent !== CSS) el.textContent = CSS;
    if (head.lastElementChild !== el) head.appendChild(el);
  }

  apply();
  ['pushState', 'replaceState'].forEach(function(fn) {
    var orig = history[fn];
    history[fn] = function() {
      var r = orig.apply(this, arguments);
      setTimeout(apply, 80);
      setTimeout(apply, 400);
      return r;
    };
  });
  window.addEventListener('popstate', function() { setTimeout(apply, 80); });
  setInterval(apply, 2500);
})();
''');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offlineDebounce?.cancel();
    _connSub?.cancel();
    widget.alerts.onUrl = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    // Do NOT lock orientation here — the successor route (OfflineNoticeStage
    // or MainMenuScreen) sets its own orientations in initState. Locking
    // portrait here would override that and break the landscape no-wifi view.
    super.dispose();
  }

  Future<bool> _handleBack() async {
    if (await _web.canGoBack()) {
      await _web.goBack();
    }
    return false; // never pop out of the app
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // CRITICAL: false so `windowSoftInputMode=adjustResize` in the
        // manifest is the sole handler of keyboard resizing (avoids the
        // dual-resize jitter — see gray_part_pitfalls).
        resizeToAvoidBottomInset: false,
        body: Stack(fit: StackFit.expand, children: [
          _webviewBody(context),
          if (_busy)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE8B94A)),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _webviewBody(BuildContext context) {
    final orient = MediaQuery.of(context).orientation;
    final vpad = MediaQuery.of(context).viewPadding;

    // In portrait: leave a top gap = status-bar height so the notch
    // never overlays the WebView content.
    // In landscape: keep left/right insets so the WebView cannot
    // creep under a side-mounted camera cutout.
    final padding = orient == Orientation.landscape
        ? EdgeInsets.only(left: vpad.left, right: vpad.right)
        : EdgeInsets.only(top: vpad.top);

    return Padding(
      padding: padding,
      child: WebViewWidget(controller: _web),
    );
  }
}
