import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'local_vault.dart';
import 'user_agent_client.dart';

// Top-level background handler required by firebase_messaging when the
// process is not alive. Kept intentionally empty — the OS renders the
// system notification on its own; we only need code to run when the
// user taps it and the app resumes (handled by onMessageOpenedApp).
@pragma('vm:entry-point')
Future<void> _onSilentBackground(RemoteMessage _) async {}

class AlertRelay {
  static const String _channelId = 'olympus_alerts_channel';
  static const String _channelName = 'Olympus Alerts';
  static const String _channelDescription =
      'High-priority notifications about your Aegis Thunder journey';
  static const String _iconResource = '@drawable/ic_notification';

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final LocalVault _vault;

  FirebaseMessaging? _fcm;
  String? _token;
  bool _ready = false;

  /// Fired when the user taps a push while the app is warm (background
  /// resume or foreground local-notification tap). ContentScreen listens
  /// for this and hot-loads the URL into the WebView.
  void Function(String url)? onUrl;

  /// Fired when FCM rotates the device token. Splash re-submits to the
  /// gateway with the fresh value so the backend can push future
  /// notifications to the correct device.
  void Function(String token)? onTokenRotated;

  AlertRelay(this._vault);

  String? get token => _token;

  Future<void> bootstrap() async {
    // One-time wiring of Firebase + listeners. Token acquisition is
    // handled separately by ensureToken() so it can be retried later:
    // on the very first (possibly offline) launch getToken() may fail,
    // and we must be able to fetch it once the network comes back
    // (e.g. after the No-Wifi → Retry flow) within the SAME session.
    if (!_ready) {
      try {
        await Firebase.initializeApp();
        _fcm = FirebaseMessaging.instance;

        FirebaseMessaging.onBackgroundMessage(_onSilentBackground);
        await _installLocalPlugin();

        _fcm!.onTokenRefresh.listen((newToken) {
          _token = newToken;
          onTokenRotated?.call(newToken);
        });

        FirebaseMessaging.onMessage.listen(_onForeground);
        FirebaseMessaging.onMessageOpenedApp.listen(_onResumeFromBackground);

        final cold = await _fcm!.getInitialMessage();
        if (cold != null) {
          _onColdBoot(cold);
        }
        _ready = true;
      } catch (_) {
        // Firebase not configured yet (missing google-services.json).
        // Push simply won't work — game / WebView continue as usual.
        return;
      }
    }

    await ensureToken();
  }

  /// Fetches the FCM token if we don't have one yet. Safe to call
  /// repeatedly — it becomes a no-op once a token has been obtained.
  /// Returns the token (or null if it still couldn't be fetched, e.g.
  /// no network / Firebase unavailable).
  Future<String?> ensureToken() async {
    if (_token != null && _token!.isNotEmpty) return _token;
    if (_fcm == null) return null;
    // A few bounded attempts: right after the network returns (No-Wifi
    // → Retry) FCM registration can lag by a second or two before it
    // can hand out a token. Kept short so boot stays well under 10 s.
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final fresh = await _fcm!.getToken();
        if (fresh != null && fresh.isNotEmpty) {
          _token = fresh;
          return _token;
        }
      } catch (_) {
        // Offline or transient failure — leave _token null so a later
        // ensureToken()/onTokenRefresh can still populate it.
      }
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
    return _token;
  }

  Future<void> _installLocalPlugin() async {
    const android = AndroidInitializationSettings(_iconResource);
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        final raw = response.payload;
        if (raw == null || raw.isEmpty) return;
        try {
          final data = jsonDecode(raw);
          if (data is Map) {
            final url = data['url'];
            if (url is String && url.isNotEmpty) onUrl?.call(url);
          }
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final plugin = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await plugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
        ),
      );
    }
  }

  /// Present the system permission prompt. On API < 33 permission is
  /// implicit and returns immediately as granted.
  Future<bool> askPermission() async {
    if (_fcm == null) return false;
    final result = await _fcm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final status = result.authorizationStatus;
    final granted = status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
    await _vault.markAlertGranted(granted);
    if (status == AuthorizationStatus.denied) {
      // OS remembers this; we can't ask again — flag it so the promo
      // screen won't reappear after the snooze timer runs out.
      await _vault.markAlertOsDenied();
    }
    return granted;
  }

  Future<void> _onForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    if (!Platform.isAndroid) return; // iOS handles banners itself

    Uint8List? picture;
    final imageUrl = notification.android?.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      picture = await _fetchBytes(imageUrl);
    }

    AndroidNotificationDetails details;
    if (picture != null) {
      details = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        icon: _iconResource,
        styleInformation: BigPictureStyleInformation(
          ByteArrayAndroidBitmap(picture),
          largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        ),
      );
    } else {
      details = const AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        icon: _iconResource,
      );
    }

    final payload = message.data.isNotEmpty ? jsonEncode(message.data) : null;
    await _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(android: details),
      payload: payload,
    );
  }

  void _onResumeFromBackground(RemoteMessage message) {
    final url = message.data['url'];
    if (url is String && url.isNotEmpty) onUrl?.call(url);
  }

  void _onColdBoot(RemoteMessage message) {
    final url = message.data['url'];
    if (url is String && url.isNotEmpty) {
      _vault.writePushUrl(url);
    }
  }

  Future<Uint8List?> _fetchBytes(String url) async {
    try {
      final response = await uaClient
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }
}
