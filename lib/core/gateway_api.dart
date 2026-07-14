import 'dart:convert';

import '../data/gateway_reply.dart';
import '../env/debug_flags.dart';
import '../env/shell_settings.dart';
import 'local_vault.dart';
import 'user_agent_client.dart';

// GatewayApi is the thin client for the config endpoint that decides
// whether this install should show the WebView or fall back to the game.
//
// On success we persist (url, expires) inside the LocalVault so that a
// subsequent cold launch can display the offer even before AppsFlyer
// re-issues attribution data.

class GatewayApi {
  final LocalVault _vault;

  GatewayApi(this._vault);

  Future<GatewayReply> submit(Map<String, dynamic> body) async {
    final url = ShellSettings.gatewayUrl;
    if (url.isEmpty) {
      grayLog('gateway submit SKIPPED: url empty (gateway-not-configured)');
      return GatewayReply.failure('gateway-not-configured');
    }
    grayLog('gateway POST $url');
    try {
      final response = await uaClient
          .post(
            Uri.parse(url),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(ShellSettings.gatewayCallTimeout);

      grayLog('gateway HTTP ${response.statusCode}, '
          'body=${response.body.length > 500 ? '${response.body.substring(0, 500)}…' : response.body}');

      // Per android_gray_guide.md §9: a genuine backend verdict can
      // arrive with a non-200 status (the test backend returns HTTP
      // 404 + {"ok":false} for organic installs). So we parse the body
      // regardless of status code — if it's valid JSON with the
      // contract shape, it's a real decision (responded=true), NOT a
      // transient failure. Only a non-JSON / unreadable response is
      // treated as transient (retry on the next launch).
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }
      if (decoded is! Map<String, dynamic>) {
        grayLog('gateway reply non-JSON (status ${response.statusCode}) '
            '→ transient failure');
        return GatewayReply.failure('http-${response.statusCode}-nonjson');
      }

      final reply = GatewayReply.fromMap(decoded);
      grayLog('gateway reply parsed (responded): approved=${reply.approved} '
          'url=${reply.destination} message=${reply.explanation}');

      if (reply.approved && reply.destination != null) {
        await _vault.writeOfferUrl(reply.destination!);
        if (reply.expiresAt != null) {
          await _vault.writeOfferExpiry(reply.expiresAt!);
        }
      }
      return reply;
    } catch (e) {
      grayLog('gateway submit FAILED (transient, no response): $e');
      return GatewayReply.failure(e.toString());
    }
  }

  Future<String?> cachedOfferUrl() => _vault.readOfferUrl();
}
