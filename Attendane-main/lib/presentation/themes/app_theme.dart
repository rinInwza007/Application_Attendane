import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      primarySwatch: Colors.purple,
      primaryColor: Colors.purple.shade400,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}