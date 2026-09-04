import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'payment_reminders.dart';

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
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(settings);
    _ready = true;
  }

  static Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return true;
  }

  static Future<void> scheduleDailyReminder({
    int hour = 21,
    int minute = 0,
  }) async {
    if (kIsWeb) return;
    await _plugin.cancelAll();
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

    await _plugin.zonedSchedule(
      _kDailyReminderId,
      '💰 Aspyric — Daily Update',
      'Don\'t forget to log today\'s transactions!',
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.wallClockTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifEnabled, true);
    await prefs.setInt(_kNotifHour, hour);
    await prefs.setInt(_kNotifMinute, minute);
  }

  static Future<void> cancelReminder() async {
    if (kIsWeb) return;
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
        await _plugin.zonedSchedule(
          s.id,
          s.title,
          s.body,
          when,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.wallClockTime,
        );
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
