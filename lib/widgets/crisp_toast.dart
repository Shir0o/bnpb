import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart'; // To access CrispColorScheme extension on ColorScheme

/// A floating, auto-dismissing pill notification styled according to the
/// Crisp Utility design specs, replacing the default [SnackBar] for
/// informational save/confirm/error messages.
class CrispToast {
  CrispToast._();

  static const Duration _visibleDuration = Duration(milliseconds: 1900);
  static const Duration _fadeDuration = Duration(milliseconds: 200);

  /// Shows [message] in a floating pill above the bottom nav/FAB, then
  /// auto-dismisses. No action button, no swipe-to-dismiss.
  static void show(BuildContext context, String message) {
    showOnOverlay(Overlay.of(context), message);
  }

  /// Same as [show], but takes an [OverlayState] captured ahead of time.
  /// Useful for services that, like [ScaffoldMessengerState], need to
  /// surface a message after a long-running async operation where the
  /// original [BuildContext] may no longer be valid.
  static void showOnOverlay(OverlayState overlay, String message) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _CrispToastWidget(
        message: message,
        fadeDuration: _fadeDuration,
        visibleDuration: _visibleDuration,
        onDismissed: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _CrispToastWidget extends StatefulWidget {
  const _CrispToastWidget({
    required this.message,
    required this.fadeDuration,
    required this.visibleDuration,
    required this.onDismissed,
  });

  final String message;
  final Duration fadeDuration;
  final Duration visibleDuration;
  final VoidCallback onDismissed;

  @override
  State<_CrispToastWidget> createState() => _CrispToastWidgetState();
}

class _CrispToastWidgetState extends State<_CrispToastWidget> {
  bool _visible = false;
  Timer? _hideTimer;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
    _hideTimer = Timer(widget.visibleDuration, () {
      if (mounted) setState(() => _visible = false);
      _dismissTimer = Timer(widget.fadeDuration, widget.onDismissed);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      left: 24,
      right: 24,
      bottom: 96,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: widget.fadeDuration,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              decoration: BoxDecoration(
                color: colorScheme.aiCardBg,
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
