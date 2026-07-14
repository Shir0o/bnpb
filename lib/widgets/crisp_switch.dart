import 'package:flutter/material.dart';
import '../main.dart'; // To access CrispColorScheme extension on ColorScheme

/// A custom switch styled according to the Crisp Utility design specs.
/// Height: 26px, Width: 44px, border-radius: 14px.
class CrispSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const CrispSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEnabled = onChanged != null;

    return GestureDetector(
      onTap: isEnabled ? () => onChanged!(!value) : null,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
        child: Semantics(
          toggled: value,
          enabled: isEnabled,
          label: 'Switch Toggle',
          container: true,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
            width: 44,
            height: 26,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: value ? colorScheme.primary : colorScheme.switchOff,
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeInOut,
                  left: value ? 21.0 : 3.0,
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
    );
  }
}
