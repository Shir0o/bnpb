import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/recurring_log_pattern.dart';

class RecurringLogPreference {
  const RecurringLogPreference({
    this.confirmed = false,
    this.suppressed = false,
    this.snoozedUntil,
    this.spanOverride,
    this.cadenceOverride,
  });

  final bool confirmed;
  final bool suppressed;
  final DateTime? snoozedUntil;
  final int? spanOverride;
  final PatternCadence? cadenceOverride;

  RecurringLogPreference copyWith({
    bool? confirmed,
    bool? suppressed,
    DateTime? snoozedUntil,
    int? spanOverride,
    bool clearSpan = false,
    PatternCadence? cadenceOverride,
    bool clearCadence = false,
  }) {
    return RecurringLogPreference(
      confirmed: confirmed ?? this.confirmed,
      suppressed: suppressed ?? this.suppressed,
      snoozedUntil: snoozedUntil ?? this.snoozedUntil,
      spanOverride: clearSpan ? null : (spanOverride ?? this.spanOverride),
      cadenceOverride:
          clearCadence ? null : (cadenceOverride ?? this.cadenceOverride),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'confirmed': confirmed,
      'suppressed': suppressed,
      'snoozedUntil': snoozedUntil?.toIso8601String(),
      'spanOverride': spanOverride,
      'cadenceOverride': cadenceOverride?.toJson(),
    };
  }

  static RecurringLogPreference fromJson(Map<String, dynamic> json) {
    final snoozeRaw = json['snoozedUntil'];
    final cadenceRaw = json['cadenceOverride'];
    return RecurringLogPreference(
      confirmed: json['confirmed'] == true,
      suppressed: json['suppressed'] == true,
      snoozedUntil: snoozeRaw is String ? DateTime.tryParse(snoozeRaw) : null,
      spanOverride: json['spanOverride'] is num
          ? (json['spanOverride'] as num).toInt()
          : null,
      cadenceOverride: cadenceRaw is Map
          ? PatternCadence.fromJson(Map<String, dynamic>.from(cadenceRaw))
          : null,
    );
  }
}

class RecurringLogPreferences {
  RecurringLogPreferences([Map<String, RecurringLogPreference>? entries])
      : _entries = Map<String, RecurringLogPreference>.from(entries ?? {});

  final Map<String, RecurringLogPreference> _entries;

  RecurringLogPreference? get(String key) => _entries[key];

  RecurringLogPreference preferenceFor(String key) =>
      _entries[key] ?? const RecurringLogPreference();

  RecurringLogPreferences withPreference(
    String key,
    RecurringLogPreference preference,
  ) {
    final next = Map<String, RecurringLogPreference>.from(_entries);
    next[key] = preference;
    return RecurringLogPreferences(next);
  }

  Map<String, dynamic> toJson() => {
        for (final entry in _entries.entries) entry.key: entry.value.toJson(),
      };

  static RecurringLogPreferences fromJson(Map<String, dynamic> json) {
    final entries = <String, RecurringLogPreference>{};
    for (final entry in json.entries) {
      final raw = entry.value;
      if (raw is Map) {
        entries[entry.key] =
            RecurringLogPreference.fromJson(Map<String, dynamic>.from(raw));
      }
    }
    return RecurringLogPreferences(entries);
  }
}

class RecurringLogPreferenceStore {
  static const String _prefsKey = 'recurring_log.preferences';

  Future<RecurringLogPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return RecurringLogPreferences();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return RecurringLogPreferences.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {
      // Corrupt preference payload; fall back to an empty model.
    }
    return RecurringLogPreferences();
  }

  Future<void> save(RecurringLogPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(preferences.toJson()));
  }
}
