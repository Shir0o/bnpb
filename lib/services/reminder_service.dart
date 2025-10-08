import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/notification_preference.dart';

/// Handles platform notification scheduling for reminders.
class ReminderService {
  ReminderService._();

  static final ReminderService _instance = ReminderService._();

  /// Singleton accessor.
  factory ReminderService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _timeZoneInitialized = false;

  /// Ensures the plugin and time zone data are available before scheduling.
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
    );

    await _plugin.initialize(settings);
    await _configureLocalTimeZone();
    await _requestPlatformPermissions();

    _initialized = true;
  }

  Future<void> _requestPlatformPermissions() async {
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();

    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosImpl?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    final macImpl = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    await macImpl?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _configureLocalTimeZone() async {
    if (_timeZoneInitialized) {
      return;
    }
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
    _timeZoneInitialized = true;
  }

  /// Schedules a reminder for the specified [channel] and [key].
  Future<void> scheduleReminder({
    required ReminderChannel channel,
    String? contactId,
    required String key,
    required DateTime scheduledAt,
    required String title,
    required String body,
    Map<String, dynamic>? additionalPayload,
  }) async {
    await initialize();

    final id = _notificationId(channel, key);
    var target = scheduledAt;
    final now = DateTime.now();
    if (!target.isAfter(now)) {
      target = now.add(const Duration(minutes: 1));
    }
    final tzTime = tz.TZDateTime.from(target, tz.local);

    final androidDetails = AndroidNotificationDetails(
      'reminders_${channel.name}',
      channel.label,
      channelDescription: channel.description,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    );
    const darwinDetails = DarwinNotificationDetails(
      categoryIdentifier: 'reminder',
    );

    final payloadMap = <String, dynamic>{
      'channel': channel.name,
      'key': key,
    };
    if (contactId != null) {
      payloadMap['contactId'] = contactId;
    }
    if (additionalPayload != null) {
      payloadMap.addAll(additionalPayload);
    }
    final payload = jsonEncode(payloadMap);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzTime,
      NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  /// Cancels every notification scheduled for the supplied [channel]
  /// regardless of contact.
  Future<void> cancelChannel(ReminderChannel channel) async {
    await initialize();
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      final payload = request.payload;
      if (payload == null) {
        continue;
      }
      try {
        final decoded = jsonDecode(payload) as Map<String, dynamic>;
        if (decoded['channel'] == channel.name) {
          await _plugin.cancel(request.id);
        }
      } catch (_) {
        continue;
      }
    }
  }

  /// Cancels a previously scheduled reminder using the [key] used during
  /// [scheduleReminder].
  Future<void> cancelReminder(ReminderChannel channel, String key) async {
    await initialize();
    final id = _notificationId(channel, key);
    await _plugin.cancel(id);
  }

  /// Cancels all reminders scheduled for [contactId] under a [channel].
  Future<void> cancelChannelForContact(
    ReminderChannel channel,
    String contactId,
  ) async {
    await initialize();
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      final payload = request.payload;
      if (payload == null) {
        continue;
      }
      try {
        final decoded = jsonDecode(payload) as Map<String, dynamic>;
        if (decoded['channel'] == channel.name &&
            decoded['contactId'] == contactId) {
          await _plugin.cancel(request.id);
        }
      } catch (_) {
        continue;
      }
    }
  }

  /// Cancels every reminder tied to [contactId].
  Future<void> cancelAllForContact(String contactId) async {
    await initialize();
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      final payload = request.payload;
      if (payload == null) {
        continue;
      }
      try {
        final decoded = jsonDecode(payload) as Map<String, dynamic>;
        if (decoded['contactId'] == contactId) {
          await _plugin.cancel(request.id);
        }
      } catch (_) {
        continue;
      }
    }
  }

  /// Cancels every scheduled reminder regardless of contact.
  Future<void> cancelAll() async {
    await initialize();
    await _plugin.cancelAll();
  }

  int _notificationId(ReminderChannel channel, String key) {
    final seed = '${channel.name}::$key';
    final hash = seed.hashCode;
    return hash & 0x7fffffff;
  }
}
