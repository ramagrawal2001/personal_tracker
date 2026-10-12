import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Something the OS asked the app to do: open Quick Add from a widget / app
/// shortcut / quick-settings tile, review a capture, or ingest shared text /
/// an image. Delivered as `aspyric://<host>?<query>` links.
class LaunchAction {
  /// `add`, `voice`, `scan`, `capture`, `inbox`, `image`.
  final String kind;
  final Map<String, String> params;
  const LaunchAction(this.kind, [this.params = const {}]);

  static LaunchAction? fromUri(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'aspyric') return null;
    final kind = uri.host.isNotEmpty ? uri.host : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
    if (kind.isEmpty) return null;
    return LaunchAction(kind, uri.queryParameters);
  }

  static LaunchAction? fromMap(Object? raw) {
    if (raw is String) return fromUri(raw);
    if (raw is! Map) return null;
    final kind = raw['kind']?.toString();
    if (kind == null) return null;
    return LaunchAction(kind, {
      for (final e in raw.entries)
        if (e.key != 'kind' && e.value != null) e.key.toString(): e.value.toString(),
    });
  }

  @override
  String toString() => 'LaunchAction($kind, $params)';
}

/// A raw money message captured natively (Android SMS receiver /
/// notification listener) while the app may not have been running.
class RawCapture {
  final String id;
  final String source; // 'sms' | 'notification'
  final String body;
  final String? sender;
  final DateTime receivedAt;

  const RawCapture({required this.id, required this.source, required this.body, this.sender, required this.receivedAt});

  static RawCapture? fromMap(Map m) {
    final body = m['body']?.toString();
    if (body == null || body.trim().isEmpty) return null;
    final ts = m['ts'];
    return RawCapture(
      id: m['id']?.toString() ?? '${m['source']}-${ts ?? body.hashCode}',
      source: m['source']?.toString() ?? 'sms',
      body: body,
      sender: m['sender']?.toString(),
      receivedAt: ts is int ? DateTime.fromMillisecondsSinceEpoch(ts) : DateTime.now(),
    );
  }
}

/// Dart side of the `com.aspyric.app/capture` platform channel implemented in
/// MainActivity.kt (Android) and AppDelegate.swift (iOS). Every call is
/// defensive: on an unsupported platform (web, desktop, tests) it no-ops.
class NativeCaptureBridge {
  NativeCaptureBridge._();

  static const _channel = MethodChannel('com.aspyric.app/capture');
  static final _actions = StreamController<LaunchAction>.broadcast();
  static bool _wired = false;

  /// Actions that arrived while nothing was listening (e.g. the app was on
  /// the biometric lock screen, which unmounts the shell). Replayed by
  /// [takeBufferedActions] once the shell is back.
  static final List<LaunchAction> _buffered = [];

  static void _emit(LaunchAction a) {
    if (_actions.hasListener) {
      _actions.add(a);
    } else {
      _buffered.add(a);
    }
  }

  static List<LaunchAction> takeBufferedActions() {
    final out = List<LaunchAction>.from(_buffered);
    _buffered.clear();
    return out;
  }

  static bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isIOS => !kIsWeb && Platform.isIOS;

  /// Actions arriving while the app is already running.
  static Stream<LaunchAction> get actions {
    _wire();
    return _actions.stream;
  }

  static void _wire() {
    if (_wired || !_supported) return;
    _wired = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAction') {
        final a = LaunchAction.fromMap(call.arguments);
        if (a != null) _emit(a);
      } else if (call.method == 'onCaptured') {
        if (_actions.hasListener) _actions.add(const LaunchAction('captured'));
      }
      return null;
    });
  }

  static Future<T?> _invoke<T>(String method, [Object? args]) async {
    if (!_supported) return null;
    _wire();
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('NativeCaptureBridge.$method failed: ${e.message}');
      return null;
    }
  }

  /// The action that cold-started the app (consumed once).
  static Future<LaunchAction?> takeInitialAction() async =>
      LaunchAction.fromMap(await _invoke<Object>('takeInitialAction'));

  /// Drains messages queued natively since the last call.
  static Future<List<RawCapture>> drainCaptured() async {
    final raw = await _invoke<List<Object?>>('drainCaptured');
    if (raw == null) return const [];
    return raw.whereType<Map>().map(RawCapture.fromMap).whereType<RawCapture>().toList();
  }

  /// IANA timezone of the device ("Asia/Kolkata"), for notification scheduling.
  static Future<String?> localTimezone() => _invoke<String>('localTimezone');

  // ── Android-only capture controls ────────────────────────────────────
  /// False on iOS and on the default ("standard") Android release APK, which
  /// leaves out the SMS / notification-listener permissions so Google Play
  /// Protect doesn't block sideloading it.
  static Future<bool> captureSupported() async => await _invoke<bool>('captureSupported') ?? false;

  static Future<bool> hasSmsPermission() async => await _invoke<bool>('hasSmsPermission') ?? false;
  static Future<bool> requestSmsPermission() async => await _invoke<bool>('requestSmsPermission') ?? false;

  /// Reads recent bank-looking SMS from the inbox (last [days] days).
  static Future<List<RawCapture>> scanSmsInbox({int days = 7}) async {
    final raw = await _invoke<List<Object?>>('scanSmsInbox', {'days': days});
    if (raw == null) return const [];
    return raw.whereType<Map>().map(RawCapture.fromMap).whereType<RawCapture>().toList();
  }

  static Future<bool> notificationAccessEnabled() async => await _invoke<bool>('notificationAccessEnabled') ?? false;
  static Future<void> openNotificationAccessSettings() => _invoke('openNotificationAccessSettings');

  /// Capture on/off switches the native receivers read even when Flutter
  /// isn't running.
  static Future<void> setCaptureEnabled({required bool sms, required bool notifications}) =>
      _invoke('setCaptureEnabled', {'sms': sms, 'notifications': notifications});

  /// Pushes numbers to the Android home-screen widget.
  static Future<void> updateWidget({required String todaySpent, required int pending}) =>
      _invoke('updateWidget', {'todaySpent': todaySpent, 'pending': pending});

  /// Pins the widget to the home screen (Android 8+ launchers that support it).
  static Future<bool> requestPinWidget() async => await _invoke<bool>('requestPinWidget') ?? false;

  /// Adds the quick-settings tile (Android 13+).
  static Future<bool> requestAddTile() async => await _invoke<bool>('requestAddTile') ?? false;

  /// On-device OCR of an image file (ML Kit on Android, Vision on iOS).
  static Future<String?> recognizeText(String path) => _invoke<String>('recognizeText', {'path': path});
}
