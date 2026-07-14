import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../env/attribution_env.dart';
import '../env/debug_flags.dart';
import '../env/shell_settings.dart';
import 'user_agent_client.dart';

// AttributionBureau owns the AppsFlyer lifecycle and produces the
// map that gets POST-ed to the config endpoint.
//
// The tricky bit is the "false Organic" scenario: the SDK sometimes
// fires onInstallConversionData with af_status == "Organic" on the
// very first callback even for paid installs. When that happens we
// wait for [ShellSettings.gcdRetryDelay], then re-query attribution
// through the raw GCD REST endpoint and prefer that answer.

class AttributionBureau {
  AppsflyerSdk? _sdk;

  Map<String, dynamic>? _installData;
  Map<String, dynamic>? _deepLinkData;
  Map<String, dynamic>? _reopenData;

  final Completer<Map<String, dynamic>> _installReady = Completer();
  final Completer<void> _deepLinkReady = Completer();

  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    final devKey = ShellSettings.devKey;
    // Without a key there's no point booting the SDK — we still
    // "complete" both futures so the splash flow does not hang.
    if (devKey.isEmpty) {
      if (!_installReady.isCompleted) _installReady.complete({});
      if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
      return;
    }

    final options = AppsFlyerOptions(
      afDevKey: devKey,
      appId: ShellSettings.appStoreId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );

    _sdk = AppsflyerSdk(options);

    _sdk!.onInstallConversionData(_onInstallData);
    _sdk!.onAppOpenAttribution(_onReopen);
    _sdk!.onDeepLinking(_onDeepLink);

    await _sdk!.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
  }

  Future<void> _onInstallData(dynamic raw) async {
    final Map<String, dynamic> payload = _flatten(raw);
    grayLog('onInstallConversionData: af_status=${payload['af_status']} '
        'media_source=${payload['media_source']} '
        'campaign=${payload['campaign']} '
        'is_first_launch=${payload['is_first_launch']}');
    grayLog('onInstallConversionData raw=$payload');
    if (payload['af_status'] == 'Organic') {
      // False-organic recovery: AppsFlyer often reports "Organic" on
      // the first callback because its own GCD lookup hasn't propagated
      // yet (the log shows GCD → 404 "attribution not available"). We
      // re-query GCD a few times with a delay, stopping as soon as a
      // Non-organic answer arrives. Total time stays within
      // attributionMaxWait (30 s): 3 × (5 s + ~3 s) ≈ 24 s.
      _installData = payload;
      const maxAttempts = 3;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        grayLog('af_status=Organic → GCD re-check attempt $attempt/$maxAttempts '
            'after ${ShellSettings.gcdRetryDelay}');
        await Future<void>.delayed(ShellSettings.gcdRetryDelay);
        final retry = await _fetchGcd();
        final retryStatus = retry?['af_status']?.toString();
        grayLog('GCD attempt $attempt result: '
            '${retry == null ? 'null (no data yet)' : 'af_status=$retryStatus'}');
        if (retry != null && retry.isNotEmpty) {
          _installData = retry;
          if (retryStatus != null && retryStatus != 'Organic') {
            grayLog('GCD resolved Non-organic → stop retrying');
            break;
          }
        }
      }
    } else {
      _installData = payload;
    }
    if (!_installReady.isCompleted) _installReady.complete(_installData!);
  }

  void _onReopen(dynamic raw) {
    _reopenData = _flatten(raw);
  }

  void _onDeepLink(DeepLinkResult result) {
    try {
      final ev = result.deepLink?.clickEvent;
      if (ev != null) {
        _deepLinkData = Map<String, dynamic>.from(ev);
      }
    } catch (_) {}
    if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
  }

  Map<String, dynamic> _flatten(dynamic raw) {
    if (raw is Map) {
      // The SDK sometimes wraps the true attribution dict under
      // "payload" and sometimes returns it flat — handle both.
      final direct = Map<String, dynamic>.from(raw);
      final nested = direct['payload'];
      if (nested is Map) return Map<String, dynamic>.from(nested);
      return direct;
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> waitForInstall({Duration? within}) {
    return _installReady.future.timeout(
      within ?? ShellSettings.attributionMaxWait,
      onTimeout: () => <String, dynamic>{},
    );
  }

  Future<void> waitForDeepLink({Duration? within}) {
    return _deepLinkReady.future.timeout(
      within ?? ShellSettings.deepLinkMaxWait,
      onTimeout: () {},
    );
  }

  Future<String?> currentUid() async {
    try {
      return await _sdk?.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchGcd() async {
    final uid = await currentUid();
    if (uid == null || uid.isEmpty) return null;
    final appId = Platform.isIOS
        ? ShellSettings.appStoreId
        : ShellSettings.bundleId;
    final url = resolveGcdUrl(appId: appId, deviceId: uid);
    if (url.isEmpty) return null;
    try {
      final resp = await uaClient.get(
        Uri.parse(url),
        headers: {'authorization': 'Bearer ${ShellSettings.devKey}'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  /// Build the merged payload sent to the config endpoint.
  ///
  /// Order matters:
  ///   1. install-conversion payload — added as-is (never rewritten)
  ///   2. deep-link click payload — putIfAbsent (won't overwrite)
  ///   3. app-open attribution — putIfAbsent
  ///   4. device-side fields — always added last (may overwrite)
  Future<Map<String, dynamic>> composePayload({
    required String locale,
    String? pushToken,
  }) async {
    final body = <String, dynamic>{};
    (_installData ?? const {}).forEach((k, v) => body[k] = v);
    (_deepLinkData ?? const {}).forEach((k, v) => body.putIfAbsent(k, () => v));
    (_reopenData ?? const {}).forEach((k, v) => body.putIfAbsent(k, () => v));

    body['af_id'] = (await currentUid()) ?? '';
    body['bundle_id'] = ShellSettings.bundleId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = ShellSettings.storeId;
    body['locale'] = locale;
    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    final senderId = ShellSettings.senderId;
    if (senderId.isNotEmpty) {
      body['firebase_project_id'] = senderId;
    }

    grayLog('composePayload → af_status=${body['af_status']} '
        'media_source=${body['media_source']} '
        'af_id=${body['af_id']} '
        'push_token=${(pushToken == null || pushToken.isEmpty) ? 'MISSING' : 'present'}');
    grayLog('composePayload full=${jsonEncode(body)}');
    return body;
  }
}
