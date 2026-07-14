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
  // Time to wait for the AppsFlyer install-conversion callback on
  // first launch. MUST be generous: the SDK first runs its own GCD
  // lookup (~3-4 s), and on a (false) Organic reply we add our own
  // GCD re-check on top. If this cap is too small the gateway is
  // called with an EMPTY attribution set (af_status=null) and the
  // backend can only answer "organic → white". Value per
  // android_gray_guide.md §"Gray Flow State Machine" (30 s).
  static const Duration attributionMaxWait = Duration(seconds: 30);

  // Follow-up wait for the deep-link callback. Guide value: 5 s.
  static const Duration deepLinkMaxWait = Duration(seconds: 5);

  // Delay before retrying attribution via GCD when the SDK reports
  // "Organic" on the first callback (known false positive). Guide
  // value: 5 s (gives AppsFlyer time to propagate the attribution).
  static const Duration gcdRetryDelay = Duration(seconds: 5);

  // How long a single config POST is allowed to take.
  static const Duration gatewayCallTimeout = Duration(seconds: 15);

  // Push permission promo re-appears after this delay when the
  // user skipped it (3 days).
  static const int alertRepromptCooldownSec = 3 * 24 * 60 * 60;

  // ── Resolvers ─────────────────────────────────────────────
  static String get gatewayUrl => resolveGatewayUrl();
  static String get devKey => resolveDevKey();
  static String get senderId => resolveSenderId();
}
