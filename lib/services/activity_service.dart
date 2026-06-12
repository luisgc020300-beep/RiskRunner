// lib/services/activity_service.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_notif_service.dart';

// ── Modelo de una entrada del feed ────────────────────────────────────────────
class ActivityEntry {
  final String userNick;
  final String territoryId;
  final String territoryName;
  final String mode; // 'competitivo' | 'solitario'
  final DateTime timestamp;
  final String? previousOwnerNick;
  final int fromColorValue;

  const ActivityEntry({
    required this.userNick,
    required this.territoryId,
    required this.territoryName,
    required this.mode,
    required this.timestamp,
    this.previousOwnerNick,
    this.fromColorValue = 0xFFCC2222,
  });

  Color get color => Color(fromColorValue);

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}min';
    if (diff.inHours < 24)   return 'hace ${diff.inHours}h';
    return 'hace ${diff.inDays}d';
  }

  factory ActivityEntry.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return ActivityEntry(
      userNick:          d['userNick'] as String? ?? d['fromNickname'] as String? ?? '?',
      territoryId:       d['territoryId'] as String? ?? '',
      territoryName:     d['territoryName'] as String? ?? 'Zona desconocida',
      mode:              d['mode'] as String? ?? 'competitivo',
      timestamp:         (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      previousOwnerNick: d['previousOwnerNick'] as String?,
      fromColorValue:    (d['fromColor'] as num?)?.toInt() ?? 0xFFCC2222,
    );
  }

  Map<String, dynamic> _toMap() => {
    'userNick':          userNick,
    'territoryId':       territoryId,
    'territoryName':     territoryName,
    'mode':              mode,
    'timestamp':         timestamp.millisecondsSinceEpoch,
    'previousOwnerNick': previousOwnerNick,
    'fromColorValue':    fromColorValue,
  };

  factory ActivityEntry._fromMap(Map<String, dynamic> m) => ActivityEntry(
    userNick:          m['userNick'] as String? ?? '?',
    territoryId:       m['territoryId'] as String? ?? '',
    territoryName:     m['territoryName'] as String? ?? 'Zona desconocida',
    mode:              m['mode'] as String? ?? 'competitivo',
    timestamp:         DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
    previousOwnerNick: m['previousOwnerNick'] as String?,
    fromColorValue:    m['fromColorValue'] as int? ?? 0xFFCC2222,
  );
}

// ── Servicio ──────────────────────────────────────────────────────────────────
class ActivityService {
  static FirebaseFirestore _db = FirebaseFirestore.instance;

  @visibleForTesting
  static void setDb(FirebaseFirestore db) => _db = db;

  static const _kFeedDataKey = 'act_feed_data';
  static const _kFeedTsKey   = 'act_feed_ts';
  static const _kTtlMs       = 5 * 60 * 1000; // 5 minutos

