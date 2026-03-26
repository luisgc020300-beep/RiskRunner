// lib/services/territory_service.dart
//
// ── OPTIMIZACIONES v6 ──────────────────────────────────────────────────────
//  NUEVO en v6 respecto a v5:
//    • renombrarTerritorio — llama a la Cloud Function "renombrarTerritorio".
//      El servidor valida: ownership + longitud + caracteres + lista negra.
//      El cliente nunca escribe nombre_territorio directamente a Firestore.
//
//  MANTENIDO de v5:
//    • conquistarTerritorio via Cloud Function
//
//  MANTENIDO de v4:
//    • caché estático TTL 2 min + invalidación por push
//    • invalidarCachePorConquista() alias semántico
//    • cargarTodosLosTerritorios con filtro geográfico opcional
//    • whereIn en chunks de 10
// ─────────────────────────────────────────────────────────────────────────────

import 'package:RiskRunner/services/clan_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import 'league_service.dart';

const int kDiasParaDeterioroVisual    = 5;
const int kDiasParaDeterioroFuncional = 10;
const double kAreaMinimaM2            = 2000.0;
const double kMultiplicadorMonedasSolitario   = 0.65;
const double kMultiplicadorMonedasCompetitivo = 1.00;
const int kDiasParaSerRey = 14;

double multiplicadorMonedas(bool esSolitario) =>
    esSolitario ? kMultiplicadorMonedasSolitario : kMultiplicadorMonedasCompetitivo;

class TerritoryData {
  final String docId;
  final String ownerId;
  final String ownerNickname;
  final Color color;
  final List<LatLng> puntos;
  final LatLng centro;
  final DateTime? ultimaVisita;
  final bool esMio;
  final String? reyId;
  final String? reyNickname;
  final DateTime? reyDesde;
  final String? nombreTerritorio;

  TerritoryData({
    required this.docId,
    required this.ownerId,
    required this.ownerNickname,
    required this.color,
    required this.puntos,
    required this.centro,
    required this.esMio,
    this.ultimaVisita,
    this.reyId,
    this.reyNickname,
    this.reyDesde,
    this.nombreTerritorio,
  });

  int get diasSinVisitar {
    if (ultimaVisita == null) return 0;
    return DateTime.now().difference(ultimaVisita!).inDays;
  }

  bool get estaDeterirado          => diasSinVisitar >= kDiasParaDeterioroVisual;
  bool get esConquistableSinPasar  => diasSinVisitar >= kDiasParaDeterioroFuncional;

  double get opacidadRelleno {
    if (diasSinVisitar >= kDiasParaDeterioroFuncional) return 0.12;
    if (diasSinVisitar >= kDiasParaDeterioroVisual)    return 0.22;
    return 0.45;
  }

  double get opacidadBorde {
    if (diasSinVisitar >= kDiasParaDeterioroFuncional) return 0.3;
    if (diasSinVisitar >= kDiasParaDeterioroVisual)    return 0.55;
    return 1.0;
  }

  bool get tieneRey => reyId != null && reyId!.isNotEmpty;

  int get diasComoRey {
    if (reyDesde == null) return 0;
    return DateTime.now().difference(reyDesde!).inDays;
  }

  double get progresoHaciaRey {
    if (tieneRey) return 1.0;
    return 0.0;
  }
}

