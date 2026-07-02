import 'attribution_env.dart';
import 'gateway_env.dart';

// Single facade over every environment-derived value that the
// runtime cares about. Keeping the const identity constants here
// avoids scattering the bundle id across many files.

class ShellSettings {
  const ShellSettings._();

  static const String bundleId = 'com.aegisthund.aegisthunder';
  static const String storeId = 'com.aegisthund.aegisthunder';
  static const String displayName = 'Aegis Thunder';

  // Empty on Android; only populated for iOS App Store numeric ids.
  static const String appStoreId = '';

  // ── Timing knobs ─────────────────────────────────────────
  // Time to wait for the AppsFlyer install-conversion callback
  // on first launch. If it doesn't arrive, we go ahead with an
  // empty attribution set.
  static const Duration attributionMaxWait = Duration(seconds: 7);

  // Follow-up wait for the deep-link callback (much shorter —
  // the SDK either has a link ready almost instantly or not at all).
  static const Duration deepLinkMaxWait = Duration(seconds: 2);

  // Delay before retrying attribution via GCD when the SDK
  // reports "Organic" on the first callback (known false positive).
  static const Duration gcdRetryDelay = Duration(seconds: 2);

  // How long the config POST is allowed to take.
  static const Duration gatewayCallTimeout = Duration(seconds: 7);

  // Push permission promo re-appears after this delay when the
  // user skipped it (3 days).
  static const int alertRepromptCooldownSec = 3 * 24 * 60 * 60;

  // ── Resolvers ─────────────────────────────────────────────
  static String get gatewayUrl => resolveGatewayUrl();
  static String get devKey => resolveDevKey();
  static String get senderId => resolveSenderId();
}
