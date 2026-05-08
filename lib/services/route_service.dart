// lib/services/route_service.dart
//
// Gestiona rutas libres (modo Ruta): guardar, nombrar, cargar y stats.
// Recompensa basada en distancia + ritmo, menor que modos de conquista.
//
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

// ── Constantes de recompensa ──────────────────────────────────────────────────
const double _kMonedasPorKm   = 8.0;  // vs 10 base en territorios
const double _kLigaPtsPorKm  = 2.0;  // vs 15-25 pts en territorios
const double _kBonusRitmoRapido = 1.20; // +20% si ritmo < 5:00/km

// =============================================================================
// MODELO
// =============================================================================
class RouteData {
  final String    id;
  final String    userId;
  final String?   nombre;
  final List<LatLng> coords;
  final double    distanciaKm;
  final int       tiempoSeg;
  final double    ritmoMinKm;
  final DateTime  fecha;
  final int       monedasGanadas;
  final int       puntosLigaGanados;
  final Color     color;
  final String    ownerNickname;

  const RouteData({
    required this.id,
    required this.userId,
    this.nombre,
    required this.coords,
    required this.distanciaKm,
    required this.tiempoSeg,
    required this.ritmoMinKm,
    required this.fecha,
    required this.monedasGanadas,
    required this.puntosLigaGanados,
    required this.color,
    required this.ownerNickname,
  });

  factory RouteData.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    final rawCoords = (d['coords'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return RouteData(
      id:                doc.id,
      userId:            d['userId']         as String? ?? '',
      nombre:            d['nombre']         as String?,
      coords:            rawCoords.map((c) => LatLng(
        (c['lat'] as num).toDouble(),
        (c['lng'] as num).toDouble(),
      )).toList(),
      distanciaKm:       (d['distanciaKm']  as num?)?.toDouble() ?? 0.0,
      tiempoSeg:         (d['tiempoSeg']    as num?)?.toInt()    ?? 0,
      ritmoMinKm:        (d['ritmoMinKm']   as num?)?.toDouble() ?? 0.0,
      fecha:             (d['fecha'] as Timestamp?)?.toDate()    ?? DateTime.now(),
      monedasGanadas:    (d['monedasGanadas']    as num?)?.toInt() ?? 0,
      puntosLigaGanados: (d['puntosLigaGanados'] as num?)?.toInt() ?? 0,
      color:             Color((d['color'] as num?)?.toInt()     ?? 0xFFD4722A),
      ownerNickname:     d['ownerNickname']  as String? ?? '',
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
}

// =============================================================================
// SERVICIO
// =============================================================================
class RouteService {
  static final _db = FirebaseFirestore.instance;

  // ── Calcular recompensa para una ruta libre ───────────────────────────────
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

  // ── Guardar ruta + dar recompensa + actualizar stats ─────────────────────
  // Devuelve el ID del documento creado (null si error).
  static Future<String?> guardarRuta({
    required String    userId,
    required String    ownerNickname,
    required Color     color,
    required List<LatLng> coords,
    required double    distanciaKm,
    required int       tiempoSeg,
    required double    ritmoMinKm,
    required int       monedas,
    required int       puntosLiga,
    String?            nombre,
  }) async {
    try {
      final routeRef  = _db.collection('routes').doc();
      final playerRef = _db.collection('players').doc(userId);

      // Transacción: guarda la ruta y actualiza stats + récords en atómico
      await _db.runTransaction((tx) async {
        final playerSnap = await tx.get(playerRef);
        final existing   = (playerSnap.data()?['rutasStats'] as Map<String, dynamic>?) ?? {};

        final prevMejorRitmo = (existing['mejorRitmoMinKm'] as num?)?.toDouble();
        final prevMayorDist  = (existing['mayorDistanciaKm'] as num?)?.toDouble();

        final nuevoMejorRitmo = (prevMejorRitmo == null || ritmoMinKm < prevMejorRitmo)
            ? ritmoMinKm : prevMejorRitmo;
        final nuevaMayorDist  = (prevMayorDist  == null || distanciaKm > prevMayorDist)
            ? distanciaKm : prevMayorDist;

        tx.set(routeRef, {
          'userId':           userId,
          'ownerNickname':    ownerNickname,
          'color':            color.toARGB32(),
          'nombre':           nombre,
          'coords':           coords.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
          'distanciaKm':      distanciaKm,
          'tiempoSeg':        tiempoSeg,
          'ritmoMinKm':       ritmoMinKm,
          'monedasGanadas':   monedas,
          'puntosLigaGanados': puntosLiga,
          'fecha':            FieldValue.serverTimestamp(),
        });

        // set+merge en vez de update para que funcione aunque el doc no exista
        tx.set(playerRef, {
          'monedas':                         FieldValue.increment(monedas),
          'rutasStats.totalRutas':           FieldValue.increment(1),
          'rutasStats.totalKm':              FieldValue.increment(distanciaKm),
          'rutasStats.totalSeg':             FieldValue.increment(tiempoSeg),
          'rutasStats.mejorRitmoMinKm':      nuevoMejorRitmo,
          'rutasStats.mayorDistanciaKm':     nuevaMayorDist,
          // Campo denormalizado para el ranking de rutas (evita índice compuesto)
          'km_totales_rutas':                FieldValue.increment(distanciaKm),
        }, SetOptions(merge: true));
      });

      return routeRef.id;
    } catch (e) {
      debugPrint('RouteService.guardarRuta: $e');
      return null;
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

  // ── Rutas del usuario actual (para FullscreenMap y perfil) ───────────────
  static Future<List<RouteData>> cargarMisRutas({int limit = 50}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    try {
      // Sin orderBy en Firestore para evitar requerir índice compuesto;
      // ordenamos por fecha en cliente.
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

  // ── Stats del campo rutasStats en el doc del jugador ────────────────────
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
        totalSeg:         (raw['totalSeg']           as num?)?.toInt()   ?? 0,
        mejorRitmoMinKm:  (raw['mejorRitmoMinKm']   as num?)?.toDouble() ?? 0.0,
        mayorDistanciaKm: (raw['mayorDistanciaKm']  as num?)?.toDouble() ?? 0.0,
      );
    } catch (e) {
      debugPrint('RouteService.cargarRutasStats: $e');
      return null;
    }
  }
}
