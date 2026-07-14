import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/alert_relay.dart';
import 'core/attribution_bureau.dart';
import 'core/gateway_api.dart'; 
import 'core/local_vault.dart';
import 'core/net_probe.dart';
import 'core/user_agent_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase + App Check are best-effort. Missing google-services.json
  // must not crash the app — the gray flow simply proceeds without
  // push and the App-Check-gated endpoint short-circuits to "arcade".
  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
    );
  } catch (_) {}

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0B0F1A),
  ));

  await uaClient.prepare();

  final vault = LocalVault();
  await vault.init();

  final netProbe = NetProbe();
  final bureau = AttributionBureau();
  final gateway = GatewayApi(vault);
  final alerts = AlertRelay(vault);

  runApp(AegisThunderShell(
    vault: vault,
    netProbe: netProbe,
    bureau: bureau,
    gateway: gateway,
    alerts: alerts,
  ));
}
