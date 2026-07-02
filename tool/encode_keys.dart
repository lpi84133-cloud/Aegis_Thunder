// Run: `dart run tool/encode_keys.dart`
//
// Fills in the byte-array slots in lib/env/gateway_env.dart,
// lib/env/attribution_env.dart and lib/core/user_agent_client.dart
// after you paste the plaintext values in the map below.
//
// IMPORTANT: use this Dart script (never a PowerShell foreach — see
// gray_part_pitfalls: PowerShell overflows int32 on Windows and
// generates the wrong bytes, causing "Invalid HTTP header field
// value" at runtime).

import '../lib/vault/scrambler.dart';

void main() {
  final secrets = <String, String>{
    // Config endpoint — split into host and path
    'gateway.host': 'https://aegisthunder.com',
    'gateway.path': '/config.php',

    'appsflyer.devKey': 'o5TqMXnXytrdGBwB6ZKUFH',
    'appsflyer.senderId': '829309830652',

    // GCD fallback endpoint (AppsFlyer standard)
    'gcd.host': 'https://gcdsdk.appsflyer.com',
    'gcd.path': '/install_data/v4.0/',

    // Chrome/WebKit version fragments used in the User-Agent
    'ua.chromeVersion': '132.0.6834.163',
    'ua.webkitVersion': '605.1.15',
  };

  print('// ─── Encoded byte arrays ─────────────────────────');
  print('// paste each entry into the matching const in lib/env/');
  print('');
  for (final entry in secrets.entries) {
    final bytes = scramble(entry.value);
    final label = entry.key;
    print('/* $label = "${entry.value}" */');
    print('const List<int> _${_slug(label)} = <int>${bytes.toString()};');
    print('');
  }
}

String _slug(String key) => key
    .split('.')
    .expand((segment) => [segment[0].toUpperCase(), segment.substring(1)])
    .join()
    .replaceRange(0, 1, key.split('.').first[0].toLowerCase());
