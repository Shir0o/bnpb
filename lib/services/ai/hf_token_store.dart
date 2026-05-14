import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the user-supplied Hugging Face access token in the device key
/// store. The token is needed to download gated Gemma models; it never
/// leaves the device and is only sent in the Authorization header to
/// huggingface.co during model download.
class HfTokenStore {
  HfTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'ai.huggingface_token';

  final FlutterSecureStorage _storage;

  Future<String?> read() => _storage.read(key: _key);

  Future<void> write(String token) => _storage.write(key: _key, value: token);

  Future<void> delete() => _storage.delete(key: _key);
}
