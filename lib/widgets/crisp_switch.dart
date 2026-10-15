import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart'; // To access CrispColorScheme extension on ColorScheme

/// A custom switch styled according to the Crisp Utility design specs.
/// Height: 26px, Width: 44px, border-radius: 14px.
class CrispSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;

  const CrispSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel = 'Toggle',
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<CrispSwitch> createState() => _CrispSwitchState();
}

class _CrispSwitchState extends State<CrispSwitch> {
  bool _isFocused = false;

  void _handleToggle() {
    if (widget.onChanged != null) {
      widget.onChanged!(!widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEnabled = widget.onChanged != null;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final duration =
        disableAnimations ? Duration.zero : const Duration(milliseconds: 150);

    return FocusableActionDetector(
      enabled: isEnabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor:
          isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onShowFocusHighlight: (showHighlight) {
        if (_isFocused != showHighlight) {
          setState(() => _isFocused = showHighlight);
        }
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _handleToggle();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: isEnabled ? _handleToggle : null,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Opacity(
              opacity: isEnabled ? 1.0 : 0.5,
              child: Semantics(
                toggled: widget.value,
                enabled: isEnabled,
                label: widget.semanticLabel,
                container: true,
                child: AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeInOut,
                  width: 44,
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: widget.value
                        ? colorScheme.primary
                        : colorScheme.switchOff,
                    boxShadow: _isFocused
                        ? [
                            BoxShadow(
                              color: colorScheme.primary.withValues(alpha: 0.4),
                              blurRadius: 4,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        duration: duration,
                        curve: Curves.easeInOut,
                        left: widget.value ? 21.0 : 3.0,
                        top: 3.0,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.knobColor,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
