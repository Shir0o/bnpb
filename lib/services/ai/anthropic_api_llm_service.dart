import 'dart:convert';
import 'package:http/http.dart' as http;
import 'local_llm_service.dart';

/// Cloud backend for [LocalLlmService] that routes prompts to Anthropic's Claude API.
class AnthropicApiLlmService implements LocalLlmService {
  AnthropicApiLlmService({
    required String apiKey,
    String modelId = 'claude-3-5-haiku-latest',
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
    final uri = Uri.parse('https://api.anthropic.com/v1/messages');
    final response = await _client.post(
      uri,
      headers: {
        'x-api-key': _apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'model': _modelId,
        'max_tokens': maxTokens,
        'temperature': temperature,
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Anthropic API error (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content = data['content'] as List<dynamic>?;
    if (content == null || content.isEmpty) return '';

    final firstText = content.firstWhere(
      (c) => c['type'] == 'text',
      orElse: () => {'text': ''},
    );
    return (firstText['text'] as String?)?.trim() ?? '';
  }
}
