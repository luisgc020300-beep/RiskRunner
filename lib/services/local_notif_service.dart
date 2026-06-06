import 'package:flutter/material.dart' show Color;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class LocalNotifService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _chRacha    = 'riskrunner_racha';
  static const _chSemanal  = 'riskrunner_semanal';
  static const _chInvasion = 'riskrunner_invasion';
  static const _chReto     = 'riskrunner_reto';
  static const _idRacha    = 1001;
  static const _idSemanal  = 1002;
  static const _idInvasion = 1003;
  static const _idReto     = 1004;

  static bool _initialized = false;

  // ── Init ──────────────────────────────────────────────────────────────────
  static Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios     = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _initialized = true;
  }

  // ── Racha en riesgo ───────────────────────────────────────────────────────
  /// Programa un aviso a las 20:00 de hoy (o mañana si ya pasaron) con la racha.
  static Future<void> programarRachaEnRiesgo(int racha) async {
    if (racha <= 0) return;
    await _plugin.cancel(_idRacha);

    final ahora = tz.TZDateTime.now(tz.local);
    var objetivo = tz.TZDateTime(
        tz.local, ahora.year, ahora.month, ahora.day, 20, 0);
    if (objetivo.isBefore(ahora)) {
      objetivo = objetivo.add(const Duration(days: 1));
    }

    try {
      await _plugin.zonedSchedule(
        _idRacha,
        '¡Tu racha de $racha días está en riesgo!',
        'Sal a correr antes de medianoche para mantenerla.',
        objetivo,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _chRacha, 'Racha diaria',
            channelDescription: 'Recordatorio cuando tu racha está en riesgo',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFFE02020),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('LocalNotifService.programarRachaEnRiesgo: $e');
    }
  }

  /// Cancela el aviso de racha (llamar al iniciar una carrera).
  static Future<void> cancelarRecordatorioRacha() async {
    await _plugin.cancel(_idRacha);
  }

  // ── Resumen semanal ───────────────────────────────────────────────────────
  /// Programa un resumen el próximo lunes a las 9:00 con las stats de la semana.
  static Future<void> programarResumenSemanal({
    required double kmSemana,
    required int carreras,
    required int territorios,
  }) async {
    await _plugin.cancel(_idSemanal);

    final ahora      = tz.TZDateTime.now(tz.local);
    final diasLunes  = (8 - ahora.weekday) % 7;
    final offsetDias = diasLunes == 0 ? 7 : diasLunes;
    final lunes      = tz.TZDateTime(
        tz.local,
        ahora.year, ahora.month, ahora.day + offsetDias,
        9, 0);

    final body = kmSemana > 0
        ? '${kmSemana.toStringAsFixed(1)} km · $carreras ${carreras == 1 ? 'carrera' : 'carreras'} · $territorios ${territorios == 1 ? 'territorio' : 'territorios'}'
        : 'Esta semana sin actividad. ¡Empieza hoy!';

    try {
      await _plugin.zonedSchedule(
        _idSemanal,
        'Tu semana en RiskRunner',
        body,
        lunes,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _chSemanal, 'Resumen semanal',
            channelDescription: 'Resumen de actividad cada lunes',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('LocalNotifService.programarResumenSemanal: $e');
    }
  }

  // ── Invasión de territorio ────────────────────────────────────────────────
  /// Dispara una notificación inmediata cuando un rival conquista un territorio.
  static Future<void> notificarInvasion({
    required String territorio,
    required String rival,
  }) async {
    try {
      await _plugin.show(
        _idInvasion,
        '¡Territorio perdido!',
        '$rival ha conquistado $territorio',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _chInvasion, 'Invasiones',
            channelDescription: 'Alertas cuando pierdes un territorio',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            color: Color(0xFFE02020),
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('LocalNotifService.notificarInvasion: $e');
    }
  }

  // ── Reto completado ───────────────────────────────────────────────────────
  /// Dispara una notificación inmediata al completar un reto.
  static Future<void> notificarRetoCumplido(String nombreReto) async {
    try {
      await _plugin.show(
        _idReto,
        '¡Reto completado!',
        nombreReto,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _chReto, 'Logros y retos',
            channelDescription: 'Notificaciones de retos completados',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@mipmap/ic_launcher',
            color: Color(0xFFFFD60A),
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('LocalNotifService.notificarRetoCumplido: $e');
    }
  }
}
