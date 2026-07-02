import '../vault/scrambler.dart';

// Config endpoint URL is stored scrambled to avoid a plaintext hit
// in `strings` / `apktool` scans of the released binary.
//
// The endpoint is split into (host, path) so the two halves live in
// different code sections. When both slots are empty (fresh checkout,
// no keys pasted yet), `resolveGatewayUrl()` returns an empty string
// and RemoteResponse.error is produced without a network call —
// callers must handle that gracefully.
//
// Regenerate the byte arrays via  `dart run tool/encode_keys.dart`
// after changing the scrambler seed.

// Encoded host + scheme  →  "https://aegisthunder.com"
const List<int> _hostBytes = <int>[
  209, 110, 86, 16, 66, 234, 145, 204, 136, 76, 160, 124, 54, 247, 207, 126,
  239, 255, 156, 56, 118, 200, 144, 163,
];

// Encoded path  →  "/config.php"
const List<int> _pathBytes = <int>[
  150, 121, 77, 14, 87, 185, 217, 205, 153, 65, 183,
];

String resolveGatewayUrl() {
  final host = unscramble(_hostBytes);
  if (host.isEmpty) return '';
  return host + unscramble(_pathBytes);
}
