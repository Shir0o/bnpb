import 'dart:convert';
import 'package:http/http.dart' as http;
import 'ai_feature_gate.dart';

/// Represents a model discovered from a provider API with pricing details.
class AiModelInfo {
  final String id;
  final String displayName;
  final String? description;
  final double? inputPricePerMillion;
  final double? outputPricePerMillion;
  final bool isFree;

  const AiModelInfo({
    required this.id,
    required this.displayName,
    this.description,
    this.inputPricePerMillion,
    this.outputPricePerMillion,
    this.isFree = false,
  });

  String get pricingLabel {
    if (isFree) return 'Free / On-Device';
    if (inputPricePerMillion != null && outputPricePerMillion != null) {
      return '\$${inputPricePerMillion!.toStringAsFixed(2)} / \$${outputPricePerMillion!.toStringAsFixed(2)} per 1M';
    }
    return 'Standard API rates';
  }
}

/// Service that dynamically fetches available models from provider APIs with pricing metadata.
class DynamicModelCatalog {
  final http.Client _client;

  DynamicModelCatalog({http.Client? client})
      : _client = client ?? http.Client();

  /// Fetches available models for [backend] using the user's [apiKey].
  Future<List<AiModelInfo>> getModels(AiBackend backend,
      {String? apiKey}) async {
    switch (backend) {
      case AiBackend.local:
        return _getLocalModels();
      case AiBackend.cloud:
        return _getGeminiModels(apiKey);
      case AiBackend.claude:
        return _getClaudeModels(apiKey);
      case AiBackend.huggingface:
        return _getHuggingFaceModels(apiKey);
    }
  }

  List<AiModelInfo> _getLocalModels() {
    return const [
      AiModelInfo(
        id: 'gemma-3n-e2b-int4',
        displayName: 'Gemma 3n E2B (int4)',
        description: 'On-device private model via MediaPipe / LiteRT',
        isFree: true,
      ),
    ];
  }

  Future<List<AiModelInfo>> _getGeminiModels(String? apiKey) async {
    if (apiKey == null || apiKey.isEmpty) {
      return _fallbackGeminiModels();
    }

    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
      );
      final res = await _client.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final models = (data['models'] as List<dynamic>?) ?? [];
        final list = <AiModelInfo>[];

        for (final m in models) {
          final name = m['name'] as String? ?? '';
          final modelId = name.replaceFirst('models/', '');
          final methods =
              (m['supportedGenerationMethods'] as List<dynamic>?) ?? [];
          if (!methods.contains('generateContent')) continue;

          final (inPrice, outPrice) = _resolveGeminiPrice(modelId);
          list.add(
            AiModelInfo(
              id: modelId,
              displayName: m['displayName'] as String? ?? modelId,
              description: m['description'] as String?,
              inputPricePerMillion: inPrice,
              outputPricePerMillion: outPrice,
            ),
          );
        }

        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    return _fallbackGeminiModels();
  }

  List<AiModelInfo> _fallbackGeminiModels() {
    return const [
      AiModelInfo(
        id: 'gemini-2.5-flash',
        displayName: 'Gemini 2.5 Flash',
        description: 'High-speed multimodal, low cost',
        inputPricePerMillion: 0.15,
        outputPricePerMillion: 0.60,
      ),
      AiModelInfo(
        id: 'gemini-2.5-pro',
        displayName: 'Gemini 2.5 Pro',
        description: 'Advanced reasoning and analysis',
        inputPricePerMillion: 1.25,
        outputPricePerMillion: 5.00,
      ),
      AiModelInfo(
        id: 'gemini-2.0-flash',
        displayName: 'Gemini 2.0 Flash',
        description: 'Ultra fast standard generation',
        inputPricePerMillion: 0.10,
        outputPricePerMillion: 0.40,
      ),
    ];
  }

  (double?, double?) _resolveGeminiPrice(String id) {
    final lower = id.toLowerCase();
    if (lower.contains('pro')) {
      return (1.25, 5.00);
    }
    if (lower.contains('flash')) {
      return (0.15, 0.60);
    }
    return (0.50, 1.50);
  }

  Future<List<AiModelInfo>> _getClaudeModels(String? apiKey) async {
    if (apiKey == null || apiKey.isEmpty) {
      return _fallbackClaudeModels();
    }

    try {
      final uri = Uri.parse('https://api.anthropic.com/v1/models');
      final res = await _client.get(
        uri,
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        },
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final models = (data['data'] as List<dynamic>?) ?? [];
        final list = <AiModelInfo>[];

        for (final m in models) {
          final modelId = m['id'] as String? ?? '';
          final (inPrice, outPrice) = _resolveClaudePrice(modelId);
          list.add(
            AiModelInfo(
              id: modelId,
              displayName: m['display_name'] as String? ?? modelId,
              inputPricePerMillion: inPrice,
              outputPricePerMillion: outPrice,
            ),
          );
        }

        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    return _fallbackClaudeModels();
  }

  List<AiModelInfo> _fallbackClaudeModels() {
    return const [
      AiModelInfo(
        id: 'claude-3-5-haiku-latest',
        displayName: 'Claude 3.5 Haiku',
        description: 'Fastest and most cost-effective Claude',
        inputPricePerMillion: 0.80,
        outputPricePerMillion: 4.00,
      ),
      AiModelInfo(
        id: 'claude-3-7-sonnet-latest',
        displayName: 'Claude 3.7 Sonnet',
        description: 'State-of-the-art hybrid reasoning',
        inputPricePerMillion: 3.00,
        outputPricePerMillion: 15.00,
      ),
      AiModelInfo(
        id: 'claude-3-5-sonnet-latest',
        displayName: 'Claude 3.5 Sonnet',
        description: 'Balanced intelligent generation',
        inputPricePerMillion: 3.00,
        outputPricePerMillion: 15.00,
      ),
    ];
  }

  (double?, double?) _resolveClaudePrice(String id) {
    final lower = id.toLowerCase();
    if (lower.contains('haiku')) {
      return (0.80, 4.00);
    }
    if (lower.contains('sonnet')) {
      return (3.00, 15.00);
    }
    if (lower.contains('opus')) {
      return (15.00, 75.00);
    }
    return (1.00, 5.00);
  }

  Future<List<AiModelInfo>> _getHuggingFaceModels(String? apiKey) async {
    try {
      final uri = Uri.parse(
        'https://huggingface.co/api/models?pipeline_tag=text-generation&sort=trending&limit=15',
      );
      final headers = <String, String>{};
      if (apiKey != null && apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer $apiKey';
      }
      final res = await _client.get(uri, headers: headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List<dynamic>;
        final list = <AiModelInfo>[];
        for (final m in data) {
          final modelId = m['id'] as String? ?? '';
          list.add(
            AiModelInfo(
              id: modelId,
              displayName: modelId,
              description: 'HF Trending Model',
              inputPricePerMillion: 0.0,
              outputPricePerMillion: 0.0,
              isFree: true,
            ),
          );
        }
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    return const [
      AiModelInfo(
        id: 'meta-llama/Llama-3.2-3B-Instruct',
        displayName: 'Llama 3.2 3B Instruct',
        isFree: true,
      ),
      AiModelInfo(
        id: 'mistralai/Mistral-7B-Instruct-v0.3',
        displayName: 'Mistral 7B Instruct',
        isFree: true,
      ),
      AiModelInfo(
        id: 'Qwen/Qwen2.5-7B-Instruct',
        displayName: 'Qwen 2.5 7B Instruct',
        isFree: true,
      ),
    ];
  }
}
