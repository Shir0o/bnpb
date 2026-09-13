import 'package:bnpb/models/recurring_log_pattern.dart';
import 'package:bnpb/services/recurring_log_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('round-trips preferences through JSON', () {
    final preferences = RecurringLogPreferences().withPreference(
      'contact@@bible reading@@coffee',
      RecurringLogPreference(
        confirmed: true,
        spanOverride: 2,
        cadenceOverride: PatternCadence.weekdays({
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.thursday,
          DateTime.friday,
          DateTime.saturday,
        }),
      ),
    );

    final decoded = RecurringLogPreferences.fromJson(
      preferences.toJson(),
    );
    final value = decoded.preferenceFor('contact@@bible reading@@coffee');

    expect(value.confirmed, isTrue);
    expect(value.spanOverride, 2);
    final cadence = value.cadenceOverride as PatternCadence;
    expect(cadence.weekdays, hasLength(6));
  });

  test('stores and loads preferences using SharedPreferences', () async {
    final store = RecurringLogPreferenceStore();
    final preferences = RecurringLogPreferences().withPreference(
      'contact@@workout@@in person',
      const RecurringLogPreference(confirmed: true),
    );

    await store.save(preferences);
    final loaded = await store.load();

    expect(
        loaded.preferenceFor('contact@@workout@@in person').confirmed, isTrue);
  });
}
