// Persisted routing state.
//
//  * initial  — user has just installed; gray/white decision has not been made.
//  * portal   — the backend approved a WebView URL; every subsequent launch
//               shall try to reload the portal.
//  * arcade   — the backend declined (organic install / expired offer / no
//               endpoint configured). We fall back to the native game and
//               never poll the backend again for this install.

enum RunMode {
  initial,
  portal,
  arcade;

  static RunMode fromStorage(String? raw) {
    switch (raw) {
      case 'portal':
        return RunMode.portal;
      case 'arcade':
        return RunMode.arcade;
      default:
        return RunMode.initial;
    }
  }

  String get storageValue {
    switch (this) {
      case RunMode.portal:
        return 'portal';
      case RunMode.arcade:
        return 'arcade';
      case RunMode.initial:
        return 'initial';
    }
  }
}
