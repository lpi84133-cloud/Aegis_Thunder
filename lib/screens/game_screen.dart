import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../data/levels.dart';
import '../data/progress.dart';
import '../game/game_engine.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.levelIndex});

  final int levelIndex;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  GameEngine? _engine;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _paused = false;
  bool _resultShown = false;
  ui.Image? _boltImage;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _ticker.start();
    _loadBoltImage();
  }

  Future<void> _loadBoltImage() async {
    final data = await rootBundle.load('assets/lightbolt.webp');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() => _boltImage = frame.image);
  }

  void _onTick(Duration elapsed) {
    if (_engine == null) {
      _last = elapsed;
      return;
    }
    final dt = (elapsed - _last).inMicroseconds / 1000000.0;
    _last = elapsed;
    if (_paused || _engine!.status != GameStatus.playing) {
      _maybeShowResult();
      return;
    }
    _engine!.tick(dt.clamp(0.0, 0.033));
    _maybeShowResult();
  }

  void _maybeShowResult() {
    if (_engine == null || _resultShown) return;
    if (_engine!.status == GameStatus.won) {
      _resultShown = true;
      ProgressStore.setUnlocked(widget.levelIndex + 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showResultDialog(true);
      });
    } else if (_engine!.status == GameStatus.lost) {
      _resultShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showResultDialog(false);
      });
    }
  }

  Future<void> _showResultDialog(bool won) async {
    setState(() => _paused = true);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ResultDialog(
        won: won,
        levelIndex: widget.levelIndex,
        hasNext: won && widget.levelIndex + 1 < kLevels.length,
        onRetry: () {
          Navigator.of(ctx).pop();
          setState(() {
            _resultShown = false;
            _paused = false;
            _engine?.restart();
          });
        },
        onNext: () {
          Navigator.of(ctx).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => GameScreen(
                levelIndex: widget.levelIndex + 1,
              ),
            ),
          );
        },
        onExit: () {
          Navigator.of(ctx).pop();
          Navigator.of(context).pop();
        },
      ),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = kLevels[widget.levelIndex];
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (_engine == null) {
            _engine = GameEngine(level: level, size: size);
          } else {
            _engine!.updateSize(size);
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset('assets/bgZeus.webp', fit: BoxFit.cover),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Image.asset(
                  'assets/floor.webp',
                  fit: BoxFit.cover,
                  height: 90,
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: constraints.maxHeight * 0.14,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0.75,
                          child: Image.asset(
                            'assets/clouds.webp',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: FractionallySizedBox(
                          heightFactor: 1.35,
                          child: Image.asset(
                            'assets/zeus.webp',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Game field with gesture control.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    _engine?.moveShieldTo(details.localPosition.dx);
                    setState(() {});
                  },
                  onTapDown: (details) {
                    _engine?.moveShieldTo(details.localPosition.dx);
                    setState(() {});
                  },
                  child: AnimatedBuilder(
                    animation: _engine!,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _GamePainter(
                          engine: _engine!,
                          boltImage: _boltImage,
                        ),
                      );
                    },
                  ),
                ),
              ),
              _hud(context, level),
            ],
          );
        },
      ),
    );
  }

  Widget _hud(BuildContext context, LevelConfig level) {
    final engine = _engine!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          children: [
            Row(
              children: [
                _hudChip(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                _hudBadge(text: 'LVL ${level.index + 1}'),
                const Spacer(),
                _hudBadge(
                  text: '${engine.targetsRemaining}/${engine.totalTargets}',
                  icon: Icons.gps_fixed_rounded,
                ),
                const SizedBox(width: 8),
                _hudBadge(
                  text: '${engine.lives}',
                  icon: Icons.favorite_rounded,
                  color: const Color(0xFFEC5B5B),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _timerBar(engine.timeLeft, level.timeLimitSeconds),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hudChip({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.black.withOpacity(0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE8B94A), width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: const Color(0xFFF6D36B), size: 20),
        ),
      ),
    );
  }

  Widget _hudBadge({
    required String text,
    IconData? icon,
    Color color = const Color(0xFFF6D36B),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8B94A), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFFF6D36B),
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _timerBar(double timeLeft, int limit) {
    final value = (timeLeft / limit).clamp(0.0, 1.0);
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8B94A), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFFFE58A),
                  Color(0xFFE8B94A),
                  Color(0xFFB47912),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GamePainter extends CustomPainter {
  _GamePainter({required this.engine, required this.boltImage});

  final GameEngine engine;
  final ui.Image? boltImage;

  @override
  void paint(Canvas canvas, Size size) {
    _drawTargets(canvas);
    _drawBolts(canvas);
    _drawShield(canvas);
    _drawEffects(canvas);
  }

  void _drawTargets(Canvas canvas) {
    final paintRing = Paint()
      ..color = const Color(0xFFE8B94A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final paintFill = Paint()..color = const Color(0xFF3A2A0A);
    final paintCenter = Paint()..color = const Color(0xFFF6D36B);

    for (final t in engine.targets) {
      if (t.destroyed) continue;
      final c = Offset(t.x, t.y);
      // Halo
      final halo = Paint()
        ..color = const Color(0xFFE8B94A).withOpacity(0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(c, t.radius + 6, halo);
      canvas.drawCircle(c, t.radius, paintFill);
      canvas.drawCircle(c, t.radius, paintRing);
      canvas.drawCircle(c, t.radius * 0.55, paintCenter);
      canvas.drawCircle(
        c,
        t.radius * 0.28,
        Paint()..color = const Color(0xFF7A1D1D),
      );
    }
  }

  void _drawBolts(Canvas canvas) {
    for (final b in engine.bolts) {
      canvas.save();
      canvas.translate(b.x, b.y);
      final angle = atan2(b.vx, -b.vy);
      canvas.rotate(angle);
      _paintBolt(canvas);
      canvas.restore();
    }
  }

  void _paintBolt(Canvas canvas) {
    const w = GameEngine.boltWidth;
    const h = GameEngine.boltHeight;
    final dst = Rect.fromCenter(
      center: Offset.zero,
      width: w,
      height: h,
    );

    // Outer soft glow behind the sprite.
    final glowPaint = Paint()
      ..color = const Color(0xFFFFE58A).withOpacity(0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: w * 1.2, height: h * 1.05),
      glowPaint,
    );

    // Inner tight glow.
    final innerGlow = Paint()
      ..color = const Color(0xFFFFF7C2).withOpacity(0.85)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: w * 0.85, height: h * 0.9),
      innerGlow,
    );

    if (boltImage != null) {
      final img = boltImage!;
      final src = Rect.fromLTWH(
        0,
        0,
        img.width.toDouble(),
        img.height.toDouble(),
      );
      canvas.drawImageRect(img, src, dst, Paint()..isAntiAlias = true);
    } else {
      // Fallback path if the asset isn't decoded yet.
      final path = Path()
        ..moveTo(-w * 0.15, -h * 0.5)
        ..lineTo(w * 0.35, -h * 0.1)
        ..lineTo(w * 0.05, -h * 0.02)
        ..lineTo(w * 0.4, h * 0.5)
        ..lineTo(-w * 0.35, h * 0.05)
        ..lineTo(w * 0.05, -h * 0.02)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFF7C2),
              Color(0xFFFFD24C),
              Color(0xFFB47912),
            ],
          ).createShader(dst),
      );
    }
  }

  void _drawShield(Canvas canvas) {
    final rect = Rect.fromCenter(
      center: Offset(engine.shieldX, engine.shieldY),
      width: engine.shieldWidth,
      height: GameEngine.shieldHeight * 1.8,
    );

    // Glow
    final glow = Paint()
      ..color = const Color(0xFFE8B94A).withOpacity(0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawOval(rect.inflate(6), glow);

    // Shield body (gradient oval).
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFFFFE58A),
          Color(0xFFE8B94A),
          Color(0xFF8A5A0F),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect);
    canvas.drawOval(rect, bodyPaint);

    // Border.
    canvas.drawOval(
      rect,
      Paint()
        ..color = const Color(0xFF3A2A0A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Inner ring.
    canvas.drawOval(
      rect.deflate(8),
      Paint()
        ..color = const Color(0xFF3A2A0A).withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Medusa emblem: a dark circle in the center for visual identity.
    final center = rect.center;
    canvas.drawCircle(
      center,
      GameEngine.shieldHeight * 0.55,
      Paint()..color = const Color(0xFF5C3A0A),
    );
    canvas.drawCircle(
      center,
      GameEngine.shieldHeight * 0.55,
      Paint()
        ..color = const Color(0xFF1A1305)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Tiny highlight
    canvas.drawCircle(
      Offset(center.dx - 4, center.dy - 4),
      GameEngine.shieldHeight * 0.15,
      Paint()..color = const Color(0xFFFFF7C2).withOpacity(0.8),
    );
  }

  void _drawEffects(Canvas canvas) {
    for (final e in engine.effects) {
      final t = e.t.clamp(0.0, 1.0);
      final radius = 8 + 40 * t;
      final paint = Paint()
        ..color = const Color(0xFFFFE58A).withOpacity(1 - t)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * (1 - t) + 1
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(Offset(e.x, e.y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GamePainter oldDelegate) => true;
}

class _ResultDialog extends StatelessWidget {
  const _ResultDialog({
    required this.won,
    required this.levelIndex,
    required this.hasNext,
    required this.onRetry,
    required this.onNext,
    required this.onExit,
  });

  final bool won;
  final int levelIndex;
  final bool hasNext;
  final VoidCallback onRetry;
  final VoidCallback onNext;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF120C05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE8B94A), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              won
                  ? Icons.emoji_events_rounded
                  : Icons.sentiment_dissatisfied_rounded,
              color: const Color(0xFFF6D36B),
              size: 60,
            ),
            const SizedBox(height: 8),
            Text(
              won ? 'VICTORY!' : 'DEFEAT',
              style: const TextStyle(
                color: Color(0xFFF6D36B),
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Level ${levelIndex + 1}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            _dialogButton(
              label: won && hasNext ? 'NEXT LEVEL' : 'RETRY',
              onTap: won && hasNext ? onNext : onRetry,
            ),
            if (won && hasNext) ...[
              const SizedBox(height: 10),
              _dialogButton(label: 'REPLAY', onTap: onRetry, secondary: true),
            ],
            const SizedBox(height: 10),
            _dialogButton(
              label: 'MAIN MENU',
              onTap: onExit,
              secondary: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogButton({
    required String label,
    required VoidCallback onTap,
    bool secondary = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              gradient: secondary
                  ? const LinearGradient(
                      colors: [Color(0xFF2A2418), Color(0xFF1A1408)],
                    )
                  : const LinearGradient(
                      colors: [
                        Color(0xFFFFE58A),
                        Color(0xFFE8B94A),
                        Color(0xFFB47912),
                      ],
                    ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF3A2A0A),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: secondary
                      ? const Color(0xFFF6D36B)
                      : const Color(0xFF1A1305),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
