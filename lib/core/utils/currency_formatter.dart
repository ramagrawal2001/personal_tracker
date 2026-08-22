import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _inrFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static final NumberFormat _inrDecimalFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  /// Format double amount to Indian Rupee notation, e.g., ₹1,52,300 or -₹22,34,430
  static String format(double amount, {bool showDecimals = false, String symbol = '₹'}) {
    final absAmount = amount.abs();
    final formatter = showDecimals ? _inrDecimalFormatter : _inrFormatter;
    final formattedAbs = formatter.format(absAmount);
    
    if (amount < 0) {
      return '-$formattedAbs';
    }
    return formattedAbs;
  }


  /// Compact representation: 1.5L, 25K, 4.2M
  static String compact(double amount, {String symbol = '₹'}) {
    if (amount.abs() >= 10000000) {
      return '$symbol${(amount / 10000000).toStringAsFixed(2)} Cr';
    } else if (amount.abs() >= 100000) {
      return '$symbol${(amount / 100000).toStringAsFixed(2)} L';
    } else if (amount.abs() >= 1000) {
      return '$symbol${(amount / 1000).toStringAsFixed(1)} k';
    }
    return format(amount);
  }
}
