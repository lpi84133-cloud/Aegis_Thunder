import 'dart:math';

import 'package:flutter/widgets.dart';

import '../data/levels.dart';

enum GameStatus { playing, won, lost }

class Bolt {
  Bolt({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    this.deflected = false,
  });

  double x;
  double y;
  double vx;
  double vy;
  bool deflected;
}

class Target {
  Target({required this.x, required this.y, required this.radius});
  double x;
  double y;
  double radius;
  bool destroyed = false;
}

class HitEffect {
  HitEffect({required this.x, required this.y});
  final double x;
  final double y;
  double t = 0; // 0..1 lifetime
}

class GameEngine extends ChangeNotifier {
  GameEngine({required this.level, required this.size}) {
    _init();
  }

  final LevelConfig level;
  Size size;

  static const double boltWidth = 46;
  static const double boltHeight = 96;
  static const double shieldHeight = 42;
  static const double targetRadius = 26;

  // State
  double shieldX = 0; // center x of the shield
  double shieldY = 0;
  double shieldWidth = 180;

  final List<Bolt> bolts = [];
  final List<Target> targets = [];
  final List<HitEffect> effects = [];

  int lives = 3;
  int score = 0;
  double timeLeft = 0;
  GameStatus status = GameStatus.playing;

  double _throwTimer = 0;
  final Random _rand = Random();

  double _elapsed = 0;
  double get elapsed => _elapsed;

  int get targetsRemaining =>
      targets.where((t) => !t.destroyed).length;

  int get totalTargets => targets.length;

  void _init() {
    final w = size.width;
    final h = size.height;
    shieldWidth = level.shieldWidth * (w / 400).clamp(0.75, 1.4);
    shieldX = w / 2;
    shieldY = h - 90;
    lives = level.lives;
    timeLeft = level.timeLimitSeconds.toDouble();
    _spawnTargets();
  }

  void updateSize(Size newSize) {
    if (newSize == size) return;
    final ratioX = newSize.width / size.width;
    final ratioY = newSize.height / size.height;
    for (final t in targets) {
      t.x *= ratioX;
      t.y *= ratioY;
    }
    for (final b in bolts) {
      b.x *= ratioX;
      b.y *= ratioY;
    }
    shieldX *= ratioX;
    shieldY = newSize.height - 90;
    size = newSize;
  }

  void _spawnTargets() {
    targets.clear();
    final w = size.width;
    final rows = level.targetRows;
    final total = level.targetCount;
    final perRow = (total / rows).ceil();
    final topPadding = size.height * 0.18;
    final rowSpacing = 62.0;
    final margin = 40.0;
    for (int r = 0; r < rows; r++) {
      final countInRow = (r == rows - 1)
          ? (total - (rows - 1) * perRow)
          : perRow;
      if (countInRow <= 0) continue;
      final usableWidth = w - margin * 2;
      final step = countInRow == 1
          ? 0.0
          : usableWidth / (countInRow - 1);
      for (int c = 0; c < countInRow; c++) {
        final x = countInRow == 1
            ? w / 2
            : margin + step * c;
        final y = topPadding + r * rowSpacing;
        targets.add(Target(x: x, y: y, radius: targetRadius));
      }
    }
  }

  void moveShieldTo(double x) {
    final half = shieldWidth / 2;
    shieldX = x.clamp(half, size.width - half);
  }

  void tick(double dt) {
    if (status != GameStatus.playing) return;
    _elapsed += dt;
    timeLeft -= dt;
    if (timeLeft <= 0) {
      timeLeft = 0;
      _fail();
      return;
    }

    // Zeus throws bolts periodically.
    _throwTimer += dt * 1000;
    if (_throwTimer >= level.zeusThrowIntervalMs &&
        _activeFallingBolts() < level.maxBolts) {
      _throwTimer = 0;
      _spawnBolt();
    }

    // Update bolts.
    for (final b in bolts) {
      b.x += b.vx * dt;
      b.y += b.vy * dt;
    }

    // Collisions & cleanup.
    _handleCollisions();

    // Update effects.
    for (final e in effects) {
      e.t += dt / 0.35;
    }
    effects.removeWhere((e) => e.t >= 1);

    // Win condition.
    if (targets.every((t) => t.destroyed)) {
      status = GameStatus.won;
    }
    notifyListeners();
  }

  int _activeFallingBolts() =>
      bolts.where((b) => !b.deflected).length;

  void _spawnBolt() {
    final w = size.width;
    final margin = 40.0;
    final x = margin + _rand.nextDouble() * (w - margin * 2);
    final speed = level.boltSpeed;
    // Slight horizontal variation for later levels.
    final sway = (_rand.nextDouble() - 0.5) * 30 * (level.index / 20);
    bolts.add(Bolt(x: x, y: -boltHeight, vx: sway, vy: speed));
  }

  void _handleCollisions() {
    final removeList = <Bolt>[];
    for (final b in bolts) {
      // Out of bounds cleanup.
      if (b.y > size.height + 100 ||
          b.y < -200 ||
          b.x < -100 ||
          b.x > size.width + 100) {
        if (!b.deflected && b.y > size.height + 20) {
          // Missed bolt hit the floor.
          _loseLife();
        }
        removeList.add(b);
        continue;
      }

      if (!b.deflected) {
        // Check collision with shield.
        final withinX = (b.x - shieldX).abs() <= shieldWidth / 2;
        final withinY = (b.y + boltHeight / 2) >= shieldY - shieldHeight / 2 &&
            (b.y - boltHeight / 2) <= shieldY + shieldHeight / 2;
        if (withinX && withinY) {
          // Deflect the bolt back up with an angle depending on where it hit
          // the shield (breakout-style).
          final relative =
              ((b.x - shieldX) / (shieldWidth / 2)).clamp(-1.0, 1.0);
          final angleDeg = relative * 60; // -60..60 degrees from vertical
          final angleRad = angleDeg * pi / 180;
          final speed = sqrt(b.vx * b.vx + b.vy * b.vy) * 1.1;
          b.vx = sin(angleRad) * speed;
          b.vy = -cos(angleRad) * speed;
          b.deflected = true;
          b.y = shieldY - shieldHeight / 2 - boltHeight / 2 - 2;
          effects.add(HitEffect(x: b.x, y: shieldY - shieldHeight));
          continue;
        }
      } else {
        // Bounce off left/right walls.
        if (b.x < 20) {
          b.x = 20;
          b.vx = b.vx.abs();
        } else if (b.x > size.width - 20) {
          b.x = size.width - 20;
          b.vx = -b.vx.abs();
        }
        // Check collision with any target.
        for (final t in targets) {
          if (t.destroyed) continue;
          final dx = b.x - t.x;
          final dy = b.y - t.y;
          final dist = sqrt(dx * dx + dy * dy);
          if (dist <= t.radius + boltWidth / 2) {
            t.destroyed = true;
            score += 100;
            effects.add(HitEffect(x: t.x, y: t.y));
            removeList.add(b);
            break;
          }
        }
      }
    }
    for (final b in removeList) {
      bolts.remove(b);
    }
  }

  void _loseLife() {
    lives -= 1;
    if (lives <= 0) {
      lives = 0;
      _fail();
    }
  }

  void _fail() {
    status = GameStatus.lost;
  }

  void restart() {
    bolts.clear();
    effects.clear();
    _throwTimer = 0;
    _elapsed = 0;
    _init();
    status = GameStatus.playing;
    notifyListeners();
  }
}
