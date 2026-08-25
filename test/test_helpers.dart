import 'package:aspyric/core/database/app_database.dart';
import 'package:aspyric/core/database/finance_repository.dart';
import 'package:drift/native.dart';

/// A [FinanceNotifier] backed by an in-memory database with auto-load
/// disabled, so tests get a clean, purely in-memory, synchronous notifier
/// without racing an async DB read against the test body.
FinanceNotifier createTestFinanceNotifier() {
  return FinanceNotifier(
    AppDatabase.forTesting(NativeDatabase.memory()),
    autoLoad: false,
  );
}
