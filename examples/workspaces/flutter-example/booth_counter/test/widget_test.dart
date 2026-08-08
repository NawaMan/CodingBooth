// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// A real widget test, run by `flutter test` — which is the point: it exercises
// the Flutter test runner and the framework, not just the compiler.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:booth_counter/main.dart';

void main() {
  testWidgets('the counter starts at zero and increments on tap',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BoothCounterApp());

    expect(find.text('Booth counter'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}
