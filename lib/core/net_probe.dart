import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

// NetProbe – "am I actually online?" helper.
//
// The plain `Connectivity.checkConnectivity` API only tells us whether
// an interface is up; it will happily report a WiFi link even when the
// captive portal is intercepting DNS. We combine the two signals:
//
//   1. connectivity_plus reports at least one *usable* interface, AND
//   2. we can resolve a well-known host within 7 s.
//
// VPN, Bluetooth-tether and "other" interfaces are treated as valid —
// they carry real traffic even though many out-of-the-box demos ignore
// them (see gray_part_pitfalls #3).

class NetProbe {
  static const Set<ConnectivityResult> _liveInterfaces = {
    ConnectivityResult.wifi,
    ConnectivityResult.mobile,
    ConnectivityResult.ethernet,
    ConnectivityResult.vpn,
    ConnectivityResult.bluetooth,
    ConnectivityResult.other,
  };

  // Hosts rotate through the list so a single blocked resolver doesn't
  // force the app permanently offline.
  static const List<String> _probeHosts = <String>[
    'clients3.google.com',
    'cloudflare.com',
    'apple.com',
  ];

  final Connectivity _sensor = Connectivity();

  Future<bool> isLive() async {
    final results = await _sensor.checkConnectivity();
    if (!results.any(_liveInterfaces.contains)) return false;

    // Rotate: pick host based on the current second so consecutive
    // retries hit different resolvers.
    final idx = DateTime.now().second % _probeHosts.length;
    for (var i = 0; i < _probeHosts.length; i++) {
      final host = _probeHosts[(idx + i) % _probeHosts.length];
      try {
        final ans = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 7));
        if (ans.isNotEmpty && ans.first.rawAddress.isNotEmpty) return true;
      } on SocketException {
        return false; // route unreachable — no point trying other hosts
      } on TimeoutException {
        // try the next host
      } catch (_) {
        // treat unknown failures as inconclusive; try the next host
      }
    }
    return false;
  }

  Stream<List<ConnectivityResult>> get changes =>
      _sensor.onConnectivityChanged;
}
