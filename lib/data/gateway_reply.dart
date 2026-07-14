// Reply envelope returned by the config endpoint.
// The backend responds either:
//   { "ok": true,  "url": "...", "expires": 1735689600 }
//   { "ok": false, "message": "organic"                 }

class GatewayReply {
  final bool approved;
  final String? destination;
  final String? explanation;
  final int? expiresAt;

  /// True when the backend actually answered (HTTP 200 + valid JSON),
  /// regardless of approve/decline. False for transient client-side
  /// failures: timeout, network error, HTTP != 200, bad payload, or a
  /// missing endpoint. Callers must NOT permanently persist an
  /// "arcade" decision when this is false — the call should be retried
  /// on the next launch instead of locking the install to white.
  final bool responded;

  const GatewayReply({
    required this.approved,
    this.destination,
    this.explanation,
    this.expiresAt,
    this.responded = false,
  });

  factory GatewayReply.fromMap(Map<String, dynamic> map) {
    return GatewayReply(
      approved: map['ok'] as bool? ?? false,
      destination: map['url'] as String?,
      explanation: map['message'] as String?,
      expiresAt: map['expires'] as int?,
      responded: true,
    );
  }

  factory GatewayReply.failure(String reason) =>
      GatewayReply(approved: false, explanation: reason, responded: false);
}
