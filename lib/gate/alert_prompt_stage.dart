import 'package:flutter/material.dart';

import '../core/alert_relay.dart';
import '../core/local_vault.dart';
import '../core/net_probe.dart';
import 'portal_stage.dart' deferred as portal;

class AlertPromptStage extends StatefulWidget {
  final LocalVault vault;
  final AlertRelay alerts;
  final NetProbe netProbe;
  final String nextUrl;

  const AlertPromptStage({
    super.key,
    required this.vault,
    required this.alerts,
    required this.netProbe,
    required this.nextUrl,
  });

  @override
  State<AlertPromptStage> createState() => _AlertPromptStageState();
}

class _AlertPromptStageState extends State<AlertPromptStage> {
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.alerts.askPermission();
    if (!widget.vault.isAlertGranted()) {
      await widget.vault.snoozeAlertForDefaultCooldown();
    }
    if (!mounted) return;
    _forward();
  }

  Future<void> _skip() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.vault.snoozeAlertForDefaultCooldown();
    if (!mounted) return;
    _forward();
  }

  Future<void> _forward() async {
    await portal.loadLibrary();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => portal.PortalStage(
          targetUrl: widget.nextUrl,
          vault: widget.vault,
          alerts: widget.alerts,
          netProbe: widget.netProbe,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      body: OrientationBuilder(builder: (ctx, orient) {
        final horiz = orient == Orientation.landscape;
        final art = horiz
            ? 'assets/Horizontal_Notifications_Screen .webp'
            : 'assets/Vertical_Notifications_Screen.webp';
        final size = MediaQuery.of(ctx).size;

        // In landscape: buttons side by side in the bottom quarter.
        // In portrait : buttons stacked, bottom padding.
        final btnWidth =
            horiz ? size.width * 0.38 : double.infinity;
        final hPad = horiz ? size.width * 0.08 : 28.0;
        // Portrait: nudge the button block 5 px to the right.
        // Landscape: symmetric padding — the row must stay dead-centre,
        // so left/right are equal (no notch-driven offset).
        final double leftPad = horiz ? hPad : hPad + 5;
        final double rightPad = horiz ? hPad : hPad - 5;
        final vPad = horiz ? 14.0 : 36.0;

        return Stack(fit: StackFit.expand, children: [
          // Image is full-bleed — covers notch/nav areas intentionally.
          Image.asset(art, fit: BoxFit.cover, gaplessPlayback: true),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.6),
                  ],
                ),
              ),
            ),
          ),

          // ── Buttons ──────────────────────────────────────
          // Portrait keeps a full SafeArea (notch top / nav bottom).
          // Landscape intentionally skips SafeArea: an asymmetric
          // camera-cutout inset would shift the usable width and push
          // the button row off the horizontal centre. Only the bottom
          // nav inset is honoured there via extra bottom padding.
          Positioned.fill(
            child: _SafeAreaMaybe(
              enabled: !horiz,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: leftPad,
                    right: rightPad,
                    bottom: horiz
                        ? vPad + MediaQuery.of(ctx).padding.bottom
                        : vPad,
                  ),
                  child: horiz
                      ? Row(
                          children: [
                            Expanded(
                              child: _PromoButton(
                                label: 'ACCEPT',
                                solid: true,
                                disabled: _busy,
                                onTap: _accept,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _PromoButton(
                                label: 'SKIP',
                                solid: false,
                                disabled: _busy,
                                onTap: _skip,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: btnWidth,
                              child: _PromoButton(
                                label: 'ACCEPT',
                                solid: true,
                                disabled: _busy,
                                onTap: _accept,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: btnWidth,
                              child: _PromoButton(
                                label: 'SKIP',
                                solid: false,
                                disabled: _busy,
                                onTap: _skip,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}

// ─── Conditional SafeArea wrapper ─────────────────────────────────────
// When [enabled] is false the child is returned untouched, so no
// safe-area insets are applied. Used to keep the landscape button row
// perfectly centred (an asymmetric notch inset would offset it).

class _SafeAreaMaybe extends StatelessWidget {
  final bool enabled;
  final Widget child;

  const _SafeAreaMaybe({required this.enabled, required this.child});

  @override
  Widget build(BuildContext context) {
    return enabled ? SafeArea(child: child) : child;
  }
}

// ─── Single button used for both Accept and Skip ──────────────────────

class _PromoButton extends StatefulWidget {
  final String label;
  final bool solid;    // true = gold fill, false = outlined
  final bool disabled;
  final VoidCallback onTap;

  const _PromoButton({
    required this.label,
    required this.solid,
    required this.disabled,
    required this.onTap,
  });

  @override
  State<_PromoButton> createState() => _PromoButtonState();
}

class _PromoButtonState extends State<_PromoButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const h = 48.0;
    const radius = 12.0;
    final gold = const Color(0xFFE8B94A);

    final bg = widget.solid
        ? (widget.disabled
            ? const Color(0xFF6A5015)
            : gold)
        : Colors.transparent;

    final border = Border.all(
      color: widget.disabled
          ? const Color(0xFF6A5015)
          : gold,
      width: 1.8,
    );

    final labelColor = widget.solid
        ? const Color(0xFF1A1100)
        : (widget.disabled ? const Color(0xFF8A7030) : gold);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (!widget.disabled) widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: AnimatedOpacity(
          opacity: _pressed ? 0.82 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: Container(
            height: h,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(radius),
              border: border,
              boxShadow: widget.solid && !widget.disabled
                  ? [
                      BoxShadow(
                        color: gold.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                widget.label,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
