// test/widget_test.dart
//
// Tests de widget básicos que NO requieren Firebase.
// Los tests de pantallas que usan Firebase (LiveActivity, FullscreenMap, etc.)
// se hacen a nivel de servicio con FakeFirebaseFirestore en /services/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── Smoke test: MaterialApp renderiza sin errores ──────────────────────────
  testWidgets('MaterialApp con texto renderiza correctamente', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('RiskRunner')),
      ),
    );
    expect(find.text('RiskRunner'), findsOneWidget);
  });

  // ── Smoke test: tema oscuro/claro ──────────────────────────────────────────
  testWidgets('tema dark no lanza excepciones', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme:     ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: ThemeMode.dark,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
