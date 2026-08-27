import 'package:flutter/material.dart';

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  static EdgeInsets symmetric({
    double horizontal = lg,
    double vertical = md,
  }) =>
      EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);

  static EdgeInsets all(double value) => EdgeInsets.all(value);

  static EdgeInsets only({
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 0,
  }) =>
      EdgeInsets.only(left: left, top: top, right: right, bottom: bottom);

  static double responsive(BuildContext context, {
    double mobile = lg,
    double tablet = xl,
    double desktop = xxl,
  }) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 900) return desktop;
    if (width >= 600) return tablet;
    return mobile;
  }
}