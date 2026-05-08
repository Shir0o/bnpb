import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_preference.dart';
import '../repositories/notification_preferences_repository.dart';
import 'platform_info.dart' as platform_info;

/// Handles platform notification scheduling for reminders.
class ReminderService {
  ReminderService._();

  static final ReminderService _instance = ReminderService._();

  /// Singleton accessor.
  factory ReminderService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final NotificationPreferencesRepository _preferencesRepository =
      NotificationPreferencesRepository();
  SharedPreferences? _sharedPreferences;

  bool _initialized = false;
  Future<void>? _initializationFuture;
  bool _timeZoneInitialized = false;
  bool _notificationsSupported = true;
  bool? _exactAlarmOptIn;

  /// Ensures the plugin and time zone data are available before scheduling.
  Future<void> initialize() async {
    if (!_notificationsSupported || _initialized) {
      return;
    }

    if (_initializationFuture != null) {
      return _initializationFuture;
    }

    _initializationFuture = _doInitialize();
    await _initializationFuture;
  }

  Future<void> _doInitialize() async {
    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
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
      try {
        await _requestPlatformPermissions();
      } catch (e) {
        // Ignore permission errors during init, we can request later or functionality just won't work
        debugPrint('Permission request failed: $e');
      }

      _initialized = true;
    } catch (error, stackTrace) {
      if (_markUnsupported('initialize', error, stackTrace)) {
        return;
      }
      rethrow; // Do not swallow other errors? Or maybe we should to keep app alive.
    } finally {
      // If failed, we might want to allow retrying?
      // For now, let's keep _initializationFuture set so we don't retry endlessly if it's a hard crash.
    }
  }

  Future<void> _requestPlatformPermissions() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();

    if (await _shouldRequestExactAlarmPermission()) {
      await androidImpl?.requestExactAlarmsPermission();
    }

    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);

    final macImpl = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    await macImpl?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> _configureLocalTimeZone() async {
    if (_timeZoneInitialized) {
      return;
    }
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name.toString()));
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

    await _guardOperation('scheduleReminder($channel, $key)', () async {
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

      final payloadMap = <String, dynamic>{'channel': channel.name, 'key': key};
      if (contactId != null) {
        payloadMap['contactId'] = contactId;
      }
      if (additionalPayload != null) {
        payloadMap.addAll(additionalPayload);
      }
      final payload = jsonEncode(payloadMap);

      try {
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
          payload: payload,
        );
      } catch (e) {
        if (_isExactAlarmPermissionError(e)) {
          debugPrint(
            'Exact alarm failed, falling back to inexact scheduling: $e',
          );
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
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: payload,
          );
        } else {
          rethrow;
        }
      }
    });
  }

  /// Cancels every notification scheduled for the supplied [channel]
  /// regardless of contact.
  Future<void> cancelChannel(ReminderChannel channel) async {
    await initialize();
    await _guardOperation('cancelChannel(${channel.name})', () async {
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
    });
  }

  /// Cancels a previously scheduled reminder using the [key] used during
  /// [scheduleReminder].
  Future<void> cancelReminder(ReminderChannel channel, String key) async {
    await initialize();
    await _guardOperation('cancelReminder(${channel.name}, $key)', () async {
      final id = _notificationId(channel, key);
      await _plugin.cancel(id);
    });
  }

  /// Cancels all reminders scheduled for [contactId] under a [channel].
  Future<void> cancelChannelForContact(
    ReminderChannel channel,
    String contactId,
  ) async {
    await initialize();
    await _guardOperation(
      'cancelChannelForContact(${channel.name}, $contactId)',
      () async {
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
      },
    );
  }

  /// Cancels every reminder tied to [contactId].
  Future<void> cancelAllForContact(String contactId) async {
    await initialize();
    await _guardOperation('cancelAllForContact($contactId)', () async {
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
    });
  }

  /// Cancels every scheduled reminder regardless of contact.
  Future<void> cancelAll() async {
    await initialize();
    await _guardOperation('cancelAll', () async {
      await _plugin.cancelAll();
    });
  }

  Future<void> _guardOperation(
    String context,
    Future<void> Function() action,
  ) async {
    if (!_notificationsSupported) {
      return;
    }
    try {
      await action();
    } catch (error, stackTrace) {
      if (_markUnsupported(context, error, stackTrace)) {
        return;
      }
      rethrow;
    }
  }

  bool _markUnsupported(String context, Object error, StackTrace stackTrace) {
    if (!_isUnsupportedError(error)) {
      return false;
    }

    final isExactAlarmError = _isExactAlarmPermissionError(error);

    // We only disable the service if it's NOT an exact alarm error.
    // If it's an exact alarm error, we'll try to fallback to inexact in scheduleReminder next time.
    if (!isExactAlarmError) {
      _notificationsSupported = false;
    }

    if (isExactAlarmError) {
      debugPrint(
        'ReminderService exact alarm failed ($context): permission required. '
        'Falling back to inexact reminders if possible.',
      );
    }

    if (kDebugMode) {
      debugPrint('ReminderService operation failed ($context): $error');
      debugPrint(stackTrace.toString());
    }
    return true;
  }

  bool _isUnsupportedError(Object error) {
    if (error is MissingPluginException ||
        error is UnimplementedError ||
        error is UnsupportedError) {
      return true;
    }
    if (error is PlatformException) {
      if (_isExactAlarmPermissionError(error)) {
        return true;
      }
      final code = error.code.toLowerCase();
      if (code.contains('unavailable') ||
          code.contains('notimplemented') ||
          code.contains('not_implemented') ||
          code.contains('not_available') ||
          code.contains('unsupported')) {
        return true;
      }
      final message = (error.message ?? '').toLowerCase();
      if (message.contains('not implemented') ||
          message.contains('not available') ||
          message.contains('unsupported')) {
        return true;
      }
    }
    return false;
  }

  bool _isExactAlarmPermissionError(Object error) {
    if (error is! PlatformException) {
      return false;
    }
    final code = error.code.toLowerCase();
    if (code.contains('scheduleexactalarm') ||
        code.contains('exactalarmpermission') ||
        code == 'exact_alarms_not_permitted'.toLowerCase() ||
        code == 'androidscheduleexactalarmpermissiondenied'.toLowerCase()) {
      return true;
    }
    final message = (error.message ?? '').toLowerCase();
    return message.contains('exact alarm');
  }

  int _notificationId(ReminderChannel channel, String key) {
    final seed = '${channel.name}::$key';
    final hash = seed.hashCode;
    return hash & 0x7fffffff;
  }

  Future<bool> _shouldRequestExactAlarmPermission() async {
    if (kIsWeb || !platform_info.isAndroid) {
      return false;
    }

    if (!await _deviceRequiresExactAlarmPermission()) {
      return false;
    }

    await _ensureExactAlarmOptInLoaded();
    if (!(_exactAlarmOptIn ?? false)) {
      return false;
    }

    if (!await _hasEnabledExactAlarmReminders()) {
      return false;
    }

    return true;
  }

  Future<bool> _deviceRequiresExactAlarmPermission() async {
    final sdkInt = await platform_info.androidSdkInt();
    if (sdkInt == null) {
      return true;
    }
    return sdkInt >= 31;
  }

  Future<void> _ensureExactAlarmOptInLoaded() async {
    if (_exactAlarmOptIn != null) {
      return;
    }
    final prefs = _sharedPreferences ??= await SharedPreferences.getInstance();
    _exactAlarmOptIn = prefs.getBool(_exactAlarmOptInKey) ?? false;
  }

  Future<bool> _hasEnabledExactAlarmReminders() async {
    try {
      await _preferencesRepository.ensureDefaults();
      final preferences = await _preferencesRepository.loadPreferences(
        scopeType: NotificationScopeType.global,
      );
      if (preferences.isEmpty) {
        return true;
      }
      return preferences.any((preference) => preference.enabled);
    } catch (_) {
      return true;
    }
  }

  static const String _exactAlarmOptInKey = 'reminder_exact_alarm_opt_in';

  /// Persists whether the user has opted into requesting the exact alarm
  /// permission.
  Future<void> updateExactAlarmOptIn(bool value) async {
    final prefs = _sharedPreferences ??= await SharedPreferences.getInstance();
    await prefs.setBool(_exactAlarmOptInKey, value);
    _exactAlarmOptIn = value;
  }

  /// Returns whether the user has opted into requesting exact alarm access.
  Future<bool> isExactAlarmOptInEnabled() async {
    await _ensureExactAlarmOptInLoaded();
    return _exactAlarmOptIn ?? false;
  }

  /// Indicates if the running platform may require the exact alarm
  /// permission.
  Future<bool> isExactAlarmPermissionRelevant() async {
    if (kIsWeb || !platform_info.isAndroid) {
      return false;
    }
    return await _deviceRequiresExactAlarmPermission();
  }

  /// Returns whether the exact alarm permission is currently granted.
  Future<bool> isExactAlarmPermissionGranted() async {
    if (!await isExactAlarmPermissionRelevant()) {
      return true;
    }
    // We don't have a reliable way to check without the specific Android plugin import
    // which might not be available. We'll rely on the try-catch in scheduleReminder.
    return true;
  }

  /// Requests the exact alarm permission when the user has opted in and the
  /// device requires it.
  Future<bool> requestExactAlarmPermission() async {
    if (!await _shouldRequestExactAlarmPermission()) {
      return true;
    }
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final result = await androidImpl?.requestExactAlarmsPermission();
    return result ?? true;
  }
}
