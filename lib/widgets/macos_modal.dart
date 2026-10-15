import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart'; // To access CrispColorScheme extension on ColorScheme
import 'log_interaction_sheet.dart';
import 'log_prayer_request_sheet.dart';

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
  final disableAnimations = MediaQuery.disableAnimationsOf(context);

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x700F1512),
    transitionDuration:
        disableAnimations ? Duration.zero : const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) {
      final colorScheme = Theme.of(context).colorScheme;
      final content = builder(context);
      final Widget modalBody = (content is Scaffold ||
              content is LogInteractionSheet ||
              content is LogPrayerRequestSheet)
          ? SizedBox(
              height: MediaQuery.of(context).size.height * 0.86,
              child: content,
            )
          : SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: content,
            );

      return Center(
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (barrierDismissible) {
                Navigator.of(context).maybePop();
              }
            },
          },
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: EdgeInsets.zero,
            child: FocusScope(
              autofocus: true,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: width,
                  maxHeight: MediaQuery.of(context).size.height * 0.86,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colorScheme.cardBorder),
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
                    child: modalBody,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) {
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            child,
          ],
        );
      }

      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: curved,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
              child: child,
            ),
          ),
        ],
      );
    },
  );
}
