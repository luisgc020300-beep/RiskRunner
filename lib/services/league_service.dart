import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

// lib/services/league_service.dart
//
// Fuente única de verdad para todo lo relacionado con ligas.
// Importar desde: social_screen.dart, perfil_screen.dart, live_activity_screen.dart
//
// La suma de puntos de liga por carrera competitiva o ruta guardada se
// calcula en el servidor (Cloud Function 'sumarPuntosLigaJugador') — el
// cliente solo manda el motivo y los datos brutos de la actividad, nunca
// un delta ya calculado. Las recompensas de guerra global y conquista de
// territorio se escriben directamente desde otras Cloud Functions.

// =============================================================================
// MODELO
// =============================================================================

class LeagueInfo {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final int minPts;
  final int? maxPts;
  final String descripcion;

  const LeagueInfo({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.minPts,
    this.maxPts,
    required this.descripcion,
  });
}

// =============================================================================
// SISTEMA DE LIGAS
// =============================================================================

class LeagueSystem {
  static const List<LeagueInfo> ligas = [
    LeagueInfo(
      id: 'bronce',
      name: 'BRONCE',
      icon: Icons.military_tech_rounded,
      color: Color(0xFFBF8B5E),
      minPts: 0,
      maxPts: 499,
      descripcion: 'Recién llegado al campo de batalla',
    ),
    LeagueInfo(
      id: 'plata',
      name: 'PLATA',
      icon: Icons.military_tech_rounded,
      color: Color(0xFFB0BEC5),
      minPts: 500,
      maxPts: 1499,
      descripcion: 'Conquistador en ascenso',
    ),
    LeagueInfo(
      id: 'oro',
      name: 'ORO',
      icon: Icons.emoji_events_rounded,
      color: Color(0xFFFFD600),
      minPts: 1500,
      maxPts: 3499,
      descripcion: 'Dominador territorial reconocido',
    ),
    LeagueInfo(
      id: 'platino',
      name: 'PLATINO',
      icon: Icons.workspace_premium_rounded,
      color: Color(0xFF40C4FF),
      minPts: 3500,
      maxPts: 6999,
      descripcion: 'Élite de la conquista urbana',
    ),
    LeagueInfo(
      id: 'diamante',
      name: 'DIAMANTE',
      icon: Icons.diamond_rounded,
      color: Color(0xFF00B0FF),
      minPts: 7000,
      maxPts: 11999,
      descripcion: 'Leyenda viviente de las calles',
    ),
    LeagueInfo(
      id: 'leyenda',
      name: 'LEYENDA',
      icon: Icons.stars_rounded,
      color: Color(0xFFFF6D00),
      minPts: 12000,
      maxPts: null,
      descripcion: 'El rey indiscutible del territorio',
    ),
  ];

  static const List<String> _orden = [
    'bronce', 'plata', 'oro', 'platino', 'diamante', 'leyenda'
  ];

  static LeagueInfo getLeagueById(String ligaId) {
    final id = ligaId.toLowerCase();
    return ligas.firstWhere((l) => l.id == id, orElse: () => ligas.first);
  }

  static LeagueInfo calcularLigaPorPuntos(int puntos) {
    for (int i = ligas.length - 1; i >= 0; i--) {
      if (puntos >= ligas[i].minPts) return ligas[i];
    }
    return ligas.first;
  }

  static double progresoDentroLiga(int puntos) {
    final liga = calcularLigaPorPuntos(puntos);
    if (liga.maxPts == null) return 1.0;
    final rango = liga.maxPts! - liga.minPts + 1;
    final dentro = puntos - liga.minPts;
    return (dentro / rango).clamp(0.0, 1.0);
  }

  static int puntosParaSiguienteLiga(int puntos) {
    final liga = calcularLigaPorPuntos(puntos);
    if (liga.maxPts == null) return 0;
    return liga.maxPts! + 1 - puntos;
  }

  static int indice(String ligaId) {
    final i = _orden.indexOf(ligaId.toLowerCase());
    return i < 0 ? 0 : i;
  }
}