class TerritoryService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── CACHÉ ESTÁTICO con TTL 2 minutos ─────────────────────────────────────
  static List<TerritoryData>? _cachedTerritorios;
  static DateTime? _cacheTimestamp;
  static const Duration _cacheTTL = Duration(minutes: 2);

  static void invalidarCache() {
    _cachedTerritorios = null;
    _cacheTimestamp    = null;
    debugPrint('🗑️ TerritoryService: caché invalidado');
  }

  static void invalidarCachePorConquista() {
    debugPrint('⚔️ TerritoryService: caché invalidado por conquista externa');
    invalidarCache();
  }

  static bool get _cacheValido {
    if (_cachedTerritorios == null || _cacheTimestamp == null) return false;
    return DateTime.now().difference(_cacheTimestamp!) < _cacheTTL;
  }

  // ── Calcular área ─────────────────────────────────────────────────────────
  static double calcularAreaM2(List<LatLng> puntos) {
    if (puntos.length < 3) return 0;
    final latRef = puntos.map((p) => p.latitude).reduce((a, b) => a + b) / puntos.length;
    final cosLat = math.cos(latRef * math.pi / 180);
    double area = 0;
    final int n = puntos.length;
    for (int i = 0; i < n; i++) {
      final j  = (i + 1) % n;
      final xi = puntos[i].longitude * 111320 * cosLat;
      final yi = puntos[i].latitude  * 111320;
      final xj = puntos[j].longitude * 111320 * cosLat;
      final yj = puntos[j].latitude  * 111320;
      area += xi * yj - xj * yi;
    }
    return (area / 2).abs();
  }

  // ── Crear territorio solitario ────────────────────────────────────────────
  static Future<bool> crearTerritorioSolitario({
    required List<LatLng> ruta,
    required Color colorTerritorio,
    required String nickname,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || ruta.length < 3) return false;

    final areaM2 = calcularAreaM2(ruta);
    if (areaM2 < kAreaMinimaM2) {
      debugPrint('Área insuficiente: ${areaM2.toStringAsFixed(0)} m²');
      return false;
    }

    try {
      final puntosList = ruta.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
      final latC = ruta.map((p) => p.latitude).reduce((a, b) => a + b) / ruta.length;
      final lngC = ruta.map((p) => p.longitude).reduce((a, b) => a + b) / ruta.length;

      await _db.collection('territories').add({
        'userId':            user.uid,
        'nickname':          nickname,
        'puntos':            puntosList,
        'centro':            {'lat': latC, 'lng': lngC},
        'color':             colorTerritorio.value,
        'ultima_visita':     FieldValue.serverTimestamp(),
        'fecha_creacion':    FieldValue.serverTimestamp(),
        'fecha_desde_dueno': FieldValue.serverTimestamp(),
        'modo':              'solitario',
        'area_m2':           areaM2,
        'rey_id':            null,
        'rey_nickname':      null,
        'rey_desde':         null,
        'nombre_territorio': null,
        'centroLat':         latC,
        'centroLng':         lngC,
      });

      invalidarCache();
      return true;
    } catch (e) {
      debugPrint('❌ Error creando territorio: $e');
      return false;
    }
  }

  // ── OPTIMIZADO v4: caché 2 min + filtro geográfico opcional ──────────────
  static Future<List<TerritoryData>> cargarTodosLosTerritorios({
    LatLng? centro,
  }) async {
    if (_cacheValido) {
      debugPrint('✅ TerritoryService: caché hit (${_cachedTerritorios!.length} territorios)');
      return _cachedTerritorios!;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    // 1. Ids de amigos
    final friendsSnap = await _db
        .collection('friendships')
        .where('status', isEqualTo: 'accepted')
        .get();

    final List<String> amigoIds = [];
    for (final doc in friendsSnap.docs) {
      final data = doc.data();
      if (data['senderId'] == user.uid) {
        amigoIds.add(data['receiverId'] as String);
      } else if (data['receiverId'] == user.uid) {
        amigoIds.add(data['senderId'] as String);
      }
    }

    final List<String> todosIds = [user.uid, ...amigoIds];

    // 2. Players en chunks de 10
    final Map<String, Map<String, dynamic>> playerDataMap = {};
    for (int i = 0; i < todosIds.length; i += 10) {
      final chunk = todosIds.sublist(i, (i + 10).clamp(0, todosIds.length));
      final snap = await _db
          .collection('players')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        playerDataMap[doc.id] = doc.data();
      }
    }

    // 3. Territorios en chunks de 10 con filtro geográfico opcional
    const double kRadGrados = 0.09; // ~10 km
    final List<TerritoryData> resultado = [];

    for (int i = 0; i < todosIds.length; i += 10) {
      final chunk = todosIds.sublist(i, (i + 10).clamp(0, todosIds.length));

      Query<Map<String, dynamic>> query = _db
          .collection('territories')
          .where('userId', whereIn: chunk);

      if (centro != null) {
        query = query
            .where('centroLat', isGreaterThan: centro.latitude  - kRadGrados)
            .where('centroLat', isLessThan:    centro.latitude  + kRadGrados);
      }

      final territoriosSnap = await query.get();

      for (final doc in territoriosSnap.docs) {
        final data      = doc.data();
        final uid       = data['userId'] as String? ?? '';
        final rawPuntos = data['puntos'] as List<dynamic>?;
        if (rawPuntos == null || rawPuntos.isEmpty) continue;

        final List<LatLng> puntos = rawPuntos.map((p) {
          final m = p as Map<String, dynamic>;
          return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
        }).toList();

        final double latC = puntos.map((p) => p.latitude).reduce((a, b) => a + b) / puntos.length;
        final double lngC = puntos.map((p) => p.longitude).reduce((a, b) => a + b) / puntos.length;

        if (centro != null) {
          final storeLng = (data['centroLng'] as num?)?.toDouble() ?? lngC;
          if ((storeLng - centro.longitude).abs() > kRadGrados) continue;
        }

        final playerData = playerDataMap[uid];
        final colorInt   = (playerData?['territorio_color'] as num?)?.toInt();
        final color      = colorInt != null
            ? Color(colorInt)
            : (uid == user.uid ? Colors.orange : Colors.blue);
        final nickPlayer = playerData?['nickname'] as String? ?? '';

        DateTime? ultimaVisita;
        final tsRaw = data['ultima_visita'];
        if (tsRaw is Timestamp) ultimaVisita = tsRaw.toDate();

        DateTime? reyDesde;
        final reyDesdeRaw = data['rey_desde'];
        if (reyDesdeRaw is Timestamp) reyDesde = reyDesdeRaw.toDate();

        resultado.add(TerritoryData(
          docId:            doc.id,
          ownerId:          uid,
          ownerNickname:    nickPlayer,
          color:            color,
          puntos:           puntos,
          centro:           LatLng(latC, lngC),
          esMio:            uid == user.uid,
          ultimaVisita:     ultimaVisita,
          reyId:            data['rey_id'] as String?,
          reyNickname:      data['rey_nickname'] as String?,
          reyDesde:         reyDesde,
          nombreTerritorio: data['nombre_territorio'] as String?,
        ));
      }
    }

    _cachedTerritorios = resultado;
    _cacheTimestamp    = DateTime.now();
    debugPrint('💾 TerritoryService: caché actualizado (${resultado.length} territorios)');

    return resultado;
  }

  // ── Actualizar última visita ──────────────────────────────────────────────
  static Future<void> actualizarUltimaVisita(String docId) async {
    try {
      await _db.collection('territories').doc(docId).update({
        'ultima_visita': FieldValue.serverTimestamp(),
      });
      invalidarCache();
      await _comprobarYCoronarRey(docId);
    } catch (e) {
      debugPrint('Error actualizando ultima_visita: $e');
    }
  }

  static Future<void> _comprobarYCoronarRey(String docId) async {
    try {
      final doc = await _db.collection('territories').doc(docId).get();
      if (!doc.exists) return;
      final data = doc.data()!;

      final reyExistente = data['rey_id'] as String?;
      if (reyExistente != null && reyExistente.isNotEmpty) return;

      final userId   = data['userId'] as String?;
      final nickname = data['nickname'] as String? ?? '';
      if (userId == null) return;

      final fechaDesdeDueno = data['fecha_desde_dueno'] as Timestamp?;
      if (fechaDesdeDueno == null) return;

      final diasControlado = DateTime.now().difference(fechaDesdeDueno.toDate()).inDays;

      if (diasControlado >= kDiasParaSerRey) {
        await _db.collection('territories').doc(docId).update({
          'rey_id':       userId,
          'rey_nickname': nickname,
          'rey_desde':    FieldValue.serverTimestamp(),
        });

        await _db.collection('notifications').add({
          'toUserId':  userId,
          'type':      'territory_king',
          'message':   '👑 ¡Has sido coronado Rey de uno de tus territorios! '
                       'Llevas $diasControlado días dominando esta zona.',
          'read':      false,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Error comprobando Rey: $e');
    }
  }

  static TerritoryData? territorioEnPosicion(
      List<TerritoryData> territorios, LatLng posicion) {
    for (final t in territorios) {
      if (_puntoEnPoligono(posicion, t.puntos)) return t;
    }
    return null;
  }

  static bool _puntoEnPoligono(LatLng punto, List<LatLng> poligono) {
    int intersecciones = 0;
    final int n = poligono.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final double xi = poligono[i].longitude;
      final double yi = poligono[i].latitude;
      final double xj = poligono[j].longitude;
      final double yj = poligono[j].latitude;
      final bool cruza =
          ((yi > punto.latitude) != (yj > punto.latitude)) &&
          (punto.longitude < (xj - xi) * (punto.latitude - yi) / (yj - yi) + xi);
      if (cruza) intersecciones++;
    }
    return intersecciones % 2 == 1;
  }

  static Future<RoboResult> puedeRobarTerritorio({
    required String atacanteId,
    required String defensorId,
  }) async {
    return LeagueService.puedeRobarTerritorio(
      atacanteId: atacanteId,
      defensorId: defensorId,
    );
  }

  // ── NUEVO v5: conquista via Cloud Function ────────────────────────────────
  //
  // El servidor valida:
  //   1. El territorio existe
  //   2. El atacante no es el dueño actual
  //   3. El territorio lleva >= 10 días sin visita
  //   4. El usuario está físicamente a <= 200 m del centro
  //
  // Returns true si la conquista fue exitosa, false en caso de error.
  // Lanza una excepción con mensaje legible si la validación falla.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<bool> conquistarTerritorio({
    required String docId,
    required String duenoAnteriorId,
    required double latUsuario,
    required double lngUsuario,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    // Si es nuestro propio territorio, solo visitamos (sin llamar a la Function)
    if (duenoAnteriorId == user.uid) {
      await actualizarUltimaVisita(docId);
      return true;
    }

    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('conquistarTerritorio');

      final result = await callable.call<Map<String, dynamic>>({
        'docId':      docId,
        'latUsuario': latUsuario,
        'lngUsuario': lngUsuario,
      });

      final data   = result.data;
      final ok     = data['ok'] as bool? ?? false;
      final accion = data['accion'] as String? ?? '';

      if (ok) {
        invalidarCache();
        debugPrint('⚔️ Conquista exitosa: $accion en $docId');
      }

      return ok;
    } on FirebaseFunctionsException catch (e) {
      // El mensaje viene del servidor — mostrárselo al usuario directamente
      debugPrint('❌ conquistarTerritorio [${e.code}]: ${e.message}');
      rethrow; // el caller puede capturarlo y mostrarlo en un SnackBar
    } catch (e) {
      debugPrint('❌ Error inesperado en conquistarTerritorio: $e');
      return false;
    }
  }

  // ── NUEVO v6: renombrar territorio via Cloud Function ────────────────────
  //
  // El servidor valida:
  //   1. El usuario es el dueño del territorio
  //   2. Longitud 1-30 caracteres
  //   3. Solo caracteres permitidos (letras, números, espacios, - ' . , ! ?)
  //   4. Sin palabras de la lista negra
  //
  // Lanza FirebaseFunctionsException con mensaje legible si falla.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<String> renombrarTerritorio({
    required String docId,
    required String nombre,
  }) async {
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('renombrarTerritorio');

      final result = await callable.call<Map<String, dynamic>>({
        'docId':  docId,
        'nombre': nombre,
      });

      final nombreGuardado = result.data['nombre'] as String? ?? nombre;
      invalidarCache();
      debugPrint('✏️ Territorio $docId renombrado: $nombreGuardado');
      return nombreGuardado;

    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ renombrarTerritorio [${e.code}]: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ Error inesperado en renombrarTerritorio: $e');
      rethrow;
    }
  }

  static Future<void> crearNotificacionInvasion({
    required String toUserId,
    required String fromNickname,
    required String territoryId,
  }) async {
    try {
      final hace10min = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 10)));
      final recientes = await _db
          .collection('notifications')
          .where('toUserId', isEqualTo: toUserId)
          .where('type', isEqualTo: 'territory_invasion')
          .where('timestamp', isGreaterThan: hace10min)
          .get();
      if (recientes.docs.isNotEmpty) return;

      await _db.collection('notifications').add({
        'toUserId':     toUserId,
        'fromNickname': fromNickname,
        'type':         'territory_invasion',
        'message':      '⚔️ $fromNickname está invadiendo tu territorio AHORA MISMO. '
                        '¡Sal a defenderlo!',
        'territoryId':  territoryId,
        'read':         false,
        'timestamp':    FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error creando notificación de invasión: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> obtenerReyes({int limit = 20}) async {
    try {
      final snap = await _db
          .collection('territories')
          .where('rey_id', isNull: false)
          .limit(limit)
          .get();
      return snap.docs.map((doc) {
        final d = doc.data();
        return {
          'docId':       doc.id,
          'reyId':       d['rey_id'] as String? ?? '',
          'reyNickname': d['rey_nickname'] as String? ?? '',
          'reyDesde':    d['rey_desde'] as Timestamp?,
          'nombre':      d['nombre_territorio'] as String?,
          'color':       (d['color'] as num?)?.toInt() ?? 0xFFCC7C3A,
        };
      }).where((m) => (m['reyId'] as String).isNotEmpty).toList();
    } catch (e) {
      debugPrint('Error obteniendo reyes: $e');
      return [];
    }
  }

  static Future<int> contarReinosDe(String userId) async {
    try {
      final snap = await _db
          .collection('territories')
          .where('rey_id', isEqualTo: userId)
          .get();
      return snap.docs.length;
    } catch (e) {
      debugPrint('Error contando reinos: $e');
      return 0;
    }
  }
}