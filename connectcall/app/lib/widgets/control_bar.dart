import 'package:flutter/material.dart';

/// Round toggle button used in the meeting control bar.
class ControlButton extends StatelessWidget {
  const ControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = true,
    this.danger = false,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// When false the button is shown in the "off" style (e.g. mic muted).
  final bool active;
  final bool danger;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (danger) {
      bg = Colors.red.shade600;
      fg = Colors.white;
    } else if (active) {
      bg = const Color(0xFF2B2E3A);
      fg = Colors.white;
    } else {
      bg = Colors.white;
      fg = Colors.black87;
    }
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: busy ? null : onPressed,
            child: SizedBox.square(
              dimension: 54,
              child: busy
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                    )
                  : Icon(icon, color: onPressed == null ? fg.withValues(alpha: 0.4) : fg),
            ),
          ),
        ),
      ),
    );
  }
}