// =============================================================================
// LEAGUE HELPER  —  alias para compatibilidad con social_screen y perfil_screen
// =============================================================================

class LeagueHelper {
  static LeagueInfo getLeague(int puntosLiga) =>
      LeagueSystem.calcularLigaPorPuntos(puntosLiga);

  static double getProgress(int puntosLiga) =>
      LeagueSystem.progresoDentroLiga(puntosLiga);

  static int ptsParaSiguiente(int puntosLiga) =>
      LeagueSystem.puntosParaSiguienteLiga(puntosLiga);
}

// =============================================================================
// RESULTADO DE COMPROBACIÓN DE ROBO
// =============================================================================

enum RoboRazon {
  permitido,
  defensorProtegido,
  diferenciaLigaExcesiva,
}

class RoboResult {
  final bool permitido;
  final RoboRazon razon;
  final int diasProteccionRestantes;
  final LeagueInfo? ligaAtacante;
  final LeagueInfo? ligaDefensor;

  const RoboResult({
    required this.permitido,
    required this.razon,
    this.diasProteccionRestantes = 0,
    this.ligaAtacante,
    this.ligaDefensor,
  });
}

// =============================================================================
// LEAGUE SERVICE
// =============================================================================

class LeagueService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Protección ─────────────────────────────────────────────────────────────

  static Future<bool> tieneProteccion(String userId) async {
    try {
      final doc = await _db.collection('players').doc(userId).get();
      if (!doc.exists) return false;
      final ts = doc.data()?['proteccion_hasta'] as Timestamp?;
      if (ts == null) return false;
      return ts.toDate().isAfter(DateTime.now());
    } catch (e) {
      debugPrint('Error comprobando protección: $e');
      return false;
    }
  }

  static Future<int> diasProteccionRestantes(String userId) async {
    try {
      final doc = await _db.collection('players').doc(userId).get();
      if (!doc.exists) return 0;
      final ts = doc.data()?['proteccion_hasta'] as Timestamp?;
      if (ts == null) return 0;
      final hasta = ts.toDate();
      if (hasta.isBefore(DateTime.now())) return 0;
      return hasta.difference(DateTime.now()).inDays + 1;
    } catch (_) {
      return 0;
    }
  }

  // ── Comprobación de robo ───────────────────────────────────────────────────

  static Future<RoboResult> puedeRobarTerritorio({
    required String atacanteId,
    required String defensorId,
  }) async {
    try {
      if (await tieneProteccion(defensorId)) {
        final dias = await diasProteccionRestantes(defensorId);
        return RoboResult(
          permitido: false,
          razon: RoboRazon.defensorProtegido,
          diasProteccionRestantes: dias,
        );
      }

      final results = await Future.wait([
        _db.collection('players').doc(atacanteId).get(),
        _db.collection('players').doc(defensorId).get(),
      ]);

      final atacanteDoc = results[0];
      final defensorDoc = results[1];

      if (!atacanteDoc.exists || !defensorDoc.exists) {
        return const RoboResult(permitido: true, razon: RoboRazon.permitido);
      }

      final int ptsAtacante =
          (atacanteDoc.data()?['puntos_liga'] as num?)?.toInt() ?? 0;
      final int ptsDefensor =
          (defensorDoc.data()?['puntos_liga'] as num?)?.toInt() ?? 0;

      final ligaAtacante = LeagueSystem.calcularLigaPorPuntos(ptsAtacante);
      final ligaDefensor = LeagueSystem.calcularLigaPorPuntos(ptsDefensor);

      if (LeagueSystem.indice(ligaAtacante.id) -
              LeagueSystem.indice(ligaDefensor.id) >=
          2) {
        return RoboResult(
          permitido: false,
          razon: RoboRazon.diferenciaLigaExcesiva,
          ligaAtacante: ligaAtacante,
          ligaDefensor: ligaDefensor,
        );
      }

      return const RoboResult(permitido: true, razon: RoboRazon.permitido);
    } catch (e) {
      debugPrint('Error comprobando robo: $e');
      return const RoboResult(permitido: true, razon: RoboRazon.permitido);
    }
  }

  // ── Sumar puntos de liga — Cloud Function transaccional ─────────────────────
  //
  //  El servidor calcula el delta a partir de los datos brutos de la
  //  actividad (nunca confía en un número ya calculado por el cliente) y
  //  aplica el mismo umbral de liga que LeagueSystem.calcularLigaPorPuntos.
  //
  static final _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

  static Future<LeagueInfo?> sumarPuntosLigaCarrera({
    required String userId,
    required double distanciaKm,
    required int territoriosConquistados,
  }) async {
    try {
      final result = await _functions.httpsCallable('sumarPuntosLigaJugador').call({
        'motivo':                  'carrera_competitiva',
        'distanciaKm':             distanciaKm,
        'territoriosConquistados': territoriosConquistados,
      });
      return _leagueInfoSiCambio(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Error sumarPuntosLigaCarrera (${e.code}): ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Error sumarPuntosLigaCarrera: $e');
      return null;
    }
  }

  static Future<LeagueInfo?> sumarPuntosLigaRuta({
    required String userId,
    required double distanciaKm,
    required double ritmoMinKm,
  }) async {
    try {
      final result = await _functions.httpsCallable('sumarPuntosLigaJugador').call({
        'motivo':      'ruta_guardada',
        'distanciaKm': distanciaKm,
        'ritmoMinKm':  ritmoMinKm,
      });
      return _leagueInfoSiCambio(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Error sumarPuntosLigaRuta (${e.code}): ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Error sumarPuntosLigaRuta: $e');
      return null;
    }
  }

  static LeagueInfo? _leagueInfoSiCambio(Map<Object?, Object?> data) {
    if (data['ligaCambio'] != true) return null;
    return LeagueSystem.ligas.firstWhere(
      (l) => l.id == data['liga'],
      orElse: () => LeagueSystem.ligas.first,
    );
  }

  // ── Datos completos de liga para UI ───────────────────────────────────────

  static Future<Map<String, dynamic>> obtenerDatosLiga(
      String userId) async {
    try {
      final doc = await _db.collection('players').doc(userId).get();
      if (!doc.exists) return {};
      final data = doc.data()!;
      final int puntos = (data['puntos_liga'] as num?)?.toInt() ?? 0;
      final int monedas = (data['monedas'] as num?)?.toInt() ?? 0;
      final liga = LeagueSystem.calcularLigaPorPuntos(puntos);
      return {
        'liga': liga,
        'puntos_liga': puntos,
        'monedas': monedas,
        'progreso': LeagueSystem.progresoDentroLiga(puntos),
        'puntosParaSiguiente':
            LeagueSystem.puntosParaSiguienteLiga(puntos),
        'proteccionHasta': data['proteccion_hasta'] as Timestamp?,
      };
    } catch (_) {
      return {};
    }
  }

  // ── Migración ──────────────────────────────────────────────────────────────

  static Future<void> migrarJugadoresSinLiga() async {
    try {
      final snap = await _db.collection('players').get();
      final batch = _db.batch();
      int count = 0;

      for (final doc in snap.docs) {
        final data = doc.data();
        final bool tienePuntos = data.containsKey('puntos_liga');
        final bool tieneLiga = data.containsKey('liga');

        if (tienePuntos && tieneLiga) continue;

        final int monedas = (data['monedas'] as num?)?.toInt() ?? 0;
        final int ptsIniciales = (monedas ~/ 10).clamp(0, 999999);
        final liga = LeagueSystem.calcularLigaPorPuntos(ptsIniciales);

        batch.update(doc.reference, {
          if (!tienePuntos) 'puntos_liga': ptsIniciales,
          if (!tieneLiga) 'liga': liga.id,
        });
        count++;
      }

      await batch.commit();
      debugPrint('Migración completada: $count jugadores actualizados');
    } catch (e) {
      debugPrint('Error en migración: $e');
    }
  }
}