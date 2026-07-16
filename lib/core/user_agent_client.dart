import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../env/shell_settings.dart';
import '../vault/scrambler.dart';

// UserAgentClient wraps http.Client and rewrites every outgoing
// request with a Chrome-on-Android UA that carries the real device
// model + OS version. The tail also carries the app identity, per the
// integration TZ:
//
//   ... Mobile Safari/537.36 appid/com.aegisthund.aegisthunder appname/AegisThunder
//
// This UA is also handed to WebViewController so both surfaces look
// identical to the backend fingerprinting logic.

// Scrambled Chrome version fragment  →  "149.0.7827.163"
const List<int> _chromeVersionBytes = <int>[
  136, 46, 27, 78, 1, 254, 137, 219, 219, 30, 233, 36, 115, 176,
];

// Scrambled WebKit version fragment  →  "605.1.15"
const List<int> _webkitVersionBytes = <int>[
  143, 42, 23, 78, 0, 254, 143, 214,
];

class UserAgentClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  String _ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/149.0.7827.163 Mobile Safari/537.36';

  String get userAgent => _ua;

  Future<void> prepare() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        final chrome = _chromeVersion();
        final build = android.display.isNotEmpty
            ? android.display
            : (android.id.isNotEmpty ? android.id : 'AP3A.240905.015.A2');
        // android.version.release is the human-readable OS version
        // (e.g. "16"). android.version.sdkInt is the API level
        // (e.g. 36) and must never appear in the "Android X" slot.
        final osVersion = android.version.release.isNotEmpty
            ? android.version.release
            : android.version.sdkInt.toString();
        _ua = _decorate(
          'Mozilla/5.0 (Linux; Android $osVersion; '
          '${android.brand} ${android.model} Build/$build) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/$chrome Mobile Safari/537.36',
        );
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        final v = ios.systemVersion.replaceAll('.', '_');
        final webkit = _webkitVersion();
        _ua = _decorate(
          'Mozilla/5.0 (iPhone; CPU iPhone OS $v like Mac OS X) '
          'AppleWebKit/$webkit (KHTML, like Gecko) '
          'Version/${ios.systemVersion} Mobile/15E148 Safari/$webkit',
        );
      }
    } catch (_) {
      _ua = _decorate(_ua);
    }
  }

  String _decorate(String base) =>
      '$base appid/${ShellSettings.bundleId} '
      'appname/${ShellSettings.displayName.replaceAll(' ', '')}';

  String _chromeVersion() {
    final v = unscramble(_chromeVersionBytes);
    return v.isNotEmpty ? v : '149.0.7827.163';
  }

  String _webkitVersion() {
    final v = unscramble(_webkitVersionBytes);
    return v.isNotEmpty ? v : '605.1.15';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => _ua);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

// Single instance shared by every service that speaks HTTP.
final UserAgentClient uaClient = UserAgentClient();
