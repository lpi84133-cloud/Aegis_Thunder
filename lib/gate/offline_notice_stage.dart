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
    // Ensure both orientations are allowed so the landscape asset
    // activates when the user rotates the device.
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
        final art = horiz
            ? 'assets/Horizontal_Nowifi_Screen.webp'
            : 'assets/Vertical_Nowifi_Screen.webp';

        // How much space to reserve at the bottom for the button.
        final buttonZone = horiz ? 80.0 : 110.0;
        final hPad = horiz ? 140.0 : 48.0;
        final vPad = horiz ? 12.0 : 28.0;

        return Stack(fit: StackFit.expand, children: [
          // Image fills the screen minus the bottom button zone —
          // this shifts the sign "up" so the button never overlaps it.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: buttonZone,
            child: Image.asset(art, fit: BoxFit.cover, gaplessPlayback: true),
          ),

          // Dark area below the image where the button lives.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: buttonZone + 20,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xCC000000)],
                ),
              ),
            ),
          ),

          // Centered button at the bottom.
          Positioned(
            left: hPad,
            right: hPad,
            bottom: vPad,
            child: SafeArea(
              top: false,
              child: Center(
                child: _RetryButton(busy: _busy, onTap: _retry),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}

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
                      color: gold.withValues(alpha: 0.4),
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
