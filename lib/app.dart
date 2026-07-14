import 'package:clarity_flutter/clarity_flutter.dart';
import 'package:flutter/material.dart';

import 'bridge/insight.dart';
import 'core/alert_relay.dart';
import 'core/attribution_bureau.dart';
import 'core/gateway_api.dart';
import 'core/local_vault.dart';
import 'core/net_probe.dart';
import 'gate/boot_stage.dart';

class AegisThunderShell extends StatelessWidget {
  final LocalVault vault;
  final NetProbe netProbe;
  final AttributionBureau bureau;
  final GatewayApi gateway;
  final AlertRelay alerts;

  const AegisThunderShell({
    super.key,
    required this.vault,
    required this.netProbe,
    required this.bureau,
    required this.gateway,
    required this.alerts,
  });

  @override
  Widget build(BuildContext context) {
    return ClarityWidget(
      clarityConfig: Insight.config,
      app: MaterialApp(
        title: 'Aegis Thunder',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0B0F1A),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE8B94A),
            brightness: Brightness.dark,
          ),
        ),
        home: BootStage(
          vault: vault,
          netProbe: netProbe,
          bureau: bureau,
          gateway: gateway,
          alerts: alerts,
        ),
      ),
    );
  }
}
