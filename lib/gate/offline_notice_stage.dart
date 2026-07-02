import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OfflineNoticeStage extends StatefulWidget {
  final WidgetBuilder onRetry;

  const OfflineNoticeStage({super.key, required this.onRetry});

  @override
  State<OfflineNoticeStage> createState() => _OfflineNoticeStageState();
}

class _OfflineNoticeStageState extends State<OfflineNoticeStage>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _flicker;

  @override
  void initState() {
    super.initState();
    // Explicitly unlock both orientations so the landscape asset shows
    // when the user rotates the device.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _flicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
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

        final hPad = horiz ? 120.0 : 36.0;
        final vPad = horiz ? 18.0 : 44.0;
        final btnW = horiz ? 280.0 : double.infinity;

        return Stack(fit: StackFit.expand, children: [
          Image.asset(art, fit: BoxFit.cover, gaplessPlayback: true),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            left: hPad,
            right: hPad,
            bottom: vPad,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _flickeringTitle(horiz),
                  SizedBox(height: horiz ? 14 : 20),
                  SizedBox(
                    width: btnW,
                    child: _RetryButton(busy: _busy, onTap: _retry),
                  ),
                ],
              ),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _flickeringTitle(bool horiz) {
    return AnimatedBuilder(
      animation: _flicker,
      builder: (_, __) => Opacity(
        opacity: 0.7 + 0.3 * _flicker.value,
        child: Text(
          'Storm has cut the wires',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color(0xFFFFE58A),
            fontSize: horiz ? 18 : 21,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
          ),
        ),
      ),
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
            color: widget.busy
                ? const Color(0xFF3A2A0A)
                : gold,
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