  // Invalidar caché manualmente (botón refresh)
  static Future<void> invalidarCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFeedTsKey);
  }

  // Feed global reciente — sirve desde caché 5 min antes de ir a Firestore
  static Future<List<ActivityEntry>> obtenerFeedReciente(
      {int limit = 15}) async {
    final prefs = await SharedPreferences.getInstance();
    final ts    = prefs.getInt(_kFeedTsKey) ?? 0;
    final now   = DateTime.now().millisecondsSinceEpoch;

    if (now - ts < _kTtlMs) {
      final raw = prefs.getString(_kFeedDataKey);
      if (raw != null) {
        try {
          final list = jsonDecode(raw) as List;
          return list
              .map((e) => ActivityEntry._fromMap(e as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }
    }

    try {
      final snap = await _db
          .collection('activity_feed')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();
      final entries = snap.docs.map(ActivityEntry.fromDoc).toList();

      await prefs.setInt(_kFeedTsKey, now);
      await prefs.setString(
          _kFeedDataKey, jsonEncode(entries.map((e) => e._toMap()).toList()));

      return entries;
    } catch (e) {
      debugPrint('ActivityService.obtenerFeedReciente error: $e');
      return [];
    }
  }

  // Escribe en el historial del territorio y aumenta conquistas_count
  static Future<void> escribirHistorialConquista({
    required String territoryId,
    required String ownerNickname,
    required int ownerColorValue,
    String? previousOwnerNick,
  }) async {
    try {
      final terrRef = _db.collection('territories').doc(territoryId);
      final histRef = terrRef.collection('history').doc();
      final batch   = _db.batch();

      batch.set(histRef, {
        'ownerNickname':    ownerNickname,
        'ownerColor':       ownerColorValue,
        'previousOwner':    previousOwnerNick,
        'conquista_ts':     FieldValue.serverTimestamp(),
      });

      // Increment — si el campo no existe se crea en 1
      batch.update(terrRef, {
        'conquistas_count': FieldValue.increment(1),
      });

      await batch.commit();
    } catch (e) {
      debugPrint('ActivityService.escribirHistorialConquista error: $e');
    }
  }

  // Historial de cambios de dueño de un territorio
  static Future<List<Map<String, dynamic>>> obtenerHistorialTerritorio(
      String territoryId,
      {int limit = 4}) async {
    try {
      final snap = await _db
          .collection('territories')
          .doc(territoryId)
          .collection('history')
          .orderBy('conquista_ts', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((d) => d.data()).toList();
    } catch (e) {
      debugPrint('ActivityService.obtenerHistorialTerritorio error: $e');
      return [];
    }
  }

  // Publica una conquista en el feed global de actividad
  static Future<void> publicarConquistaFeed({
    required String uid,
    required String nickname,
    required String territoryId,
    required String territoryName,
    required String mode,
    String? previousOwnerNick,
    int fromColorValue = 0xFFCC2222,
  }) async {
    try {
      await _db.collection('activity_feed').add({
        'userId':            uid,
        'userNick':          nickname,
        'territoryId':       territoryId,
        'territoryName':     territoryName,
        'action':            'conquest',
        'mode':              mode,
        'previousOwnerNick': previousOwnerNick,
        'fromColor':         fromColorValue,
        'timestamp':         FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('ActivityService.publicarConquistaFeed error: $e');
    }
  }

  // Registra el log de una sesión completada. Devuelve el ID del documento creado.
  static Future<String?> registrarSesion(
      Map<String, dynamic> datos) async {
    try {
      final ref = await _db.collection('activity_logs').add({
        ...datos,
        'timestamp': FieldValue.serverTimestamp(),
      });
      return ref.id;
    } catch (e) {
      debugPrint('ActivityService.registrarSesion error: $e');
      return null;
    }
  }

  // Vincula un log de sesión con el territorio creado en esa misma sesión
  static void vincularLogTerritorio(String logId, String territorioId) {
    _db
        .collection('activity_logs')
        .doc(logId)
        .update({'territorio_id': territorioId})
        .catchError((e) => debugPrint('vincularLogTerritorio error: $e'));
  }

  // Acredita monedas al jugador
  static Future<void> acreditarMonedas(String uid, int cantidad) async {
    try {
      await _db
          .collection('players')
          .doc(uid)
          .update({'monedas': FieldValue.increment(cantidad)});
    } catch (e) {
      debugPrint('ActivityService.acreditarMonedas error: $e');
    }
  }

  // Envía una notificación in-app al jugador
  static Future<void> enviarNotificacion(
      Map<String, dynamic> datos) async {
    try {
      await _db.collection('notifications').add({
        ...datos,
        'read':      false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('ActivityService.enviarNotificacion error: $e');
    }
  }

  static Future<void> programarNotificacionesPostCarrera(
      String uid, double distanciaKm) async {
    try {
      final doc = await _db.collection('players').doc(uid).get();
      final d     = doc.data() ?? {};
      final racha = (d['racha_actual'] as num?)?.toInt() ?? 0;
      if (racha > 0) {
        await LocalNotifService.programarRachaEnRiesgo(racha);
      }

      final ahora      = DateTime.now();
      final inicioSemana = DateTime(
          ahora.year, ahora.month, ahora.day - (ahora.weekday - 1));
      final logsSnap = await _db
          .collection('activity_logs')
          .where('userId', isEqualTo: uid)
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(inicioSemana))
          .get();

      double kmSemana = 0;
      int    carreras = 0;
      for (final log in logsSnap.docs) {
        final dist = (log.data()['distancia'] as num?)?.toDouble() ?? 0;
        if (dist > 0) { kmSemana += dist; carreras++; }
      }

      final conqSnap = await _db
          .collection('territories')
          .where('userId', isEqualTo: uid)
          .count()
          .get();
      final territorios = (conqSnap.count as num?)?.toInt() ?? 0;

      await LocalNotifService.programarResumenSemanal(
        kmSemana:    kmSemana,
        carreras:    carreras,
        territorios: territorios,
      );
    } catch (e) {
      debugPrint('ActivityService.programarNotificacionesPostCarrera: $e');
    }
  }

  /// Lee el documento de jugador para inicializar configuración de sesión.
  /// Devuelve null si el documento no existe o hay un error de red.
  static Future<Map<String, dynamic>?> cargarConfigJugador(String uid) async {
    try {
      final doc = await _db.collection('players').doc(uid).get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      debugPrint('ActivityService.cargarConfigJugador error: $e');
      return null;
    }
  }
}
