import 'package:flutter/material.dart';

import '../services/security_service.dart';

/// Wraps the application in a lock screen whenever the user configures a
/// passcode or biometric gate.
class SecurityGate extends StatefulWidget {
  const SecurityGate({required this.child, super.key});

  /// Widget tree to render when the gate is unlocked.
  final Widget child;

  @override
  State<SecurityGate> createState() => _SecurityGateState();
}

enum _GateStatus { loading, locked, unlocked }

class _SecurityGateState extends State<SecurityGate> {
  final SecurityService _securityService = SecurityService();

  _GateStatus _status = _GateStatus.loading;
  bool _biometricsAvailable = false;
  bool _biometricsEnabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _evaluate();
  }

  Future<void> _evaluate() async {
    final hasPasscode = await _securityService.hasPasscode();
    if (!hasPasscode) {
      setState(() {
        _status = _GateStatus.unlocked;
      });
      return;
    }

    final biometricsEnabled = await _securityService.isBiometricEnabled();
    final canUseBiometrics = await _securityService.canUseBiometrics();

    if (biometricsEnabled && canUseBiometrics) {
      final unlocked = await _securityService.authenticateWithBiometrics();
      if (unlocked) {
        setState(() {
          _status = _GateStatus.unlocked;
        });
        return;
      }
    }

    setState(() {
      _status = _GateStatus.locked;
      _biometricsAvailable = canUseBiometrics;
      _biometricsEnabled = biometricsEnabled && canUseBiometrics;
      _error = null;
    });
  }

  Future<void> _unlockWithPasscode(String value) async {
    final success = await _securityService.verifyPasscode(value);
    if (success) {
      setState(() {
        _status = _GateStatus.unlocked;
        _error = null;
      });
      return;
    }

    setState(() {
      _error = 'Incorrect passcode. Please try again.';
    });
  }

  Future<void> _unlockWithBiometrics() async {
    final success = await _securityService.authenticateWithBiometrics();
    if (success) {
      setState(() {
        _status = _GateStatus.unlocked;
        _error = null;
      });
    } else {
      setState(() {
        _error = 'Biometric check failed. Use your passcode instead.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case _GateStatus.unlocked:
        return widget.child;
      case _GateStatus.loading:
        // Return a blank scaffold to avoid a jarring flash of a spinner
        // during the very brief security evaluation.
        return const Scaffold();
      case _GateStatus.locked:
        return _LockScreen(
          onSubmit: _unlockWithPasscode,
          errorText: _error,
          showBiometricButton: _biometricsEnabled,
          onBiometricRequested:
              _biometricsEnabled ? _unlockWithBiometrics : null,
          biometricsAvailable: _biometricsAvailable,
        );
    }
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({
    required this.onSubmit,
    this.onBiometricRequested,
    this.errorText,
    required this.showBiometricButton,
    required this.biometricsAvailable,
  });

  final Future<void> Function(String value) onSubmit;
  final Future<void> Function()? onBiometricRequested;
  final String? errorText;
  final bool showBiometricButton;
  final bool biometricsAvailable;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _obscured = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Enter your passcode',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This device is locked to protect your contacts. '
                    'Provide your passcode to continue.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _controller,
                    obscureText: _obscured,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Passcode',
                      errorText: widget.errorText,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscured
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscured = !_obscured;
                          });
                        },
                      ),
                    ),
                    onSubmitted: widget.onSubmit,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => widget.onSubmit(_controller.text.trim()),
                    child: const Text('Unlock'),
                  ),
                  if (widget.showBiometricButton)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        onPressed: widget.onBiometricRequested,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Use biometrics'),
                      ),
                    )
                  else if (!widget.biometricsAvailable)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Biometric unlock is unavailable on this device.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).hintColor,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
