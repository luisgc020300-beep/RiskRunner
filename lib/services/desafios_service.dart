// lib/services/desafios_service.dart
//
// ── CAMBIOS v2 (Cloud Functions) ───────────────────────────────────────────
//
//  ANTES:
//    - verificarExpirados()  → el cliente resolvía desafíos expirados
//    - acumularPuntos()      → el cliente escribía directamente en Firestore
//    - _resolverDesafio()    → lógica de resolución en el cliente
//
//    Problema: race condition si dos usuarios abrían la app a la vez,
//    y el desafío nunca se resolvía si ambos tenían la app cerrada.
//
//  AHORA:
//    - verificarExpirados()  → eliminada. El scheduler del servidor se encarga.
//    - acumularPuntos()      → llama a Cloud Function 'acumularPuntosDesafio'
//    - _resolverDesafio()    → eliminada. Solo existe en el servidor.
//
//  Lo que queda en el cliente: streams de lectura (sin cambios) y getDesafio.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class DesafioInfo {
  final String id;
  final String retadorId;
  final String retadorNick;
  final String retadoId;
  final String retadoNick;
  final int apuesta;
  final int duracionHoras;
  final String estado;
  final int puntosRetador;
  final int puntosRetado;
  final DateTime? inicio;
  final DateTime? fin;
  final String? ganadorId;

  const DesafioInfo({
    required this.id,
    required this.retadorId,
    required this.retadorNick,
    required this.retadoId,
    required this.retadoNick,
    required this.apuesta,
    required this.duracionHoras,
    required this.estado,
    required this.puntosRetador,
    required this.puntosRetado,
    this.inicio,
    this.fin,
    this.ganadorId,
  });

  factory DesafioInfo.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return DesafioInfo(
      id:            doc.id,
      retadorId:     d['retadorId']   as String? ?? '',
      retadorNick:   d['retadorNick'] as String? ?? 'Rival',
      retadoId:      d['retadoId']    as String? ?? '',
      retadoNick:    d['retadoNick']  as String? ?? 'Rival',
      apuesta:       (d['apuesta']        as num?)?.toInt() ?? 0,
      duracionHoras: (d['duracionHoras']  as num?)?.toInt() ?? 24,
      estado:        d['estado']    as String? ?? 'pendiente',
      puntosRetador: (d['puntosRetador']  as num?)?.toInt() ?? 0,
      puntosRetado:  (d['puntosRetado']   as num?)?.toInt() ?? 0,
      inicio:        (d['inicio'] as Timestamp?)?.toDate(),
      fin:           (d['fin']    as Timestamp?)?.toDate(),
      ganadorId:     d['ganadorId'] as String?,
    );
  }

  bool get haExpirado => fin != null && DateTime.now().isAfter(fin!);

  String get tiempoRestante {
    if (fin == null) return '--';
    final remaining = fin!.difference(DateTime.now());
    if (remaining.isNegative) return 'Expirado';
    if (remaining.inDays > 0) {
      return '${remaining.inDays}d ${remaining.inHours.remainder(24)}h';
    }
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m';
    }
    return '${remaining.inMinutes}m';
  }

  int puntosDeUsuario(String uid) =>
      uid == retadorId ? puntosRetador : puntosRetado;
  int puntosDeRival(String uid) =>
      uid == retadorId ? puntosRetado : puntosRetador;
  String nickRival(String uid) =>
      uid == retadorId ? retadoNick : retadorNick;
  bool vaGanando(String uid) => puntosDeUsuario(uid) >= puntosDeRival(uid);
}

class DesafiosService {
  static final _db = FirebaseFirestore.instance;

  // ── Instancia de Cloud Functions (región europe-west1) ─────────────────────
  static final _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

  // ── Streams de lectura (sin cambios) ────────────────────────────────────────

  static Stream<List<DesafioInfo>> streamActivos(String uid) {
    final q1 = _db.collection('desafios')
        .where('retadorId', isEqualTo: uid)
        .where('estado', isEqualTo: 'activo')
        .snapshots()
        .map((s) => s.docs.map(DesafioInfo.fromFirestore).toList());

    final q2 = _db.collection('desafios')
        .where('retadoId', isEqualTo: uid)
        .where('estado', isEqualTo: 'activo')
        .snapshots()
        .map((s) => s.docs.map(DesafioInfo.fromFirestore).toList());

    return _combinarStreams(q1, q2);
  }

