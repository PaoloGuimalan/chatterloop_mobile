// Centralizes the hex literals repeated across auth/profile screens
// (previously each screen redefined Color(0xFF1c7def) etc. inline).
// Not a full theming system - just named constants for the screens built
// or reworked in this pass.

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const brand = Color(0xFF1c7def);
  static const brandSoft = Color(0xffc7daff);
  static const surface = Color(0xfff0f2f5);
  static const card = Color(0xffdfdfdf);
  static const border = Color(0xffd2d2d2);
  static const textPrimary = Color(0xFF565656);
  static const danger = Color(0xffff6675);
  static const white = Colors.white;
}
