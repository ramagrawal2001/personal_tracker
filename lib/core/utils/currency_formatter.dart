import 'package:intl/intl.dart';

class CurrencyFormatter {
  // Active symbol — updated via [updateSymbol] by FinanceNotifier at startup
  // and whenever the user changes their currency preference.
  static String _symbol = '₹';

  // Lazily built formatters; rebuilt whenever the symbol changes.
  static NumberFormat _formatter = _buildFormatter(_symbol, 0);
  static NumberFormat _decimalFormatter = _buildFormatter(_symbol, 2);

  /// Called by [FinanceNotifier] once prefs are loaded and on every
  /// [setCurrencySymbol] call. Rebuilds the cached formatters immediately
  /// so all subsequent [format] / [compact] calls use the new symbol.
  static void updateSymbol(String symbol) {
    if (symbol == _symbol) return;
    _symbol = symbol;
    _formatter = _buildFormatter(symbol, 0);
    _decimalFormatter = _buildFormatter(symbol, 2);
  }

  static NumberFormat _buildFormatter(String symbol, int decimalDigits) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: symbol,
      decimalDigits: decimalDigits,
    );
  }

  /// Returns the currently active currency symbol.
  static String get symbol => _symbol;

  /// Format a double to currency notation, e.g. ₹1,52,300 or -₹22,34,430.
  /// Pass [showDecimals] for two decimal places.
  static String format(double amount, {bool showDecimals = false}) {
    final absAmount = amount.abs();
    final formatted = (showDecimals ? _decimalFormatter : _formatter).format(absAmount);
    return amount < 0 ? '-$formatted' : formatted;
  }

  /// Compact representation: ₹1.50 Cr, ₹2.50 L, ₹25.0 k, etc.
  static String compact(double amount) {
    final sym = _symbol;
    if (amount.abs() >= 10000000) {
      return '$sym${(amount / 10000000).toStringAsFixed(2)} Cr';
    } else if (amount.abs() >= 100000) {
      return '$sym${(amount / 100000).toStringAsFixed(2)} L';
    } else if (amount.abs() >= 1000) {
      return '$sym${(amount / 1000).toStringAsFixed(1)} k';
    }
    return format(amount);
  }
}
