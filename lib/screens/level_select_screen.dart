import 'package:flutter/material.dart';

import '../data/levels.dart';
import '../data/progress.dart';
import 'game_screen.dart';

class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({super.key});

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  int _unlocked = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final u = await ProgressStore.getUnlocked();
    if (mounted) setState(() => _unlocked = u);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg21zeus.webp', fit: BoxFit.cover),
          Container(color: Colors.black.withOpacity(0.55)),
          SafeArea(
            child: Column(
              children: [
                _header(context),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: GridView.builder(
                      itemCount: kLevels.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1,
                      ),
                      itemBuilder: (context, index) {
                        final unlocked = index <= _unlocked;
                        return _LevelTile(
                          number: index + 1,
                          locked: !unlocked,
                          onTap: unlocked
                              ? () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => GameScreen(
                                        levelIndex: index,
                                      ),
                                    ),
                                  );
                                  _load();
                                }
                              : null,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 20, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded,
                color: Color(0xFFF6D36B), size: 28),
          ),
          const Expanded(
            child: Text(
              'SELECT LEVEL',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFF6D36B),
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 6),
                ],
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.number,
    required this.locked,
    required this.onTap,
  });

  final int number;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: locked
                  ? const [Color(0xFF2A2418), Color(0xFF1A1408)]
                  : const [
                      Color(0xFFFFE58A),
                      Color(0xFFE8B94A),
                      Color(0xFFB47912),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: locked
                  ? const Color(0xFF3A2A0A)
                  : const Color(0xFF3A2A0A),
              width: 2,
            ),
            boxShadow: locked
                ? const []
                : [
                    BoxShadow(
                      color: const Color(0xFFE8B94A).withOpacity(0.35),
                      blurRadius: 10,
                    ),
                  ],
          ),
          child: Center(
            child: locked
                ? const Icon(Icons.lock_rounded,
                    color: Color(0xFFF6D36B), size: 26)
                : Text(
                    '$number',
                    style: const TextStyle(
                      color: Color(0xFF1A1305),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
