// lib/services/route_service.dart
//
// Gestiona rutas libres (modo Ruta): guardar, nombrar, cargar, stats
// y descubrimiento social (populares, nuevas, amigos, guardadas).
//
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

// ── Constantes de recompensa ──────────────────────────────────────────────────
const double _kMonedasPorKm      = 8.0;
const double _kLigaPtsPorKm      = 2.0;
const double _kBonusRitmoRapido  = 1.20; // +20% si ritmo < 5:00/km

// Umbral para considerar una ruta "legendaria"
const int kLegendaryThreshold = 5;

// =============================================================================
// MODELO
// =============================================================================
class RouteData {
  final String       id;
  final String       userId;
  final String?      nombre;
  final String?      descripcion;
  final String       privacidad; // 'publica' | 'amigos' | 'privada'
  final List<LatLng> coords;
  final double       distanciaKm;
  final int          tiempoSeg;
  final double       ritmoMinKm;
  final DateTime     fecha;
  final int          monedasGanadas;
  final int          puntosLigaGanados;
  final Color        color;
  final String       ownerNickname;
  final int          savesCount;
  final int          runsCount;

  const RouteData({
    required this.id,
    required this.userId,
    this.nombre,
    this.descripcion,
    this.privacidad = 'publica',
    required this.coords,
    required this.distanciaKm,
    required this.tiempoSeg,
    required this.ritmoMinKm,
    required this.fecha,
    required this.monedasGanadas,
    required this.puntosLigaGanados,
    required this.color,
    required this.ownerNickname,
    this.savesCount = 0,
    this.runsCount  = 0,
  });

  bool get esLegendaria => runsCount >= kLegendaryThreshold;

  RouteData conNombre(String? nuevoNombre) => RouteData(
    id: id, userId: userId, nombre: nuevoNombre, descripcion: descripcion,
    privacidad: privacidad, coords: coords, distanciaKm: distanciaKm,
    tiempoSeg: tiempoSeg, ritmoMinKm: ritmoMinKm, fecha: fecha,
    monedasGanadas: monedasGanadas, puntosLigaGanados: puntosLigaGanados,
    color: color, ownerNickname: ownerNickname,
    savesCount: savesCount, runsCount: runsCount,
  );

