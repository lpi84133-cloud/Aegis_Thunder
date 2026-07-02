import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/run_mode.dart';
import '../env/shell_settings.dart';

// LocalVault wraps SharedPreferences (fast, plaintext) and
// FlutterSecureStorage (KeyStore-backed) into a single API.
//
// URLs and one-shot push payloads live in the secure half.
// Booleans / counters / timestamps live in the fast half.

class LocalVault {
  static const _kMode = 'atv_mode';
  static const _kOfferUrl = 'atv_offer';
  static const _kOfferExpiry = 'atv_offer_ttl';
  static const _kPushOnce = 'atv_push_once';
  static const _kAlertSnooze = 'atv_alert_snooze';
  static const _kAlertGranted = 'atv_alert_granted';
  static const _kAlertOsDenied = 'atv_alert_os_denied';

  final FlutterSecureStorage _safe = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  late SharedPreferences _fast;

  Future<void> init() async {
    _fast = await SharedPreferences.getInstance();
  }

  // ─── Run mode ──────────────────────────────────────
  RunMode readMode() => RunMode.fromStorage(_fast.getString(_kMode));
  Future<void> writeMode(RunMode m) => _fast.setString(_kMode, m.storageValue);

  // ─── Offer URL (secure) ────────────────────────────
  Future<String?> readOfferUrl() => _safe.read(key: _kOfferUrl);
  Future<void> writeOfferUrl(String url) =>
      _safe.write(key: _kOfferUrl, value: url);

  int? readOfferExpiry() => _fast.getInt(_kOfferExpiry);
  Future<void> writeOfferExpiry(int seconds) =>
      _fast.setInt(_kOfferExpiry, seconds);

  bool isOfferExpired() {
    final ts = readOfferExpiry();
    if (ts == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= ts;
  }

  // ─── One-shot push URL (secure) ────────────────────
  Future<String?> peekPushUrl() => _safe.read(key: _kPushOnce);
  Future<void> writePushUrl(String? url) async {
    if (url == null) {
      await _safe.delete(key: _kPushOnce);
    } else {
      await _safe.write(key: _kPushOnce, value: url);
    }
  }

  /// Consume-and-clear helper — returns the saved URL exactly once.
  Future<String?> takePushUrl() async {
    final v = await peekPushUrl();
    if (v != null) await _safe.delete(key: _kPushOnce);
    return v;
  }

  // ─── Notification permission state ─────────────────
  bool isAlertGranted() => _fast.getBool(_kAlertGranted) ?? false;
  Future<void> markAlertGranted(bool granted) =>
      _fast.setBool(_kAlertGranted, granted);

  bool isAlertOsDenied() => _fast.getBool(_kAlertOsDenied) ?? false;
  Future<void> markAlertOsDenied() => _fast.setBool(_kAlertOsDenied, true);

  int? readAlertSnooze() => _fast.getInt(_kAlertSnooze);
  Future<void> writeAlertSnooze(int seconds) =>
      _fast.setInt(_kAlertSnooze, seconds);

  Future<void> snoozeAlertForDefaultCooldown() {
    final until = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        ShellSettings.alertRepromptCooldownSec;
    return writeAlertSnooze(until);
  }

  /// True when the notification promo screen should still be presented.
  ///
  /// The OS-denied flag has priority over the snooze timer — once the
  /// system dialog was refused, Android will not allow us to ask again,
  /// so re-showing the promo would just annoy the user with a dead button.
  bool shouldPromptForAlerts() {
    if (isAlertGranted()) return false;
    if (isAlertOsDenied()) return false;
    final snoozeUntil = readAlertSnooze();
    if (snoozeUntil == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= snoozeUntil;
  }
}
