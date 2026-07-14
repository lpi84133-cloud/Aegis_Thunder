import 'package:clarity_flutter/clarity_flutter.dart';
import '../env/insight_env.dart';

/// Crash-safe facade over Microsoft Clarity. Session replay captures the
/// native Flutter surface; these calls add funnel signals to answer
/// "where did the user drop off?". A Clarity failure must never crash the
/// gray flow — every public method is wrapped in [_guard].
class Insight {
  const Insight._();

  static ClarityConfig get config => ClarityConfig(
        projectId: kClarityProjectId,
        logLevel: LogLevel.None,
      );

  /// Group this session by AppsFlyer id and attach attribution tags.
  /// No-op when [aid] is null/empty so a missing af_id never overwrites
  /// a good user id from a previous call.
  static void identify(String? aid, {Map<String, String> tags = const {}}) {
    if (aid != null && aid.isNotEmpty) {
      _guard(() => Clarity.setCustomUserId(_clip(aid, 255)));
      tag('aid', aid);
    }
    tags.forEach(tag);
  }

  /// Sets the screen label, persists it as [last_screen] tag (Clarity keeps
  /// the LAST value, so filtering by last_screen shows the drop-off screen)
  /// and emits a per-screen event.
  static void screen(String name) {
    screenName(name);
    event('screen_$name');
  }

  /// Like [screen] but skips the per-screen event — use when only updating
  /// the label without creating a funnel step (e.g. WebView page navigation).
  static void screenName(String name) => _guard(() {
        Clarity.setCurrentScreenName(_clip(name, 255));
        Clarity.setCustomTag('last_screen', _clip(name, 255));
      });

  static void event(String name) =>
      _guard(() => Clarity.sendCustomEvent(_clip(name, 254)));

  static void tag(String key, String value) {
    if (value.isEmpty) return;
    _guard(() => Clarity.setCustomTag(key, _clip(value, 255)));
  }

  static String _clip(String v, int max) =>
      v.length <= max ? v : v.substring(0, max);

  static void _guard(void Function() body) {
    try {
      body();
    } catch (_) {}
  }
}
