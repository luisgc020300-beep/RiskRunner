// lib/services/ranking_service.dart
//
// Gestiona los tres rankings independientes:
//   - Competitivo (puntos_liga, permanente) — ya gestionado por LeagueService
//   - Semanal Global (puntos_semana_global, se resetea por semana ISO)
//   - Rutas (km_totales_rutas, acumulado histórico)
//
// Solitario NO tiene ranking global. Solo estadísticas personales.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class RankingService {
  static final _db = FirebaseFirestore.instance;

  // ── Semana ISO actual (e.g. "2026-W19") ─────────────────────────────────────
  static String getSemanaActual() {
    final now = DateTime.now().toUtc();
    // Calcula semana ISO-8601: semana 1 = semana que contiene el primer jueves
    final jan4 = DateTime.utc(now.year, 1, 4);
    final startW1 = jan4.subtract(Duration(days: jan4.weekday - 1));
    final diff = now.difference(startW1).inDays;
    if (diff < 0) {
      // Pertenece a la última semana del año anterior
      final jan4prev = DateTime.utc(now.year - 1, 1, 4);
      final startW1prev = jan4prev.subtract(Duration(days: jan4prev.weekday - 1));
      final diffPrev = now.difference(startW1prev).inDays;
      final week = (diffPrev ~/ 7) + 1;
      return '${now.year - 1}-W${week.toString().padLeft(2, '0')}';
    }
    final week = (diff ~/ 7) + 1;
    return '${now.year}-W${week.toString().padLeft(2, '0')}';
  }

  // ── Sumar puntos al ranking semanal global ───────────────────────────────────
  // Si el usuario entra en una semana nueva, reinicia su contador automáticamente.
  static Future<void> sumarPuntosGlobal(String userId, int delta) async {
    if (delta <= 0) return;
    try {
      final ref = _db.collection('players').doc(userId);
      final snap = await ref.get();
      final semanaActual = getSemanaActual();
      final semanaDoc = snap.data()?['semana_global'] as String?;

      if (semanaDoc == semanaActual) {
        await ref.update({'puntos_semana_global': FieldValue.increment(delta)});
      } else {
        // Nueva semana: reinicia el contador del usuario
        await ref.set({
          'puntos_semana_global': delta,
          'semana_global': semanaActual,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('RankingService.sumarPuntosGlobal: $e');
    }
  }

  // ── Ranking semanal global — top 100 de la semana actual ────────────────────
  // Sin orderBy en Firestore (evita índice compuesto), ordenado en cliente.
  static Stream<List<Map<String, dynamic>>> rankingSemanalStream() {
    final semana = getSemanaActual();
    return _db
        .collection('players')
        .where('semana_global', isEqualTo: semana)
        .limit(100)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      list.sort((a, b) {
        final pa = (a['puntos_semana_global'] as num? ?? 0).toInt();
        final pb = (b['puntos_semana_global'] as num? ?? 0).toInt();
        return pb.compareTo(pa);
      });
      return list;
    });
  }

  // ── Ranking rutas — top 100 por km totales históricos ────────────────────────
  // Usa campo km_totales_rutas (índice de un solo campo, auto-creado por Firestore).
  static Stream<List<Map<String, dynamic>>> rankingRutasStream() {
    return _db
        .collection('players')
        .orderBy('km_totales_rutas', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }
}
