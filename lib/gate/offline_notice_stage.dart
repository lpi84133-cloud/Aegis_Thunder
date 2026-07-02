import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OfflineNoticeStage extends StatefulWidget {
  final WidgetBuilder onRetry;

  const OfflineNoticeStage({super.key, required this.onRetry});

  @override
  State<OfflineNoticeStage> createState() => _OfflineNoticeStageState();
}

class _OfflineNoticeStageState extends State<OfflineNoticeStage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Unlock both orientations so OrientationBuilder can switch assets.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: widget.onRetry),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      body: OrientationBuilder(builder: (context, orient) {
        final horiz = orient == Orientation.landscape;

        // Portrait: vertical asset fills screen, button overlays bottom.
        // Landscape: horizontal asset fills screen, button overlays bottom.
        if (!horiz) {
          return _PortraitLayout(busy: _busy, onRetry: _retry);
        } else {
          return _LandscapeLayout(busy: _busy, onRetry: _retry);
        }
      }),
    );
  }
}

// ─── Portrait ────────────────────────────────────────────────────────────────
// Vertical asset: 769×1377. With BoxFit.cover on a typical portrait screen
// (~392×852) the image is scaled by height (0.619×). The sign in the
// image occupies ≈70 % of image width → ~72 % of the visible screen width.
// We match the button to that fraction for a flush fit.

class _PortraitLayout extends StatelessWidget {
  final bool busy;
  final VoidCallback onRetry;

  const _PortraitLayout({required this.busy, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      Image.asset(
        'assets/Vertical_Nowifi_Screen.webp',
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
      Positioned(
        left: 0, right: 0, bottom: 0,
        height: 160,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0xBB000000)],
            ),
          ),
        ),
      ),
      // Full SafeArea (top + bottom + sides) so the button never
      // hides behind notch, status bar, or gesture nav on any device.
      Positioned.fill(
        child: SafeArea(
          child: Align(
            alignment: const Alignment(0.06, 1.0),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: FractionallySizedBox(
                widthFactor: 0.78,
                child: _RetryButton(busy: busy, onTap: onRetry),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

// ─── Landscape ───────────────────────────────────────────────────────────────
// Horizontal asset: 1585×673. With BoxFit.cover on a typical landscape screen
// (~900×400) the image is scaled by height (0.594×). The sign in the image
// spans ≈38 % of image width → ~38 % of visible screen width.

class _LandscapeLayout extends StatelessWidget {
  final bool busy;
  final VoidCallback onRetry;

  const _LandscapeLayout({required this.busy, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      Image.asset(
        'assets/Horizontal_Nowifi_Screen.webp',
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
      Positioned(
        left: 0, right: 0, bottom: 0,
        height: 100,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x99000000)],
            ),
          ),
        ),
      ),
      // Full SafeArea — in landscape the camera cutout is often on
      // the left edge; SafeArea.left ensures buttons stay visible.
      Positioned.fill(
        child: SafeArea(
          child: Align(
            alignment: const Alignment(0.03, 1.0),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: FractionallySizedBox(
                widthFactor: 0.34,
                child: _RetryButton(busy: busy, onTap: onRetry),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

// ─── Shared button ───────────────────────────────────────────────────────────

class _RetryButton extends StatefulWidget {
  final bool busy;
  final VoidCallback onTap;

  const _RetryButton({required this.busy, required this.onTap});

  @override
  State<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<_RetryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFE8B94A);
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (!widget.busy) widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: widget.busy ? const Color(0xFF3A2A0A) : gold,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.busy
                  ? const Color(0xFF6A5015)
                  : const Color(0xFF2A1B03),
              width: 1.8,
            ),
            boxShadow: widget.busy
                ? null
                : [
                    BoxShadow(
                      color: gold.withValues(alpha: 0.45),
                      blurRadius: 14,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Center(
            child: widget.busy
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFFE8B94A)),
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'CONNECTING...',
                        style: TextStyle(
                          color: Color(0xFFE8B94A),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded,
                          color: Color(0xFF1A1100), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'TRY AGAIN',
                        style: TextStyle(
                          color: Color(0xFF1A1100),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
