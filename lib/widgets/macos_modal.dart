import 'package:flutter/material.dart';

/// Shows [builder]'s content as a centered dialog styled per the Crisp
/// Utility desktop design (20px radius, dark scrim, scale/fade-in), used on
/// macOS in place of the mobile bottom sheets built with
/// [showModalBottomSheet].
Future<T?> showMacModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = 480,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x700F1512),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) {
      final colorScheme = Theme.of(context).colorScheme;
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width,
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 70,
                  spreadRadius: -20,
                  offset: const Offset(0, 30),
                ),
              ],
            ),
            child: Material(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              elevation: 0,
              child: builder(context),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
