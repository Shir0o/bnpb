import 'dart:convert';
import 'package:http/http.dart' as http;
import 'local_llm_service.dart';

/// Cloud backend for [LocalLlmService] that routes prompts to Hugging Face's
/// Serverless Inference API.
class HuggingFaceApiLlmService implements LocalLlmService {
  HuggingFaceApiLlmService({
    required String apiKey,
    String modelId = 'meta-llama/Llama-3.2-3B-Instruct',
    http.Client? client,
  })  : _apiKey = apiKey,
        _modelId = modelId,
        _client = client ?? http.Client();

  final String _apiKey;
  final String _modelId;
  final http.Client _client;

  @override
  bool get isReady => true;

  @override
  Future<void> load(String modelPath) async {}

  @override
  Future<void> unload() async {}

  @override
  Future<String> generate(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.4,
  }) async {
    final uri =
        Uri.parse('https://api-inference.huggingface.co/models/$_modelId');
    final response = await _client.post(
      uri,
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'inputs': prompt,
        'parameters': {
          'max_new_tokens': maxTokens,
          'temperature': temperature,
          'return_full_text': false,
        },
      }),
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Hugging Face API error (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is List && decoded.isNotEmpty) {
      final first = decoded.first;
      if (first is Map && first.containsKey('generated_text')) {
        return (first['generated_text'] as String?)?.trim() ?? '';
      }
    } else if (decoded is Map && decoded.containsKey('generated_text')) {
      return (decoded['generated_text'] as String?)?.trim() ?? '';
    }

    return response.body.trim();
  }
}
