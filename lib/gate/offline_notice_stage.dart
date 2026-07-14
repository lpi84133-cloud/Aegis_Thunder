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
            // Centred so the button sits squarely under the sign's
            // text frame (the sign is horizontally centred in the art).
            alignment: const Alignment(0.0, 1.0),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 26),
              child: FractionallySizedBox(
                widthFactor: 0.72,
                child: _RetryButton(busy: busy, onTap: onRetry, height: 56),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

// ─── Landscape ───────────────────────────────────────────────────────────────
// Horizontal asset (updated). Sign is centred; button sits just below it.

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
      // No SafeArea here: an asymmetric camera cutout inset would
      // shift the usable width and push the button off the horizontal
      // centre. We use the full screen box and centre the button on it.
      //
      // Geometry measured from the source art (1584×672): the gilded sign
      // board spans ~39 % of the image width, centred, and its bottom edge
      // sits at ~82 % of the image height. With BoxFit.cover the sides are
      // cropped, widening the board to ≈42 % of the visible width while the
      // vertical position is preserved. We size the button to that width and
      // drop it just beneath the board so it lines up with the frame.
      Positioned.fill(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final btnWidth = w * 0.43; // matches the sign frame width
            final btnHeight = h * 0.135;
            final left = (w - btnWidth) / 2; // centred under the sign
            final bottom = h * 0.05; // sits low, right under the board
            return Stack(
              children: [
                Positioned(
                  left: left,
                  width: btnWidth,
                  bottom: bottom,
                  height: btnHeight,
                  child: _RetryButton(busy: busy, onTap: onRetry),
                ),
              ],
            );
          },
        ),
      ),
    ]);
  }
}

// ─── Shared button ───────────────────────────────────────────────────────────

class _RetryButton extends StatefulWidget {
  final bool busy;
  final VoidCallback onTap;

  /// Explicit height (portrait). Left null in landscape, where the
  /// parent Positioned already constrains the height.
  final double? height;

  const _RetryButton({required this.busy, required this.onTap, this.height});

  @override
  State<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<_RetryButton> {
  bool _pressed = false;

  // Palette pulled from the No-Wifi artwork: gold ornate frame around a
  // warm marble/ivory plate, with deep-bronze engraved lettering.
  static const _bronze = Color(0xFF4A3410); // dark frame / text
  static const _goldTop = Color(0xFFF7E4A6); // light gold highlight
  static const _goldMid = Color(0xFFE7C05A); // core gold
  static const _goldLow = Color(0xFFC48F2C); // deep gold shade

  @override
  Widget build(BuildContext context) {
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
        child: SizedBox(
          height: widget.height,
          // Outer ornate gold frame (matches the sign's gilded border).
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: widget.busy
                    ? const [Color(0xFF6E5A2E), Color(0xFF4A3410)]
                    : const [_goldTop, _goldMid, _goldLow],
                stops: widget.busy ? null : const [0.0, 0.55, 1.0],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _bronze, width: 2.2),
              boxShadow: widget.busy
                  ? null
                  : [
                      BoxShadow(
                        color: _goldMid.withValues(alpha: 0.5),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            padding: const EdgeInsets.all(3),
            // Inner hairline that reads as an engraved bevel.
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.busy
                      ? const Color(0x33F7E4A6)
                      : const Color(0x88FFF6D9),
                  width: 1.2,
                ),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: widget.busy ? _busyContent() : _idleContent(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _idleContent() {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.refresh_rounded, color: _bronze, size: 22),
        SizedBox(width: 10),
        Text(
          'TRY AGAIN',
          style: TextStyle(
            fontFamily: 'serif',
            color: _bronze,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }

  Widget _busyContent() {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF7E4A6)),
          ),
        ),
        SizedBox(width: 12),
        Text(
          'CONNECTING...',
          style: TextStyle(
            fontFamily: 'serif',
            color: Color(0xFFF7E4A6),
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.5,
          ),
        ),
      ],
    );
  }
}
