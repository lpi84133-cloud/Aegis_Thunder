// Reply envelope returned by the config endpoint.
// The backend responds either:
//   { "ok": true,  "url": "...", "expires": 1735689600 }
//   { "ok": false, "message": "organic"                 }

class GatewayReply {
  final bool approved;
  final String? destination;
  final String? explanation;
  final int? expiresAt;

  const GatewayReply({
    required this.approved,
    this.destination,
    this.explanation,
    this.expiresAt,
  });

  factory GatewayReply.fromMap(Map<String, dynamic> map) {
    return GatewayReply(
      approved: map['ok'] as bool? ?? false,
      destination: map['url'] as String?,
      explanation: map['message'] as String?,
      expiresAt: map['expires'] as int?,
    );
  }

  factory GatewayReply.failure(String reason) =>
      GatewayReply(approved: false, explanation: reason);
}
