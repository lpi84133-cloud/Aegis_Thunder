import 'dart:math';

class LevelConfig {
  const LevelConfig({
    required this.index,
    required this.targetCount,
    required this.targetRows,
    required this.boltSpeed,
    required this.zeusThrowIntervalMs,
    required this.maxBolts,
    required this.lives,
    required this.shieldWidth,
    required this.timeLimitSeconds,
  });

  final int index;
  final int targetCount;
  final int targetRows;
  final double boltSpeed; // pixels per second (base, normalized to 800px height)
  final int zeusThrowIntervalMs;
  final int maxBolts;
  final int lives;
  final double shieldWidth;
  final int timeLimitSeconds;

  String get title => 'Level ${index + 1}';
}

/// Generates 40 levels with a smooth ramp from easy to hard.
List<LevelConfig> buildLevels() {
  final rand = Random(42);
  final levels = <LevelConfig>[];
  for (int i = 0; i < 40; i++) {
    final t = i / 39.0; // 0..1 progression

    // Targets grow slowly, then faster.
    final targetCount = (3 + (t * 17)).round(); // 3..20
    final targetRows = 1 + (i ~/ 8).clamp(0, 3); // 1..4 rows

    // Bolt speed ramps up.
    final boltSpeed = 260.0 + t * 340.0; // 260..600

    // Zeus throws faster with each level.
    final zeusThrowIntervalMs = (1400 - t * 900).round().clamp(320, 1400);

    // Allow more simultaneous bolts later on.
    final maxBolts = (2 + (t * 6)).round().clamp(2, 8);

    // Lives decrease a bit.
    final lives = (5 - (t * 2)).round().clamp(3, 5);

    // Shield shrinks slightly on hard levels.
    final shieldWidth = 200.0 - t * 60.0; // 200..140 (base logical width)

    // A soft time limit that decreases per level.
    final timeLimitSeconds = (90 - t * 30).round().clamp(45, 90);

    levels.add(LevelConfig(
      index: i,
      targetCount: targetCount,
      targetRows: targetRows,
      boltSpeed: boltSpeed,
      zeusThrowIntervalMs: zeusThrowIntervalMs,
      maxBolts: maxBolts,
      lives: lives,
      shieldWidth: shieldWidth,
      timeLimitSeconds: timeLimitSeconds,
    ));
  }
  // Consume rand to keep tree-shaker happy about the import intent.
  rand.nextInt(1);
  return levels;
}

final List<LevelConfig> kLevels = buildLevels();