  static Stream<List<DesafioInfo>> streamPendientes(String uid) {
    return _db.collection('desafios')
        .where('retadorId', isEqualTo: uid)
        .where('estado', isEqualTo: 'pendiente')
        .snapshots()
        .map((s) => s.docs.map(DesafioInfo.fromFirestore).toList());
  }

  static Stream<List<DesafioInfo>> streamHistorial(String uid) {
    // Sin orderBy para evitar requerir índice compuesto en Firestore.
    // _combinarStreams ya ordena por inicio desc.
    final q1 = _db.collection('desafios')
        .where('retadorId', isEqualTo: uid)
        .where('estado', isEqualTo: 'finalizado')
        .limit(30)
        .snapshots()
        .map((s) => s.docs.map(DesafioInfo.fromFirestore).toList());

    final q2 = _db.collection('desafios')
        .where('retadoId', isEqualTo: uid)
        .where('estado', isEqualTo: 'finalizado')
        .limit(30)
        .snapshots()
        .map((s) => s.docs.map(DesafioInfo.fromFirestore).toList());

    return _combinarStreams(q1, q2);
  }

  // ── ACUMULAR PUNTOS — ahora llama a Cloud Function ──────────────────────────
  //
  //  La Cloud Function valida los datos y escribe en Firestore.
  //  Si el desafío ya expiró, la propia función lo resuelve.
  //
  static Future<void> acumularPuntos({
    required String uid,
    required double distanciaKm,
    required int territoriosConquistados,
  }) async {
    try {
      final callable = _functions.httpsCallable('acumularPuntosDesafio');
      final result = await callable.call({
        'distanciaKm':             distanciaKm,
        'territoriosConquistados': territoriosConquistados,
      });
      debugPrint(
        'acumularPuntos OK — '
        '${result.data['puntosAcumulados']} pts en '
        '${result.data['desafiosActualizados']} desafíos',
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Error acumularPuntos (${e.code}): ${e.message}');
    } catch (e) {
      debugPrint('Error acumularPuntos: $e');
    }
  }

  // ── VERIFICAR EXPIRADOS — ya no hace nada en el cliente ─────────────────────
  //
  //  El scheduler del servidor (resolverDesafiosExpirados) se ejecuta
  //  cada hora y resuelve todos los desafíos expirados automáticamente.
  //
  //  Mantenemos el método para no romper las llamadas existentes en main.dart,
  //  pero ya no hace ninguna query a Firestore.
  //
  static Future<void> verificarExpirados(String uid) async {
    // El servidor se encarga. Esta función ya no es necesaria en el cliente.
    debugPrint('verificarExpirados: gestionado por Cloud Function scheduler.');
  }

  // ── Obtener un desafío por ID ───────────────────────────────────────────────
  static Future<DesafioInfo?> getDesafio(String desafioId) async {
    try {
      final doc = await _db.collection('desafios').doc(desafioId).get();
      if (!doc.exists) return null;
      return DesafioInfo.fromFirestore(doc);
    } catch (e) {
      debugPrint('Error getDesafio: $e');
      return null;
    }
  }

  // ── Helper: combinar dos streams ────────────────────────────────────────────
  static Stream<List<DesafioInfo>> _combinarStreams(
    Stream<List<DesafioInfo>> s1,
    Stream<List<DesafioInfo>> s2,
  ) {
    List<DesafioInfo> last1 = [];
    List<DesafioInfo> last2 = [];

    late StreamController<List<DesafioInfo>> ctrl;
    ctrl = StreamController<List<DesafioInfo>>.broadcast(
      onListen: () {
        s1.listen((l) {
          last1 = l;
          if (!ctrl.isClosed) {
            final merged = [...last1, ...last2];
            merged.sort((a, b) => (b.inicio ?? DateTime(0))
                .compareTo(a.inicio ?? DateTime(0)));
            ctrl.add(merged);
          }
        });
        s2.listen((l) {
          last2 = l;
          if (!ctrl.isClosed) {
            final merged = [...last1, ...last2];
            merged.sort((a, b) => (b.inicio ?? DateTime(0))
                .compareTo(a.inicio ?? DateTime(0)));
            ctrl.add(merged);
          }
        });
      },
    );
    return ctrl.stream;
  }
}