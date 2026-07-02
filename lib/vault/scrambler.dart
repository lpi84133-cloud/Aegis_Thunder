import 'dart:typed_data';

// ─────────────────────────────────────────────────────────────
//  Aegis Thunder / Scrambler
//
//  Compact deobfuscator for sensitive strings baked into the
//  binary (config host, attribution key, Firebase sender id,
//  browser UA fragments).
//
//  The seed phrase drives an FNV-1a hash which then feeds an
//  xorshift64* generator; the first N bytes of the stream form
//  a mask that is XOR-ed against the encoded payload. Both the
//  hash and PRNG are intentionally different from any other
//  project in the fleet so the binary fingerprint does not
//  match sibling apps.
//
//  To rotate the key:
//    1. change [_seedPhrase] below,
//    2. re-run  `dart run tool/encode_keys.dart`,
//    3. paste the new byte lists into the env/ files.
// ─────────────────────────────────────────────────────────────

const String _seedPhrase = 'olympus_bolt_9';
const int _maskLength = 24;

Uint8List _buildMask() {
  // FNV-1a over the seed phrase (32-bit).
  const int fnvOffset = 0x811C9DC5;
  const int fnvPrime = 0x01000193;

  int h = fnvOffset;
  for (final unit in _seedPhrase.codeUnits) {
    h = (h ^ unit) & 0xFFFFFFFF;
    h = (h * fnvPrime) & 0xFFFFFFFF;
  }

  // xorshift64* is fed by two 32-bit halves derived from the hash,
  // rotated by the phrase length so equal-length seeds still diverge.
  final int rot = _seedPhrase.length & 0x1F;
  int lo = ((h << rot) | (h >> (32 - rot))) & 0xFFFFFFFF;
  int hi = ((h * 0x9E3779B1) & 0xFFFFFFFF) ^ 0xDEADBEEF;
  int state = (hi << 32) | lo;
  if (state == 0) state = 0xA5A5A5A5A5A5A5A5;

  final Uint8List mask = Uint8List(_maskLength);
  for (var i = 0; i < _maskLength; i++) {
    state ^= (state >> 12);
    state ^= (state << 25) & 0xFFFFFFFFFFFFFFFF;
    state ^= (state >> 27);
    final int mixed = (state * 0x2545F4914F6CDD1D) & 0xFFFFFFFFFFFFFFFF;
    mask[i] = ((mixed >> 33) & 0xFF);
  }
  return mask;
}

final Uint8List _mask = _buildMask();

/// Decodes an XOR-scrambled byte list into a plain string.
/// Passing an empty list returns an empty string (used as a null-guard
/// in the env/ files when a slot has not been filled in yet).
String unscramble(List<int> bytes) {
  if (bytes.isEmpty) return '';
  final out = Uint8List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    out[i] = (bytes[i] ^ _mask[i % _mask.length]) & 0xFF;
  }
  return String.fromCharCodes(out);
}

/// Symmetric helper — used only by `tool/encode_keys.dart`.
/// Not called from app code, so tree-shaking removes it in release builds.
List<int> scramble(String plain) {
  final Uint8List src = Uint8List.fromList(plain.codeUnits);
  final Uint8List out = Uint8List(src.length);
  for (var i = 0; i < src.length; i++) {
    out[i] = (src[i] ^ _mask[i % _mask.length]) & 0xFF;
  }
  return out;
}
