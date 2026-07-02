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
// Full-screen vertical image. Button sits at the very bottom, overlaying
// the golden coins at the base — the sign is never obscured.

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
      // Gradient only at the very bottom so the button text stays readable.
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
      Positioned(
        left: 40,
        right: 40,
        bottom: 40,
        child: SafeArea(
          top: false,
          child: _RetryButton(busy: busy, onTap: onRetry),
        ),
      ),
    ]);
  }
}

// ─── Landscape ───────────────────────────────────────────────────────────────
// Horizontal image. The sign occupies the centre-left area of the asset;
// we place the button at the far right bottom so it never overlaps the sign.

class _LandscapeLayout extends StatelessWidget {
  final bool busy;
  final VoidCallback onRetry;

  const _LandscapeLayout({required this.busy, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width;

    return Stack(fit: StackFit.expand, children: [
      Image.asset(
        'assets/Horizontal_Nowifi_Screen.webp',
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
      // Gradient at the right edge + bottom so button is readable.
      Positioned(
        right: 0,
        top: 0,
        bottom: 0,
        width: w * 0.45,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0x00000000), Color(0xAA000000)],
            ),
          ),
        ),
      ),
      // Button anchored to the bottom-right quadrant.
      Positioned(
        right: 36,
        bottom: 24,
        width: w * 0.38,
        child: SafeArea(
          top: false,
          child: _RetryButton(busy: busy, onTap: onRetry),
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
