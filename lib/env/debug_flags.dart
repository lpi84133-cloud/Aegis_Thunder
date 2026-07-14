import 'dart:developer' as developer;

// Gray-flow diagnostics.
//
// When [kGrayFlowDebug] is true, the attribution → gateway → routing
// pipeline emits tagged log lines that are visible in `adb logcat`
// EVEN IN RELEASE builds (unlike kDebugMode-gated debugPrint, which is
// silenced in release). Filter them with:
//
//   adb logcat -s ATGRAY
//
// IMPORTANT: set this to `false` before shipping a production build —
// leaving it on prints attribution payloads to the device log.
const bool kGrayFlowDebug = true;

const String _tag = 'ATGRAY';

void grayLog(String message) {
  if (!kGrayFlowDebug) return;
  // developer.log routes to logcat under the given name; the explicit
  // print fallback guarantees visibility across all Flutter versions.
  developer.log(message, name: _tag);
  // ignore: avoid_print
  print('[$_tag] $message');
}
