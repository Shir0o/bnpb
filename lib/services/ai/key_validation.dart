import 'dart:async';

import 'package:http/http.dart' as http;

/// Result of a key/token validation round-trip.
///
/// [ok] is true only when the remote service accepted the credentials.
/// [networkError] is set when we couldn't tell — usually no connectivity
/// or a server-side error — so callers can offer "save anyway" instead
/// of blocking the user.
class KeyValidationResult {
  const KeyValidationResult({
    required this.ok,
    required this.networkError,
    this.message,
  });

  static const KeyValidationResult valid = KeyValidationResult(
    ok: true,
    networkError: false,
  );

  static KeyValidationResult rejected(String reason) =>
      KeyValidationResult(ok: false, networkError: false, message: reason);

  static KeyValidationResult unreachable(String reason) =>
      KeyValidationResult(ok: false, networkError: true, message: reason);

  final bool ok;
  final bool networkError;
  final String? message;
}

/// Lightweight credential health checks. Both endpoints used here are
/// free, low-bandwidth, and unaffected by per-model quotas, so calling
/// them on every Save tap is cheap.
class KeyValidator {
  /// Validates a Google AI Studio (Gemini) API key by listing the
  /// available models. A valid key returns 200 with the model list;
  /// an invalid key returns 400/401/403 with a `status: INVALID_ARGUMENT`
  /// or `PERMISSION_DENIED` payload. No tokens are spent.
  static Future<KeyValidationResult> gemini(String apiKey) async {
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
    );
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      switch (response.statusCode) {
        case 200:
          return KeyValidationResult.valid;
        case 400:
        case 401:
        case 403:
          return KeyValidationResult.rejected(
            'Google rejected this key. Double-check that you copied it '
            'from aistudio.google.com/app/apikey.',
          );
        default:
          return KeyValidationResult.unreachable(
            'Google returned HTTP ${response.statusCode}. Try again in a '
            'moment.',
          );
      }
    } on TimeoutException {
      return KeyValidationResult.unreachable(
        'Timed out reaching Google. Check your network and try again.',
      );
    } catch (_) {
      return KeyValidationResult.unreachable(
        'Could not reach Google to validate the key. Check your network.',
      );
    }
  }

  /// Validates a Hugging Face access token via the `whoami-v2` endpoint.
  /// Valid tokens return 200 with the user record; revoked/wrong tokens
  /// return 401. We don't care about the payload — only the status.
  static Future<KeyValidationResult> huggingFace(String token) async {
    final url = Uri.parse('https://huggingface.co/api/whoami-v2');
    try {
      final response = await http.get(url, headers: {
        'Authorization': 'Bearer $token'
      }).timeout(const Duration(seconds: 8));
      switch (response.statusCode) {
        case 200:
          return KeyValidationResult.valid;
        case 401:
        case 403:
          return KeyValidationResult.rejected(
            'Hugging Face rejected this token. Generate a read-only token '
            'at huggingface.co/settings/tokens and try again.',
          );
        default:
          return KeyValidationResult.unreachable(
            'Hugging Face returned HTTP ${response.statusCode}. Try again '
            'in a moment.',
          );
      }
    } on TimeoutException {
      return KeyValidationResult.unreachable(
        'Timed out reaching Hugging Face. Check your network and try again.',
      );
    } catch (_) {
      return KeyValidationResult.unreachable(
        'Could not reach Hugging Face to validate the token.',
      );
    }
  }
}
