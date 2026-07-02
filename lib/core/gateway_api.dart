import 'dart:convert';

import '../data/gateway_reply.dart';
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
      return GatewayReply.failure('gateway-not-configured');
    }
    try {
      final response = await uaClient
          .post(
            Uri.parse(url),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(ShellSettings.gatewayCallTimeout);

      if (response.statusCode != 200) {
        return GatewayReply.failure('http-${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return GatewayReply.failure('bad-shape');
      }
      final reply = GatewayReply.fromMap(decoded);

      if (reply.approved && reply.destination != null) {
        await _vault.writeOfferUrl(reply.destination!);
        if (reply.expiresAt != null) {
          await _vault.writeOfferExpiry(reply.expiresAt!);
        }
      }
      return reply;
    } catch (e) {
      return GatewayReply.failure(e.toString());
    }
  }

  Future<String?> cachedOfferUrl() => _vault.readOfferUrl();
}
