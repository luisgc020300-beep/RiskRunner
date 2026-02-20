import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// 1. IMPORTANTE: El nombre del paquete DEBE estar en minúsculas. 
// Si tu proyecto se llama MI_APP, en el pubspec.yaml suele aparecer como mi_app.
import 'package:RunnerRisk/main.dart';
void main() {
  // Esta línea ayuda a que los tests no fallen con plugins de Firebase
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LoginScreen basic UI test', (WidgetTester tester) async {
    // 1. Construimos la app (MyApp es la clase de tu main.dart)
    // Si MyApp no tiene un constructor 'const', quita la palabra 'const'
    await tester.pumpWidget(const MyApp());

    // 2. pumpAndSettle espera a que todas las animaciones y el StreamBuilder terminen
    await tester.pumpAndSettle();

    // 3. Verificaciones de la interfaz de LoggingScreen
    
    // Verificamos el nombre de la app (ajusta a 'Runner Risk' si lleva espacio)
    expect(find.textContaining('RunnerRisk'), findsWidgets);

    // Verificamos que existan campos de texto para el login
    expect(find.byType(TextField), findsAtLeastNWidgets(1));

    // Verificamos el botón (asegúrate de que el texto sea exacto al de Logging.dart)
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}