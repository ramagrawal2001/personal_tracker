import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'payment_reminders.dart';
import 'smart_entry/native_capture_bridge.dart';

const _kNotifEnabled = 'daily_reminder_enabled';
const _kNotifHour = 'daily_reminder_hour';
const _kNotifMinute = 'daily_reminder_minute';
const _kPayRemEnabled = 'payment_reminders_enabled';
const _kPayRemIds = 'payment_reminder_ids';
const _kDailyReminderId = 0;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// True only after a successful [init]. Every scheduling call no-ops until
  /// then, so `flutter test` (which never calls init) can't hit the plugin.
  static bool _ready = false;

  static Future<void> init() async {
    if (kIsWeb) return; // Web doesn't support local notifications
    tz.initializeTimeZones();
    // Without this `tz.local` stays UTC, so a "21:00" reminder fired at
    // 21:00 UTC (02:30 IST) and every due-date reminder was 5½h off.
    await _setLocalTimezone();
    const androidSettings = AndroidInitializationSettings('@drawable/ic_stat_aspyric');
    // Permission is requested explicitly (see [requestPermission]) once the
    // user is signed in, rather than as a surprise on the splash screen.
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(settings);
    _ready = true;

    // Re-arm the daily reminder with the corrected local timezone (older
    // builds scheduled it in UTC) — cheap and idempotent.
    try {
      if (await isEnabled()) {
        await scheduleDailyReminder(hour: await getReminderHour(), minute: await getReminderMinute());
      }
    } catch (e) {
      debugPrint('NotificationService: re-arming daily reminder failed: $e');
    }
  }

  static Future<void> _setLocalTimezone() async {
    try {
      final name = await NativeCaptureBridge.localTimezone();
      if (name != null && name.isNotEmpty) {
        tz.setLocalLocation(tz.getLocation(name));
        return;
      }
    } catch (e) {
      debugPrint('NotificationService: timezone lookup failed: $e');
    }
    // Fallback: any zone with the device's current UTC offset.
    final offset = DateTime.now().timeZoneOffset;
    for (final loc in tz.timeZoneDatabase.locations.values) {
      if (loc.currentTimeZone.offset == offset.inMilliseconds) {
        tz.setLocalLocation(loc);
        return;
      }
    }
  }

  /// Exact alarms can be denied on Android 12+ (and are revocable by the
  /// user). Falling back to an inexact alarm still delivers the reminder,
  /// just within a few minutes, instead of throwing and scheduling nothing.
  static Future<void> _zonedSchedule(
    int id,
    String title,
    String body,
    tz.TZDateTime when,
    NotificationDetails details, {
    DateTimeComponents? match,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id, title, body, when, details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.wallClockTime,
        matchDateTimeComponents: match,
      );
    } catch (e) {
      debugPrint('NotificationService: exact alarm failed ($e), using inexact');
      await _plugin.zonedSchedule(
        id, title, body, when, details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.wallClockTime,
        matchDateTimeComponents: match,
      );
    }
  }

  static Future<bool> requestPermission() async {
    if (kIsWeb || !_ready) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission() ?? false;
      // Android 14+ denies exact alarms by default for new installs unless
      // USE_EXACT_ALARM applies; ask once so reminders fire on the minute.
      try {
        await android.requestExactAlarmsPermission();
      } catch (_) {/* older plugin / OS — inexact fallback covers it */}
      return granted;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    return true;
  }

  static const _kAskedPermission = 'notif_permission_asked_v1';

  /// Asks for notification permission once per install, after sign-in, and
  /// re-schedules everything if it was granted. Before this nothing ever
  /// asked on Android 13+ unless the user happened to toggle the daily
  /// reminder — so payment reminders were silently never shown.
  static Future<void> ensurePermissionOnce() async {
    if (kIsWeb || !_ready) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kAskedPermission) ?? false) return;
    await prefs.setBool(_kAskedPermission, true);
    await requestPermission();
  }

  /// Fires a notification right now — used by Settings → "Send test
  /// notification" so the user can confirm notifications actually work.
  static Future<bool> showTest() async {
    if (kIsWeb || !_ready) return false;
    final granted = await requestPermission();
    await _plugin.show(
      999001,
      '✅ Aspyric notifications work',
      'Reminders will show up like this.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder',
          'Daily Reminder',
          channelDescription: 'Reminds you to log daily transactions',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
    return granted;
  }

  /// Number of reminders currently queued with the OS (diagnostics).
  static Future<int> pendingCount() async {
    if (kIsWeb || !_ready) return 0;
    return (await _plugin.pendingNotificationRequests()).length;
  }

  static Future<void> scheduleDailyReminder({
    int hour = 21,
    int minute = 0,
  }) async {
    if (kIsWeb || !_ready) return;
    // Only replace the daily reminder itself — this used to be cancelAll(),
    // which also wiped every scheduled card / EMI / bill reminder.
    await _plugin.cancel(_kDailyReminderId);
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'daily_reminder',
      'Daily Reminder',
      channelDescription: 'Reminds you to log daily transactions',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _zonedSchedule(
      _kDailyReminderId,
      '💰 Aspyric — Daily Update',
      'Don\'t forget to log today\'s transactions!',
      scheduled,
      details,
      match: DateTimeComponents.time,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifEnabled, true);
    await prefs.setInt(_kNotifHour, hour);
    await prefs.setInt(_kNotifMinute, minute);
  }

  static Future<void> cancelReminder() async {
    if (kIsWeb || !_ready) return;
    await _plugin.cancel(_kDailyReminderId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifEnabled, false);
  }

  // ── Payment reminders (cards / loans / recurring) ────────────────────────

  static Future<bool> paymentRemindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPayRemEnabled) ?? true; // on by default
  }

  static Future<void> setPaymentRemindersEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPayRemEnabled, value);
    if (!value) await cancelPaymentReminders();
  }

  /// Cancels the previously-scheduled payment reminders (ids remembered in
  /// prefs, since deleted entities can't be re-derived).
  static Future<void> cancelPaymentReminders() async {
    if (kIsWeb || !_ready) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPayRemIds);
    if (raw != null) {
      try {
        for (final id in (jsonDecode(raw) as List).cast<int>()) {
          await _plugin.cancel(id);
        }
      } catch (_) {/* ignore */}
    }
    await prefs.remove(_kPayRemIds);
  }

  /// Replaces all payment reminders with [specs] (already computed by
  /// [PaymentReminders.compute]). No-ops on web, before [init], or when the
  /// user turned payment reminders off.
  static Future<void> schedulePaymentReminders(List<ReminderSpec> specs) async {
    if (kIsWeb || !_ready) return;
    if (!await paymentRemindersEnabled()) {
      await cancelPaymentReminders();
      return;
    }
    await cancelPaymentReminders();

    const androidDetails = AndroidNotificationDetails(
      'payment_reminders',
      'Payment reminders',
      channelDescription: 'Credit-card statement & due dates, EMIs, recurring bills',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    final now = tz.TZDateTime.now(tz.local);
    final scheduledIds = <int>[];
    for (final s in specs) {
      final when = tz.TZDateTime.from(s.when, tz.local);
      if (!when.isAfter(now)) continue;
      try {
        await _zonedSchedule(s.id, s.title, s.body, when, details);
        scheduledIds.add(s.id);
      } catch (_) {/* one bad spec shouldn't drop the rest */}
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPayRemIds, jsonEncode(scheduledIds));
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kNotifEnabled) ?? false;
  }

  static Future<int> getReminderHour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kNotifHour) ?? 21;
  }

  static Future<int> getReminderMinute() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kNotifMinute) ?? 0;
  }
}
