import 'package:flutter/material.dart';

import 'level_select_screen.dart';
import 'webview_screen.dart';

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  static const _privacyUrl =
      'https://aegisthunder.com/privacy-policy.html';
  static const _supportUrl = 'https://aegisthunder.com/support.html';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bgZeus.webp', fit: BoxFit.cover),
          Container(color: Colors.black.withOpacity(0.35)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: Image.asset(
                        'assets/logo.webp',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 6,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _MenuButton(
                          label: 'PLAY',
                          icon: Icons.play_arrow_rounded,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const LevelSelectScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        _MenuButton(
                          label: 'PRIVACY POLICY',
                          icon: Icons.privacy_tip_outlined,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const WebViewScreen(
                                  title: 'Privacy Policy',
                                  url: _privacyUrl,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        _MenuButton(
                          label: 'SUPPORT',
                          icon: Icons.support_agent_outlined,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const WebViewScreen(
                                  title: 'Support',
                                  url: _supportUrl,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFFE58A),
                  Color(0xFFE8B94A),
                  Color(0xFFB47912),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF3A2A0A), width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE8B94A).withOpacity(0.5),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 18),
                Icon(icon, color: const Color(0xFF1A1305), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF1A1305),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
