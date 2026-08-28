import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Regression guard for flutter_local_notifications scheduled-notification
// delivery: the plugin (v16.3+) ships NO receivers in its own manifest and
// requires the app to declare ScheduledNotificationReceiver (alarm delivery)
// and ScheduledNotificationBootReceiver (re-arm after reboot) itself.
//
// If the delivery receiver is missing, Android drops the scheduled alarm
// broadcast silently: the reminder never appears, and the app only ever shows
// it via the immediate-fire path when it is opened.
void main() {
  late String manifest;

  setUpAll(() {
    manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
  });

  test('AndroidManifest declares the scheduled-notification receiver', () {
    expect(
      manifest,
      contains(
        'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver',
      ),
      reason: 'Without this receiver the AlarmManager broadcast is dropped and '
          'scheduled reminders never appear.',
    );
  });

  test('AndroidManifest declares the boot receiver with re-arm actions', () {
    expect(
      manifest,
      contains(
        'com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver',
      ),
      reason: 'Without this receiver Android wipes all alarms on reboot and '
          'reminders are lost until the app is reopened.',
    );
    expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
    expect(manifest, contains('android.intent.action.MY_PACKAGE_REPLACED'));
  });
}
