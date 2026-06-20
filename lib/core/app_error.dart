// lib/core/app_error.dart
//
// Helper centralizado para errores de usuario y reporting a Crashlytics.
// Reemplaza los 12+ ScaffoldMessenger.showSnackBar duplicados en la app.
//
// USO:
//   AppError.show(context, 'No se pudo guardar la ruta');
//   AppError.record(e, st, reason: 'conquista_fallida');
//   AppError.log('Usuario abrió pantalla de mapa');
//
// En debug: solo imprime por consola, sin enviar a Crashlytics.
// En prod:  reporta a Crashlytics + muestra SnackBar al usuario si hay context.

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AppError {
  AppError._();

  // ── Identificación de usuario ─────────────────────────────────────────────

  static Future<void> setUser(String uid, {String? email}) async {
    if (kDebugMode) return;
    await FirebaseCrashlytics.instance.setUserIdentifier(uid);
    if (email != null) {
      await FirebaseCrashlytics.instance.setCustomKey('email', email);
    }
  }

  static Future<void> clearUser() async {
    if (kDebugMode) return;
    await FirebaseCrashlytics.instance.setUserIdentifier('');
  }

  // ── Custom keys — visibles en el panel de Crashlytics ────────────────────

  static Future<void> setKey(String key, Object value) async {
    if (kDebugMode) return;
    await FirebaseCrashlytics.instance.setCustomKey(key, value);
  }

  // ── Breadcrumbs — aparecen en la línea de tiempo del crash ───────────────

  static void log(String message) {
    if (kDebugMode) {
      debugPrint('[CRUMB] $message');
      return;
    }
    FirebaseCrashlytics.instance.log(message);
  }

  // ── Errores no fatales ───────────────────────────────────────────────────

  /// Reporta un error no fatal a Crashlytics.
  /// [reason] aparece en el título del issue en el panel.
  static void record(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) {
    if (kDebugMode) {
      debugPrint('⚠️  AppError${reason != null ? '[$reason]' : ''}: $error');
      if (stack != null) debugPrintStack(stackTrace: stack);
      return;
    }
    FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      reason: reason,
      fatal: fatal,
    );
  }

  // ── SnackBar de error — reemplaza los 12 ScaffoldMessenger duplicados ────

  /// Muestra un SnackBar de error al usuario.
  /// Si [error] y [stack] se proporcionan, también reporta a Crashlytics.
  static void show(
    BuildContext context,
    String mensaje, {
    Object? error,
    StackTrace? stack,
    String? reason,
  }) {
    if (error != null) record(error, stack, reason: reason);

    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            mensaje,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          backgroundColor: const Color(0xFF2C1A1A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: AppColors.red.withValues(alpha: 0.4)),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  /// Variante de información (no es error, no reporta a Crashlytics).
  static void showInfo(BuildContext context, String mensaje) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            mensaje,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          backgroundColor: const Color(0xFF1C2A1C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFF2A5C2A)),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          duration: const Duration(seconds: 3),
        ),
      );
  }
}
