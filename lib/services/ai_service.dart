import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/db_helper.dart';
import 'security_service.dart';
import '../models/contact.dart';
import '../models/prayer_request.dart';
import 'follow_up_recommendation_service.dart';

class AIService {
  static final AIService _instance = AIService._();
  factory AIService() => _instance;
  AIService._();

  GenerativeModel? _model;
  String? _currentApiKey;

  static const _cacheKey = 'ai_recommendations_cache';
  static const _fingerprintKey = 'ai_recommendations_fingerprint';
  static const _timestampKey = 'ai_recommendations_timestamp';

  Future<GenerativeModel?> _getModel() async {
    final apiKey = await SecurityService().getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) return null;

    if (_model != null && _currentApiKey == apiKey) return _model;

    _currentApiKey = apiKey;
    _model = GenerativeModel(
      model: 'gemini-1.5-flash-latest',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );
    return _model;
  }

  Future<List<FollowUpRecommendation>> getSmartRecommendations(
    List<Contact> contacts, {
    bool forceRefresh = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final dbHelper = DBHelper();
    final metadata = await dbHelper.getGlobalMetadata();
    final fingerprint = jsonEncode(metadata);

    if (!forceRefresh) {
      final cachedFingerprint = prefs.getString(_fingerprintKey);
      final cachedTimestamp = prefs.getInt(_timestampKey) ?? 0;
      final cachedJson = prefs.getString(_cacheKey);

      final isRecent = DateTime.now().millisecondsSinceEpoch - cachedTimestamp <
          const Duration(hours: 24).inMilliseconds;

      if (cachedFingerprint == fingerprint && isRecent && cachedJson != null) {
        return _parseRecommendations(cachedJson, contacts);
      }
    }

    final model = await _getModel();
    if (model == null) return [];

    // Prepare context: focus on contacts with activity or long gaps
    final now = DateTime.now();
    final contactsContext = contacts.map((c) {
      final latestInteraction =
          c.interactions.isNotEmpty ? c.interactions.first : null;
      final gap = latestInteraction != null
          ? now.difference(latestInteraction.occurredAt).inDays
          : null;

      return {
        'id': c.id,
        'name': c.displayName,
        'last_interaction_days_ago': gap,
        'recent_interactions': c.interactions
            .take(2)
            .map((i) => {
                  'summary': i.summary,
                  'date': i.occurredAt.toIso8601String(),
                })
            .toList(),
        'pending_prayers': c.prayerRequests
            .where((p) => p.status == PrayerRequestStatus.pending)
            .map((p) => p.description)
            .toList(),
      };
    }).toList();

    final prompt = '''
You are an assistant helping a user manage their relationships and follow up with people.
Based on the following contact list and their recent activity, provide up to 5 recommendations for who the user should reach out to and why.

Priorities should be:
- critical: urgent follow-up (e.g. overdue task, long gap with a close contact)
- high: significant event or medium gap
- medium: standard follow-up
- low: general check-in

Output MUST be a JSON array of objects with these fields:
- contact_id: the ID of the contact
- reason: a concise reason for the follow-up
- priority: one of [critical, high, medium, low]

Contacts:
${jsonEncode(contactsContext)}
''';

    try {
      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      final text = response.text;
      if (text == null) return [];

      // Validate JSON before saving
      final recommendations = _parseRecommendations(text, contacts);
      if (recommendations.isNotEmpty) {
        await prefs.setString(_cacheKey, text);
        await prefs.setString(_fingerprintKey, fingerprint);
        await prefs.setInt(
            _timestampKey, DateTime.now().millisecondsSinceEpoch);
      }
      return recommendations;
    } catch (e) {
      debugPrint('AI Recommendation error: $e');
      // If error occurs, try to return expired cache as fallback
      final expiredJson = prefs.getString(_cacheKey);
      if (expiredJson != null) {
        return _parseRecommendations(expiredJson, contacts);
      }
      return [];
    }
  }

  List<FollowUpRecommendation> _parseRecommendations(
    String jsonStr,
    List<Contact> contacts,
  ) {
    try {
      final List<dynamic> data = jsonDecode(jsonStr);
      final recommendations = <FollowUpRecommendation>[];

      for (final item in data) {
        final contactId = item['contact_id'] as String;
        final contact = contacts.cast<Contact?>().firstWhere(
              (c) => c?.id == contactId,
              orElse: () => null,
            );

        if (contact == null) continue;

        final priorityStr = item['priority'] as String;
        final priority = RecommendationPriority.values.firstWhere(
          (e) => e.name == priorityStr,
          orElse: () => RecommendationPriority.medium,
        );

        recommendations.add(FollowUpRecommendation(
          contact: contact,
          reason: item['reason'] as String,
          priority: priority,
        ));
      }
      return recommendations;
    } catch (e) {
      debugPrint('Error parsing recommendations: $e');
      return [];
    }
  }
}
