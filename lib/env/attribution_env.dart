import '../vault/scrambler.dart';

// AppsFlyer Dev Key + Firebase sender id.
// Both live as scrambled byte arrays for the same reason as the
// config endpoint — they must not be greppable in the binary.
//
// TODO(release): populate these arrays after receiving the real
// credentials from the manager (encode with `tool/encode_keys.dart`).

// AppsFlyer Dev Key.  Plain  →  "o5TqMXnXytrdGBwB6ZKUFH"
const List<int> _devKeyBytes = <int>[
  214, 47, 118, 17, 124, 136, 208, 187, 144, 93, 181, 113, 2, 193, 208, 73,
  183, 193, 178, 31, 30, 227,
];

// Firebase project number (sender id).  Plain  →  "829309830652"
const List<int> _senderIdBytes = <int>[
  129, 40, 27, 83, 1, 233, 134, 208, 217, 31, 242, 39,
];

// GCD host  →  "https://gcdsdk.appsflyer.com"
const List<int> _gcdHostBytes = <int>[
  209, 110, 86, 16, 66, 234, 145, 204, 142, 74, 163, 102, 33, 232, 137, 106,
  241, 235, 138, 44, 52, 210, 154, 188, 151, 121, 77, 13,
];

// GCD path  →  "/install_data/v4.0/"
const List<int> _gcdPathBytes = <int>[
  150, 115, 76, 19, 69, 177, 210, 143, 182, 77, 166, 97, 36, 172, 209, 63,
  175, 171, 214,
];

String resolveDevKey() => unscramble(_devKeyBytes);

String resolveSenderId() => unscramble(_senderIdBytes);

/// Builds the GCD fallback URL used to re-query attribution when
/// AppsFlyer replies with `af_status == "Organic"` on the first callback.
///
/// Format:  {host}{path}{appId}?device_id={uid}
String resolveGcdUrl({required String appId, required String deviceId}) {
  final host = unscramble(_gcdHostBytes);
  if (host.isEmpty) return '';
  final path = unscramble(_gcdPathBytes);
  return '$host$path$appId?device_id=$deviceId';
}
