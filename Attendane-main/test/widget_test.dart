// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myproject2/main.dart';

void main() {
  testWidgets('Attendance Plus app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AttendancePlusApp()); // เปลี่ยนจาก MyApp() เป็น AttendancePlusApp()

    // Verify that the login screen shows
    expect(find.text('Attendance Plus'), findsOneWidget);
    expect(find.text('Sign in to continue'), findsOneWidget);

    // Test login form exists
    expect(find.byType(TextFormField), findsAtLeast(2)); // Email and password fields
    expect(find.text('Login'), findsOneWidget);
  });
}