  factory RouteData.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    final rawCoords = (d['coords'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return RouteData(
      id:                doc.id,
      userId:            d['userId']         as String? ?? '',
      nombre:            d['nombre']         as String?,
      descripcion:       d['descripcion']    as String?,
      privacidad:        d['privacidad']     as String? ?? 'publica',
      coords:            rawCoords.map((c) => LatLng(
        (c['lat'] as num).toDouble(),
        (c['lng'] as num).toDouble(),
      )).toList(),
      distanciaKm:       (d['distanciaKm']       as num?)?.toDouble() ?? 0.0,
      tiempoSeg:         (d['tiempoSeg']          as num?)?.toInt()    ?? 0,
      ritmoMinKm:        (d['ritmoMinKm']         as num?)?.toDouble() ?? 0.0,
      fecha:             (d['fecha'] as Timestamp?)?.toDate()           ?? DateTime.now(),
      monedasGanadas:    (d['monedasGanadas']     as num?)?.toInt()    ?? 0,
      puntosLigaGanados: (d['puntosLigaGanados']  as num?)?.toInt()    ?? 0,
      color:             Color((d['color'] as num?)?.toInt()            ?? 0xFFD4722A),
      ownerNickname:     d['ownerNickname']        as String? ?? '',
      savesCount:        (d['saves_count']         as num?)?.toInt()    ?? 0,
      runsCount:         (d['runs_count']          as num?)?.toInt()    ?? 0,
    );
  }

  String get tiempoStr {
    final h = tiempoSeg ~/ 3600;
    final m = (tiempoSeg % 3600) ~/ 60;
    final s = tiempoSeg % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get ritmoStr {
    if (ritmoMinKm <= 0) return '--:--';
    final min = ritmoMinKm.floor();
    final seg = ((ritmoMinKm - min) * 60).round();
    return "$min'${seg.toString().padLeft(2, '0')}\"";
  }

  String get distanciaStr => '${distanciaKm.toStringAsFixed(1)} km';
}

// =============================================================================
// SERVICIO
// =============================================================================
class RouteService {
  static final _db = FirebaseFirestore.instance;

  // ── Calcular recompensa ───────────────────────────────────────────────────
  static ({int monedas, int puntosLiga}) calcularRecompensa({
    required double distanciaKm,
    required double ritmoMinKm,
    required bool   esPremium,
    required bool   boostActivo,
  }) {
    final bonusRitmo    = ritmoMinKm > 0 && ritmoMinKm < 5.0 ? _kBonusRitmoRapido : 1.0;
    final multiplicador = (boostActivo ? 2 : 1) * (esPremium ? 2 : 1);
    return (
      monedas:    (distanciaKm * _kMonedasPorKm  * bonusRitmo * multiplicador).round(),
      puntosLiga: (distanciaKm * _kLigaPtsPorKm  * bonusRitmo).round(),
    );
  }

  // ── Guardar ruta + recompensa + stats ────────────────────────────────────
  static Future<String?> guardarRuta({
    required String       userId,
    required String       ownerNickname,
    required Color        color,
    required List<LatLng> coords,
    required double       distanciaKm,
    required int          tiempoSeg,
    required double       ritmoMinKm,
    required int          monedas,
    required int          puntosLiga,
    String?               nombre,
    String?               descripcion,
    String                privacidad = 'publica',
  }) async {
    try {
      final routeRef  = _db.collection('routes').doc();
      final playerRef = _db.collection('players').doc(userId);

      await _db.runTransaction((tx) async {
        final playerSnap = await tx.get(playerRef);
        final existing   = (playerSnap.data()?['rutasStats'] as Map<String, dynamic>?) ?? {};

        final prevMejorRitmo = (existing['mejorRitmoMinKm'] as num?)?.toDouble();
        final prevMayorDist  = (existing['mayorDistanciaKm'] as num?)?.toDouble();

        final nuevoMejorRitmo = (prevMejorRitmo == null || ritmoMinKm < prevMejorRitmo)
            ? ritmoMinKm : prevMejorRitmo;
        final nuevaMayorDist  = (prevMayorDist == null || distanciaKm > prevMayorDist)
            ? distanciaKm : prevMayorDist;

        tx.set(routeRef, {
          'userId':            userId,
          'ownerNickname':     ownerNickname,
          'color':             color.toARGB32(),
          'nombre':            nombre,
          'descripcion':       descripcion,
          'privacidad':        privacidad,
          'coords':            coords.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
          'distanciaKm':       distanciaKm,
          'tiempoSeg':         tiempoSeg,
          'ritmoMinKm':        ritmoMinKm,
          'monedasGanadas':    monedas,
          'puntosLigaGanados': puntosLiga,
          'fecha':             FieldValue.serverTimestamp(),
          'saves_count':       0,
          'runs_count':        0,
        });

        tx.set(playerRef, {
          'monedas':                     FieldValue.increment(monedas),
          'rutasStats.totalRutas':       FieldValue.increment(1),
          'rutasStats.totalKm':          FieldValue.increment(distanciaKm),
          'rutasStats.totalSeg':         FieldValue.increment(tiempoSeg),
          'rutasStats.mejorRitmoMinKm':  nuevoMejorRitmo,
          'rutasStats.mayorDistanciaKm': nuevaMayorDist,
          'km_totales_rutas':            FieldValue.increment(distanciaKm),
        }, SetOptions(merge: true));
      });

      return routeRef.id;
    } catch (e, st) {
      debugPrint('❌ RouteService.guardarRuta FALLÓ: $e\n$st');
      rethrow;
    }
  }

  // ── Asignar nombre a una ruta ya guardada ────────────────────────────────
  static Future<void> nombrarRuta(String routeId, String nombre) async {
    try {
      await _db.collection('routes').doc(routeId).update({'nombre': nombre});
    } catch (e) {
      debugPrint('RouteService.nombrarRuta: $e');
    }
  }

  // ── Eliminar una ruta propia ──────────────────────────────────────────────
  static Future<void> eliminarRuta(String routeId) async {
    try {
      await _db.collection('routes').doc(routeId).delete();
    } catch (e) {
      debugPrint('RouteService.eliminarRuta: $e');
    }
  }

  // ── Rutas del usuario actual ──────────────────────────────────────────────
  static Future<List<RouteData>> cargarMisRutas({int limit = 50}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    try {
      final snap = await _db
          .collection('routes')
          .where('userId', isEqualTo: user.uid)
          .limit(limit)
          .get();
      final list = snap.docs.map(RouteData.fromFirestore).toList();
      list.sort((a, b) => b.fecha.compareTo(a.fecha));
      return list;
    } catch (e) {
      debugPrint('RouteService.cargarMisRutas: $e');
      return [];
    }
  }

  // ── Rutas por ID ──────────────────────────────────────────────────────────
  static Future<RouteData?> cargarRutaPorId(String routeId) async {
    try {
      final doc = await _db.collection('routes').doc(routeId).get();
      if (!doc.exists || doc.data() == null) return null;
      return RouteData.fromFirestore(doc);
    } catch (e) {
      debugPrint('RouteService.cargarRutaPorId: $e');
      return null;
    }
  }

  // ==========================================================================
  // DESCUBRIMIENTO
  // ==========================================================================

  // Rutas más corridas (sin filtro de privacidad — todas son públicas por defecto)
  static Future<List<RouteData>> rutasPopulares({int limit = 40}) async {
    try {
      final snap = await _db
          .collection('routes')
          .limit(limit * 2) // traemos más para filtrar privadas client-side
          .get();
      final list = snap.docs
          .map(RouteData.fromFirestore)
          .where((r) => r.privacidad != 'privada' && r.coords.length >= 2)
          .toList();
      list.sort((a, b) => b.runsCount.compareTo(a.runsCount));
      return list.take(limit).toList();
    } catch (e) {
      debugPrint('RouteService.rutasPopulares: $e');
      return [];
    }
  }

  // Rutas más recientes
  static Future<List<RouteData>> rutasNuevas({int limit = 40}) async {
    try {
      final snap = await _db
          .collection('routes')
          .limit(limit * 2)
          .get();
      final list = snap.docs
          .map(RouteData.fromFirestore)
          .where((r) => r.privacidad != 'privada' && r.coords.length >= 2)
          .toList();
      list.sort((a, b) => b.fecha.compareTo(a.fecha));
      return list.take(limit).toList();
    } catch (e) {
      debugPrint('RouteService.rutasNuevas: $e');
      return [];
    }
  }

  // Rutas de amigos (friendIds en batches de 10 por límite de Firestore)
  static Future<List<RouteData>> rutasDeAmigos(
      List<String> friendIds, {int limit = 40}) async {
    if (friendIds.isEmpty) return [];
    try {
      final batches = <List<String>>[];
      for (var i = 0; i < friendIds.length; i += 10) {
        batches.add(friendIds.sublist(i,
            i + 10 > friendIds.length ? friendIds.length : i + 10));
      }
      final results = await Future.wait(batches.map((batch) => _db
          .collection('routes')
          .where('userId', whereIn: batch)
          .limit(limit)
          .get()));
      final ids  = <String>{};
      final list = <RouteData>[];
      for (final snap in results) {
        for (final doc in snap.docs) {
          if (ids.add(doc.id)) {
            final r = RouteData.fromFirestore(doc);
            if (r.privacidad != 'privada' && r.coords.length >= 2) list.add(r);
          }
        }
      }
      list.sort((a, b) => b.fecha.compareTo(a.fecha));
      return list.take(limit).toList();
    } catch (e) {
      debugPrint('RouteService.rutasDeAmigos: $e');
      return [];
    }
  }

  // Rutas guardadas por el usuario (subcollección players/{uid}/saved_routes)
  static Future<List<RouteData>> rutasGuardadas(String userId) async {
    try {
      final savedSnap = await _db
          .collection('players')
          .doc(userId)
          .collection('saved_routes')
          .get();
      if (savedSnap.docs.isEmpty) return [];
      final ids = savedSnap.docs.map((d) => d.id).toList();
      // Batch get en grupos de 10
      final batches = <List<String>>[];
      for (var i = 0; i < ids.length; i += 10) {
        batches.add(ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10));
      }
      final results = await Future.wait(batches.map((batch) => _db
          .collection('routes')
          .where(FieldPath.documentId, whereIn: batch)
          .get()));
      final list = <RouteData>[];
      for (final snap in results) {
        for (final doc in snap.docs) {
          final r = RouteData.fromFirestore(doc);
          if (r.coords.length >= 2) list.add(r);
        }
      }
      list.sort((a, b) => b.fecha.compareTo(a.fecha));
      return list;
    } catch (e) {
      debugPrint('RouteService.rutasGuardadas: $e');
      return [];
    }
  }

  // ==========================================================================
  // GUARDAR / QUITAR FAVORITA
  // ==========================================================================

  static Future<void> marcarFavorita(String userId, String routeId) async {
    try {
      final batch = _db.batch();
      batch.set(
        _db.collection('players').doc(userId).collection('saved_routes').doc(routeId),
        {'savedAt': FieldValue.serverTimestamp()},
      );
      batch.update(
        _db.collection('routes').doc(routeId),
        {'saves_count': FieldValue.increment(1)},
      );
      await batch.commit();
    } catch (e) {
      debugPrint('RouteService.marcarFavorita: $e');
    }
  }

  static Future<void> quitarFavorita(String userId, String routeId) async {
    try {
      final batch = _db.batch();
      batch.delete(
        _db.collection('players').doc(userId).collection('saved_routes').doc(routeId),
      );
      batch.update(
        _db.collection('routes').doc(routeId),
        {'saves_count': FieldValue.increment(-1)},
      );
      await batch.commit();
    } catch (e) {
      debugPrint('RouteService.quitarFavorita: $e');
    }
  }

  static Future<bool> estaGuardada(String userId, String routeId) async {
    try {
      final doc = await _db
          .collection('players')
          .doc(userId)
          .collection('saved_routes')
          .doc(routeId)
          .get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  // Carga el set de routeIds guardadas (para lookup rápido en listas)
  static Future<Set<String>> cargarIdsGuardadas(String userId) async {
    try {
      final snap = await _db
          .collection('players')
          .doc(userId)
          .collection('saved_routes')
          .get();
      return snap.docs.map((d) => d.id).toSet();
    } catch (e) {
      return {};
    }
  }

  // ==========================================================================
  // REGISTRAR CORRIDA
  // ==========================================================================

  static Future<void> registrarCorrida(String routeId) async {
    try {
      await _db.collection('routes').doc(routeId).update({
        'runs_count': FieldValue.increment(1),
      });
    } catch (e) {
      debugPrint('RouteService.registrarCorrida: $e');
    }
  }

  // ==========================================================================
  // STATS DEL JUGADOR
  // ==========================================================================

  static Future<({
    int    totalRutas,
    double totalKm,
    int    totalSeg,
    double mejorRitmoMinKm,
    double mayorDistanciaKm,
  })?> cargarRutasStats(String userId) async {
    try {
      final doc = await _db.collection('players').doc(userId).get();
      final raw = doc.data()?['rutasStats'] as Map<String, dynamic>?;
      if (raw == null) return null;
      return (
        totalRutas:       (raw['totalRutas']       as num?)?.toInt()    ?? 0,
        totalKm:          (raw['totalKm']           as num?)?.toDouble() ?? 0.0,
        totalSeg:         (raw['totalSeg']          as num?)?.toInt()    ?? 0,
        mejorRitmoMinKm:  (raw['mejorRitmoMinKm']   as num?)?.toDouble() ?? 0.0,
        mayorDistanciaKm: (raw['mayorDistanciaKm']  as num?)?.toDouble() ?? 0.0,
      );
    } catch (e) {
      debugPrint('RouteService.cargarRutasStats: $e');
      return null;
    }
  }
}
