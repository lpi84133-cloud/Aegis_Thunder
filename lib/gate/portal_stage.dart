import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../bridge/insight.dart';
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
  bool _offerReached = false;
  bool _pageHadError = false;
  String? _lastMainFrameUrl;
  int _redirectRetries = 0;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _offlineDebounce;

  // URL matchers for funnel tracking.
  static final _depositRx = RegExp(
    r'(deposit|cashier|top.?up|add funds|replenish|payment|pay now|checkout|withdraw|'
    r'пополн|депозит|касс|оплат|внести|вывод|платеж)',
    caseSensitive: false,
  );
  static final _registerRx = RegExp(
    r'(sign.?up|regist|create.?account|регистрац|зарегистр)',
    caseSensitive: false,
  );
  static final _loginRx = RegExp(
    r'(sign.?in|log.?in|log.?on|/auth\b|authoriz|войти|вход|авториз)',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    Insight.screen('web');
    Insight.event('web_open');
  }

  void _applyImmersive() {
    // Hide the status bar but keep navigation buttons always visible.
    //
    // immersiveSticky hides nav buttons and auto-restores them on touch.
    // On button-navigation devices this causes a resize event every time
    // the keyboard opens (nav bar pops in → window shrinks → WebView
    // shifts → jitter). Keeping nav buttons always visible eliminates
    // that extra resize cycle.
    //
    // We hide only the top overlay (status bar) so the battery/clock HUD
    // stays hidden while the WebView is shown.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.bottom],
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyImmersive();
      Insight.event('web_foreground');
    } else if (state == AppLifecycleState.paused) {
      Insight.event('web_background');
    }
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
      ..addJavaScriptChannel(
        'AegisInsight',
        onMessageReceived: (m) => _onWebSignal(m.message),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          _pageHadError = false;
          if (mounted) setState(() => _busy = true);
        },
        onPageFinished: (url) {
          if (mounted) setState(() => _busy = false);
          _redirectRetries = 0;
          _dropSafeAreaInsets();
          _installKeyboardHelper();
          _installInsightProbe();
          _trackWebPage(url);
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
    // Keep text at 100 % so the page is not artificially enlarged.
    ctrl.setTextZoom(100);

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
    Insight.event('web_external');
    Insight.tag('web_external_scheme', uri.scheme);
    _launchExternally(uri);
    return NavigationDecision.prevent;
  }

  void _onWebViewError(WebResourceError err) {
    if (err.isForMainFrame != true) return;

    _pageHadError = true;
    if (mounted) setState(() => _busy = true);

    final reason = _classifyWebError(err);
    final failed = _lastMainFrameUrl ?? widget.targetUrl;
    final host = Uri.tryParse(failed)?.host ?? '';
    Insight.event('web_error');
    Insight.tag('web_error_reason', reason);
    Insight.tag('web_last_error', '${err.errorCode}:${err.description}');
    if (host.isNotEmpty) Insight.tag('web_error_host', host);
    if (!_offerReached) {
      Insight.event('web_offer_unreachable');
      Insight.tag('offer_reached', 'false');
      Insight.tag('offer_unreachable_reason', reason);
    } else {
      Insight.event('web_error_after_load');
    }

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

  static String _classifyWebError(WebResourceError err) {
    final d = err.description.toLowerCase();
    final c = err.errorCode;
    if (d.contains('connection_refused') || d.contains('connection refused')) return 'connection_refused';
    if (d.contains('too_many_redirects') || d.contains('too many redirects')) return 'redirect_loop';
    if (d.contains('name_not_resolved') || d.contains('address_unreachable') || d.contains('unknownhost') || c == -2) return 'dns_unresolved';
    if (d.contains('timed out') || d.contains('timeout') || c == -8) return 'timeout';
    if (d.contains('internet_disconnected') || d.contains('network_changed') || c == -6) return 'no_network';
    if (d.contains('connection_reset')) return 'connection_reset';
    if (d.contains('connection_closed') || d.contains('empty_response')) return 'connection_closed';
    if (d.contains('ssl') || d.contains('cert') || c == -11) return 'ssl_error';
    if (d.contains('blocked')) return 'blocked';
    return 'other';
  }

  void _trackWebPage(String url) {
    final uri = Uri.tryParse(url);
    Insight.screenName('web:${uri == null ? url : '${uri.host}${uri.path}'}');
    Insight.event('web_page');
    Insight.tag('web_last_url', url);
    if (!_offerReached && !_pageHadError) {
      _offerReached = true;
      Insight.event('web_offer_reached');
      Insight.tag('offer_reached', 'true');
      if (uri?.host != null) Insight.tag('offer_host', uri!.host);
    }
    if (_depositRx.hasMatch(url)) {
      Insight.event('web_cashier_page');
      Insight.tag('reached_cashier', 'true');
    }
    _trackAuthPage(url);
  }

  void _trackAuthPage(String url) {
    if (_registerRx.hasMatch(url)) {
      Insight.event('web_register_page');
      Insight.tag('reached_register', 'true');
    } else if (_loginRx.hasMatch(url)) {
      Insight.event('web_login_page');
      Insight.tag('reached_login', 'true');
    }
  }

  void _onWebSignal(String raw) {
    final i = raw.indexOf(':');
    final type = i < 0 ? raw : raw.substring(0, i);
    final data = i < 0 ? '' : raw.substring(i + 1);
    switch (type) {
      case 'path':
        Insight.event('web_spa_route');
        Insight.tag('web_last_path', data);
        if (_depositRx.hasMatch(data)) {
          Insight.event('web_cashier_page');
          Insight.tag('reached_cashier', 'true');
        }
        _trackAuthPage(data);
        break;
      case 'deposit_click':
        Insight.event('web_deposit_click');
        Insight.tag('deposit_intent', 'true');
        if (data.isNotEmpty) Insight.tag('deposit_label', data);
        break;
      case 'register_click':
        Insight.event('web_register_click');
        Insight.tag('register_intent', 'true');
        break;
      case 'login_click':
        Insight.event('web_login_click');
        Insight.tag('login_intent', 'true');
        break;
      case 'auth_submit':
        if (data == 'register') {
          Insight.event('web_register_submit');
          Insight.tag('attempted_register', 'true');
        } else {
          Insight.event('web_login_submit');
          Insight.tag('attempted_login', 'true');
        }
        break;
      case 'form_submit':
        Insight.event('web_form_submit');
        break;
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

  void _installInsightProbe() {
    _web.runJavaScript(r'''
(function(){
  if (window.__aegisInsight) return; window.__aegisInsight = true;
  function send(t){ try { AegisInsight.postMessage(t); } catch(e){} }
  var DEP=/(deposit|cashier|top.?up|add funds|replenish|payment|pay now|checkout|withdraw|пополн|депозит|касс|оплат|внести|вывод|платеж)/i;
  var REG=/(sign.?up|regist|create.?account|регистрац|зарегистр)/i;
  var LOG=/(sign.?in|log.?in|log.?on|войти|вход|авториз)/i;
  var lastPath='';
  function reportPath(){ var p=location.pathname+location.search; if(p!==lastPath){ lastPath=p; send('path:'+p);} }
  reportPath();
  ['pushState','replaceState'].forEach(function(fn){ var o=history[fn]; history[fn]=function(){ var r=o.apply(this,arguments); setTimeout(reportPath,60); return r; }; });
  window.addEventListener('popstate',function(){ setTimeout(reportPath,60); });
  document.addEventListener('click',function(e){
    try{ var el=e.target;
      for(var i=0;i<4&&el;i++){
        var t=((el.innerText||el.value||(el.getAttribute&&el.getAttribute('aria-label'))||'')+'').trim();
        if(t){ if(DEP.test(t)){send('deposit_click:'+t.slice(0,60));return;}
               if(REG.test(t)){send('register_click:'+t.slice(0,60));return;}
               if(LOG.test(t)){send('login_click:'+t.slice(0,60));return;} }
        el=el.parentElement;
      }
    }catch(x){}
  },true);
  document.addEventListener('submit',function(e){
    try{ var f=e.target;
      var pw=f.querySelectorAll?f.querySelectorAll('input[type="password"]'):[];
      var blob=((f.innerText||'')+' '+(f.getAttribute('action')||'')+' '+(f.className||''));
      var confirm=f.querySelector&&(f.querySelector('input[name*="confirm" i]')||f.querySelector('input[name*="repeat" i]'));
      if(pw&&pw.length>=2){send('auth_submit:register');return;}
      if(pw&&pw.length===1){ send('auth_submit:'+((confirm||REG.test(blob))?'register':'login')); return; }
      if(REG.test(blob)){send('auth_submit:register');return;}
      if(LOG.test(blob)){send('auth_submit:login');return;}
      send('form_submit');
    }catch(x){ send('form_submit'); }
  },true);
})();
''');
  }

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
  // Only zero-out the CSS custom properties that sites use for
  // safe-area env() padding — this removes notch white-bands.
  // We intentionally DO NOT touch padding-left/right or margin on
  // html/body/#app — that would destroy the site's own layout.
  var CSS = ':root{'
    + '--safe-area-inset-top:0px!important;'
    + '--safe-area-inset-right:0px!important;'
    + '--safe-area-inset-bottom:0px!important;'
    + '--safe-area-inset-left:0px!important;'
    + '--sat:0px!important;--sar:0px!important;'
    + '--sab:0px!important;--sal:0px!important;'
    + '--safe-top:0px!important;--safe-right:0px!important;'
    + '--safe-bottom:0px!important;--safe-left:0px!important;}'
    // Only service header wrappers get their top padding zeroed.
    + '.gameview-mobile-header,.app-header{'
    + 'padding-top:0!important;margin-top:0!important;}';

  function kbUp() {
    if (!window.visualViewport) return false;
    return window.visualViewport.height < window.innerHeight * 0.75;
  }
  function apply() {
    if (kbUp()) return; // don't reflow during keyboard animation
    var head = document.head || document.documentElement;
    if (!head) return;
    // Force a device-width viewport so the page is not zoomed in.
    // Some sites omit the viewport meta or set a fixed width, which
    // makes Android WebView render the page at its natural (large) size.
    var meta = document.querySelector('meta[name="viewport"]');
    var desired = 'width=device-width, initial-scale=1.0, '
      + 'maximum-scale=1.0, user-scalable=no, viewport-fit=contain';
    if (!meta) {
      meta = document.createElement('meta');
      meta.setAttribute('name', 'viewport');
      head.appendChild(meta);
    }
    if (meta.getAttribute('content') !== desired) {
      meta.setAttribute('content', desired);
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

    // Status bar is hidden → vpad.top is 0, but we keep it for
    // safety (e.g. notch / hole-punch camera still needs the gap).
    // Nav buttons are always visible → add vpad.bottom so WebView
    // content is never hidden behind the navigation bar.
    // Landscape: also guard against side-mounted camera cutouts.
    final padding = orient == Orientation.landscape
        ? EdgeInsets.only(
            left: vpad.left,
            right: vpad.right,
            bottom: vpad.bottom,
          )
        : EdgeInsets.only(
            top: vpad.top,
            bottom: vpad.bottom,
          );

    return Padding(
      padding: padding,
      child: WebViewWidget(controller: _web),
    );
  }
}
