import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main_menu_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _progressController;
  late final AnimationController _dotsController;

  @override
  void initState() {
    super.initState();
    // Allow all orientations only on the splash screen.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    // Fill up to ~85% smoothly, then jump to 100% right before navigating.
    _progressController.animateTo(0.85, curve: Curves.easeInOut);

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // Finish loading after a short delay, complete the bar, then navigate.
    Timer(const Duration(milliseconds: 4400), _finishLoading);
  }

  Future<void> _finishLoading() async {
    // Instantly fill the bar to 100% just before launching the game.
    await _progressController.animateTo(
      1.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    // Lock orientation to portrait once we leave the splash.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => const MainMenuScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _progressController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isPortrait = orientation == Orientation.portrait;
          final imageAsset = isPortrait
              ? 'assets/verticalloading.webp'
              : 'assets/horizontalloading.webp';
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                imageAsset,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
              // Subtle dark gradient at the bottom so the progress bar reads
              // well over any background variant.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.55),
                      ],
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isPortrait ? 32 : 80,
                      vertical: isPortrait ? 48 : 28,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LoadingLabel(controller: _dotsController),
                        const SizedBox(height: 14),
                        _ProgressBar(controller: _progressController),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LoadingLabel extends StatelessWidget {
  const _LoadingLabel({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final step = (controller.value * 4).floor() % 4;
        final dots = '.' * step;
        return SizedBox(
          width: 220,
          child: Text(
            'Loading$dots',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFF6D36B),
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              shadows: [
                Shadow(
                  color: Colors.black,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final value = controller.value.clamp(0.0, 1.0);
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Container(
              height: 22,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFE8B94A),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE8B94A).withOpacity(0.35),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: width * value,
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
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
