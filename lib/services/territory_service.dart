// lib/services/territory_service.dart
//
// ── v7: SISTEMA DE HP ─────────────────────────────────────────────────────────
//
//  NUEVO en v7:
//    • TerritoryData incluye hp, hpMax, velocidadConquistaKmh
//    • hpActual() — calcula el HP real en este momento (con decay)
//    • estadoHp — enum: saludable / dañado / critico / muerto
//    • atacarTerritorio() — llama a la Cloud Function 'atacarTerritorio'
//    • reforzarTerritorio() — visitar el propio territorio sube HP a 100
//
//  MANTENIDO de v6:
//    • renombrarTerritorio via Cloud Function
//    • conquistarTerritorio via Cloud Function (para territorios legacy sin HP)
//    • caché estático TTL 2 min + invalidación por push
//    • cargarTodosLosTerritorios con filtro geográfico opcional
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import 'league_service.dart';

// ── Constantes ────────────────────────────────────────────────────────────────
/// userId reservado para territorios fantasma (bots de relleno).
/// No corresponde a ninguna cuenta de Firebase Auth.
const String kGhostUserId = 'ghost_system';

const int kDiasParaDeterioroVisual       = 5;
const int kDiasParaDeterioroFuncional    = 10;
const double kAreaMinimaM2               = 2000.0;
const double kMultiplicadorMonedasSolitario   = 0.65;
const double kMultiplicadorMonedasCompetitivo = 1.00;
const int kDiasParaSerRey                = 14;

// HP
const int kHpMax              = 100;
const double kHpDecayPorDia   = 100 / 7; // muere en 7 días sin visita

double multiplicadorMonedas(bool esSolitario) =>
    esSolitario ? kMultiplicadorMonedasSolitario : kMultiplicadorMonedasCompetitivo;

// ── Estado de HP ──────────────────────────────────────────────────────────────
enum EstadoHp {
  saludable,  // 70-100 HP  — color verde/dorado
  danado,     // 30-69 HP   — color naranja
  critico,    // 1-29 HP    — color rojo
}

// ── Resultado de ataque ───────────────────────────────────────────────────────
class AtaqueResult {
  final bool ok;
  final String accion;      // 'sin_daño' | 'daño' | 'conquista_total' | 'robo_parcial'
  final int hpAntes;
  final int hpDespues;
  final int danio;
  final int monedasBotin;
  final String mensaje;
  final String? territorioRobadoId;

  const AtaqueResult({
    required this.ok,
    required this.accion,
    required this.hpAntes,
    required this.hpDespues,
    required this.danio,
    required this.monedasBotin,
    required this.mensaje,
    this.territorioRobadoId,
  });

  factory AtaqueResult.fromMap(Map<String, dynamic> m) => AtaqueResult(
    ok:                 m['ok'] as bool? ?? false,
    accion:             m['accion'] as String? ?? 'sin_daño',
    hpAntes:            (m['hpAntes'] as num?)?.toInt() ?? 0,
    hpDespues:          (m['hpDespues'] as num?)?.toInt() ?? 0,
    danio:              (m['danio'] as num?)?.toInt() ?? 0,
    monedasBotin:       (m['monedasBotin'] as num?)?.toInt() ?? 0,
    mensaje:            m['mensaje'] as String? ?? '',
    territorioRobadoId: m['territorioRobadoId'] as String?,
  );

  bool get conquistoAlgo =>
      accion == 'conquista_total' || accion == 'robo_parcial';
}

// ══════════════════════════════════════════════════════════════════════════════
// TERRITORY DATA
// ══════════════════════════════════════════════════════════════════════════════
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
  final DateTime? fechaDesdeDueno;
  final String? nombreTerritorio;

  // ── Escudo ────────────────────────────────────────────────────────────────
  final bool escudoActivo;
  final DateTime? escudoExpira;

  // ── HP ────────────────────────────────────────────────────────────────────
  /// HP guardado en Firestore en el momento de la última actualización
  final int hpGuardado;
  /// Momento en que se guardó ese HP (para calcular el decay)
  final DateTime? ultimaActualizacionHp;
  /// Velocidad del dueño cuando conquistó este territorio (km/h)
  final double velocidadConquistaKmh;

  /// true → territorio fantasma local (solo visual, no existe en Firestore)
  final bool esFantasma;

  /// 'competitivo' | 'solitario' | null (legacy = competitivo)
  final String? modo;

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
    this.hpGuardado = kHpMax,
    this.ultimaActualizacionHp,
    this.velocidadConquistaKmh = 5.0,
    this.esFantasma = false,
    this.fechaDesdeDueno,
    this.escudoActivo = false,
    this.escudoExpira,
    this.modo,
  });

  // ── HP calculado en tiempo real ───────────────────────────────────────────
 int get hpActual {
  final referencia = ultimaActualizacionHp ?? ultimaVisita ?? DateTime.now();
  final horasTranscurridas =
      DateTime.now().difference(referencia).inMinutes / 60.0;
  final decayPorHora = kHpDecayPorDia / 24.0;
  final hp = (hpGuardado - decayPorHora * horasTranscurridas).round();
  return hp.clamp(1, kHpMax); // ← mínimo 1, nunca muere solo
}

  EstadoHp get estadoHp {
  final hp = hpActual;
  if (hp <= 29)  return EstadoHp.critico;  // Leve — grietas
  if (hp <= 69)  return EstadoHp.danado;   // Medio — transparente
  return EstadoHp.saludable;               // Fuerte — sólido
}

  /// Color visual del borde según estado HP
  Color get colorEstadoHp {
  switch (estadoHp) {
    case EstadoHp.saludable: return color;
    case EstadoHp.danado:    return const Color(0xFFFF9800);
    case EstadoHp.critico:   return const Color(0xFFCC2222);
  }
}

double get opacidadRelleno {
  switch (estadoHp) {
    case EstadoHp.saludable: return esMio ? 0.32 : 0.20;
    case EstadoHp.danado:    return esMio ? 0.20 : 0.13;
    case EstadoHp.critico:   return esMio ? 0.10 : 0.06;
  }
}

double get opacidadBorde {
  switch (estadoHp) {
    case EstadoHp.saludable: return esMio ? 0.95 : 0.70;
    case EstadoHp.danado:    return esMio ? 0.75 : 0.45;
    case EstadoHp.critico:   return esMio ? 0.50 : 0.25;
  }
}

  // ── Compatibilidad con código previo ──────────────────────────────────────
  int get diasSinVisitar {
    if (ultimaVisita == null) return 0;
    return DateTime.now().difference(ultimaVisita!).inDays;
  }

  bool get estaDeterirado         => estadoHp == EstadoHp.danado || estadoHp == EstadoHp.critico;
  bool get esConquistableSinPasar => estadoHp == EstadoHp.critico;

  bool get tieneRey => reyId != null && reyId!.isNotEmpty;

  int get diasComoRey {
    if (reyDesde == null) return 0;
    return DateTime.now().difference(reyDesde!).inDays;
  }

  /// Progreso hacia la corona (0.0–1.0). Llega a 1.0 en kDiasParaSerRey días.
  double get progresoHaciaRey {
    if (tieneRey) return 1.0;
    if (fechaDesdeDueno == null) return 0.0;
    final dias = DateTime.now().difference(fechaDesdeDueno!).inDays;
    return (dias / kDiasParaSerRey).clamp(0.0, 1.0);
  }

  bool get escudoVigente =>
      escudoActivo && escudoExpira != null && escudoExpira!.isAfter(DateTime.now());
}

// ══════════════════════════════════════════════════════════════════════════════
// TERRITORY SERVICE
// ══════════════════════════════════════════════════════════════════════════════
class TerritoryService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Caché TTL 2 min ───────────────────────────────────────────────────────
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

  static bool get cacheValido => _cacheValido;

  // ── Calcular área ─────────────────────────────────────────────────────────
  static double calcularAreaM2(List<LatLng> puntos) {
    if (puntos.length < 3) return 0;
    final latRef = puntos.map((p) => p.latitude).reduce((a, b) => a + b) / puntos.length;
    final cosLat = math.cos(latRef * math.pi / 180);
    double area  = 0;
    final int n  = puntos.length;
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

  // ══════════════════════════════════════════════════════════════════════════
  // ATACAR TERRITORIO — llama a la Cloud Function
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Parámetros:
  //   territorioDefensorId — docId del territorio enemigo
  //   rutaAtacante         — la ruta GPS del atacante en esta sesión
  //   velocidadMediaKmh    — velocidad media de la carrera del atacante
  //
  // Devuelve un AtaqueResult con el resultado detallado.
  // Lanza FirebaseFunctionsException con mensaje legible si algo falla.
  // ────────────────────────────────────────────────────────────────────────
  static Future<AtaqueResult> atacarTerritorio({
    required String territorioDefensorId,
    required List<LatLng> rutaAtacante,
    required double velocidadMediaKmh,
  }) async {
    if (rutaAtacante.length < 3) {
      return const AtaqueResult(
        ok: false, accion: 'sin_daño', hpAntes: 0, hpDespues: 0,
        danio: 0, monedasBotin: 0, mensaje: 'Ruta insuficiente.',
      );
    }

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('atacarTerritorio');

      final result = await callable.call<Map<String, dynamic>>({
        'territorioDefensorId': territorioDefensorId,
        'rutaAtacante': rutaAtacante
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'velocidadMediaAtacanteKmh': velocidadMediaKmh,
      });

      final ataque = AtaqueResult.fromMap(
          Map<String, dynamic>.from(result.data as Map));

      if (ataque.conquistoAlgo) invalidarCache();
      return ataque;

    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ atacarTerritorio [${e.code}]: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ Error inesperado en atacarTerritorio: $e');
      return AtaqueResult(
        ok: false, accion: 'sin_daño', hpAntes: 0, hpDespues: 0,
        danio: 0, monedasBotin: 0, mensaje: 'Error: $e',
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // REFORZAR TERRITORIO PROPIO — sube HP a 100 al visitarlo
  // ══════════════════════════════════════════════════════════════════════════
 static Future<void> reforzarTerritorio(String docId) async {
  try {
    // Primero leemos el HP actual para decidir a dónde sube
    final doc = await _db.collection('territories').doc(docId).get();
    if (!doc.exists) return;
    final data = doc.data()!;

    // Calculamos HP actual con decay
    final tsHp = data['ultimaActualizacionHp'] as Timestamp?;
    final tsVisita = data['ultima_visita'] as Timestamp?;
    final referencia = tsHp?.toDate() ?? tsVisita?.toDate() ?? DateTime.now();
    final horasTranscurridas = DateTime.now().difference(referencia).inMinutes / 60.0;
    final decayPorHora = kHpDecayPorDia / 24.0;
    final hpGuardado = (data['hp'] as num?)?.toInt() ?? kHpMax;
    final hpActual = (hpGuardado - decayPorHora * horasTranscurridas)
        .round()
        .clamp(1, kHpMax);

    // Leve (1-29) → sube a Medio (30)
    // Medio (30-69) → sube a Fuerte (100)
    // Fuerte (70-100) → sube a 100
    final int nuevoHp = hpActual < 30 ? 30 : 100;

    await _db.collection('territories').doc(docId).update({
      'hp':                    nuevoHp,
      'ultimaActualizacionHp': FieldValue.serverTimestamp(),
      'ultima_visita':         FieldValue.serverTimestamp(),
    });
    invalidarCache();
    debugPrint('🛡️ Territorio $docId reforzado: $hpActual → $nuevoHp HP');
    await _comprobarYCoronarRey(docId);
  } catch (e) {
    debugPrint('Error reforzando territorio: $e');
  }
}

  // ── Crear territorio solitario ────────────────────────────────────────────
  static Future<bool> crearTerritorioSolitario({
    required List<LatLng> ruta,
    required Color colorTerritorio,
    required String nickname,
    double velocidadMediaKmh = 5.0,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || ruta.length < 3) return false;

    final areaM2 = calcularAreaM2(ruta);
    if (areaM2 < kAreaMinimaM2) {
      debugPrint('Área insuficiente: ${areaM2.toStringAsFixed(0)} m²');
      return false;
    }

    try {
      final puntosList = ruta
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList();
      final latC = ruta.map((p) => p.latitude).reduce((a, b) => a + b) / ruta.length;
      final lngC = ruta.map((p) => p.longitude).reduce((a, b) => a + b) / ruta.length;

      await _db.collection('territories').add({
        'userId':                  user.uid,
        'nickname':                nickname,
        'puntos':                  puntosList,
        'centro':                  {'lat': latC, 'lng': lngC},
        'color':                   colorTerritorio.value,
        'ultima_visita':           FieldValue.serverTimestamp(),
        'fecha_creacion':          FieldValue.serverTimestamp(),
        'fecha_desde_dueno':       FieldValue.serverTimestamp(),
        'modo':                    'solitario',
        'area_m2':                 areaM2,
        // HP
        'hp':                      kHpMax,
        'hpMax':                   kHpMax,
        'velocidadConquistaKmh':   velocidadMediaKmh,
        'ultimaActualizacionHp':   FieldValue.serverTimestamp(),
        // Rey
        'rey_id':                  null,
        'rey_nickname':            null,
        'rey_desde':               null,
        'nombre_territorio':       null,
        'centroLat':               latC,
        'centroLng':               lngC,
      });

      invalidarCache();
      return true;
    } catch (e) {
      debugPrint('❌ Error creando territorio: $e');
      return false;
    }
  }

  // ── Cargar todos los territorios (globales por posición GPS) ─────────────
  //
  // Carga TODOS los territorios dentro del radio geográfico, sin filtrar por
  // amistad. El usuario ve a todo el mundo; solo puede conquistar lo que
  // alcanza físicamente al correr.
  //
  // Si [centro] es null se devuelve solo el territorio propio (fallback seguro
  // para cuando la posición GPS aún no está disponible).
  // ──────────────────────────────────────────────────────────────────────────
  static List<TerritoryData> _filtrarPorModo(List<TerritoryData> lista, String modo) {
    if (modo == 'solitario') {
      // Solo territorios creados en modo solitario (propios + ajenos)
      return lista.where((t) => t.modo == 'solitario').toList();
    }
    // Competitivo: competitivos + legacy (null) — excluye todos los solitario
    return lista.where((t) => t.modo == null || t.modo == 'competitivo').toList();
  }

  static Future<List<TerritoryData>> cargarTodosLosTerritorios({
    LatLng? centro,
    String? modo,
  }) async {
    if (_cacheValido) {
      debugPrint('✅ TerritoryService: caché hit (${_cachedTerritorios!.length} territorios)');
      final cached = _cachedTerritorios!;
      return modo != null ? _filtrarPorModo(cached, modo) : cached;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    // ── Sin posición: solo territorios propios (arranque rápido) ─────────
    if (centro == null) {
      final snap = await _db
          .collection('territories')
          .where('userId', isEqualTo: user.uid)
          .get();
      final propios = _parsearDocs(snap.docs, user.uid, {});
      _cachedTerritorios = propios;
      _cacheTimestamp    = DateTime.now();
      return modo != null ? _filtrarPorModo(propios, modo) : propios;
    }

    // ── Con posición: query geográfica sin filtro de amistad ─────────────
    const double kRadGrados = 0.09; // ~10 km (se filtra lng en cliente)
    const int    kLimit     = 500;  // cap de seguridad

    final territoriosSnap = await _db
        .collection('territories')
        .where('centroLat', isGreaterThan: centro.latitude  - kRadGrados)
        .where('centroLat', isLessThan:    centro.latitude  + kRadGrados)
        .limit(kLimit)
        .get()
        .timeout(const Duration(seconds: 10));

    // Filtrar por longitud (Firestore no soporta rango en dos campos)
    final docsEnRango = territoriosSnap.docs.where((doc) {
      final data   = doc.data();
      final cLng   = (data['centroLng'] as num?)?.toDouble();
      if (cLng == null) return true; // sin centroLng: incluir y calcular abajo
      return (cLng - centro.longitude).abs() <= kRadGrados;
    }).toList();

    // Recoger UIDs únicos (excluyendo bot ghost que no tienen player doc)
    final Set<String> ownerIds = {};
    for (final doc in docsEnRango) {
      final uid = doc.data()['userId'] as String?;
      if (uid != null && uid != kGhostUserId) ownerIds.add(uid);
    }

    // Cargar player data en chunks de 30 (límite del SDK) en paralelo
    final Map<String, Map<String, dynamic>> playerDataMap = {};
    final uidList = ownerIds.toList();
    const int kChunk = 30;
    if (uidList.isNotEmpty) {
      final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
      for (int i = 0; i < uidList.length; i += kChunk) {
        final chunk = uidList.sublist(i, math.min(i + kChunk, uidList.length));
        futures.add(_db
            .collection('players')
            .where(FieldPath.documentId, whereIn: chunk)
            .get());
      }
      final results = await Future.wait(futures);
      for (final snap in results) {
        for (final doc in snap.docs) {
          playerDataMap[doc.id] = doc.data();
        }
      }
    }

    final resultado = _parsearDocs(docsEnRango, user.uid, playerDataMap);

    _cachedTerritorios = resultado;
    _cacheTimestamp    = DateTime.now();
    debugPrint('🌍 TerritoryService: ${resultado.length} territorios en radio de ${(kRadGrados * 111).round()} km');
    return modo != null ? _filtrarPorModo(resultado, modo) : resultado;
  }

  /// Carga puntos de todos los territorios para mostrar en el globo terráqueo.
  /// Devuelve mapas con {lat, lng, color (int), esMio (bool)}.
  /// Primero carga todos los propios, luego una muestra de los demás.
  static Future<List<Map<String, dynamic>>> cargarPuntosGlobo({String? modo}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final results  = <Map<String, dynamic>>[];
    final seenIds  = <String>{};

    void addPunto(QueryDocumentSnapshot<Map<String, dynamic>> doc, bool esMio) {
      if (!seenIds.add(doc.id)) return;
      final d = doc.data();
      // Filtrar por modo: solitario solo ve solitario; competitivo ve null+competitivo
      if (modo != null) {
        final docModo = d['modo'] as String?;
        final pasa = modo == 'solitario'
            ? docModo == 'solitario'
            : (docModo == null || docModo == 'competitivo');
        if (!pasa) return;
      }
      final lat = (d['centroLat'] as num?)?.toDouble();
      final lng = (d['centroLng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      results.add({
        'lat':   lat,
        'lng':   lng,
        'color': (d['color'] as num?)?.toInt() ?? 0xFFD4722A,
        'esMio': esMio,
      });
    }

    try {
      // Ambas queries en paralelo para reducir latencia
      final results2 = await Future.wait([
        _db.collection('territories').where('userId', isEqualTo: user.uid).get(),
        _db.collection('territories').limit(200).get(),
      ]).timeout(const Duration(seconds: 10));
      final propiosSnap = results2[0];
      final otrosSnap   = results2[1];

      for (final doc in propiosSnap.docs) {
        addPunto(doc, true);
      }
      for (final doc in otrosSnap.docs) {
        addPunto(doc, doc.data()['userId'] == user.uid);
      }
    } catch (e) {
      debugPrint('cargarPuntosGlobo: $e');
    }

    return results;
  }

  /// Convierte documentos Firestore en [TerritoryData].
  static List<TerritoryData> _parsearDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String myUid,
    Map<String, Map<String, dynamic>> playerDataMap,
  ) {
    final List<TerritoryData> resultado = [];

    for (final doc in docs) {
      final data      = doc.data();
      final uid       = data['userId'] as String? ?? '';
      final rawPuntos = data['puntos'] as List<dynamic>?;
      if (rawPuntos == null || rawPuntos.isEmpty) continue;

      final List<LatLng> puntos = rawPuntos.map((p) {
        final m = p as Map<String, dynamic>;
        return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
      }).toList();

      final double latC =
          puntos.map((p) => p.latitude).reduce((a, b) => a + b)  / puntos.length;
      final double lngC =
          puntos.map((p) => p.longitude).reduce((a, b) => a + b) / puntos.length;

      final bool esFantasmaDoc = uid == kGhostUserId;

      // Color: bots usan el valor almacenado; jugadores reales usan el del perfil
      Color color;
      String nickPlayer;
      if (esFantasmaDoc) {
        final colorInt = (data['color'] as num?)?.toInt();
        color      = colorInt != null ? Color(colorInt) : Colors.blueGrey;
        nickPlayer = data['nickname'] as String? ?? 'GhostBot';
      } else {
        final playerData = playerDataMap[uid];
        final colorInt   = (playerData?['territorio_color'] as num?)?.toInt();
        color      = colorInt != null
            ? Color(colorInt)
            : (uid == myUid ? Colors.orange : Colors.blue);
        nickPlayer = playerData?['nickname'] as String? ?? '';
      }

      DateTime? ultimaVisita;
      final tsRaw = data['ultima_visita'];
      if (tsRaw is Timestamp) ultimaVisita = tsRaw.toDate();

      DateTime? ultimaActualizacionHp;
      final tsHp = data['ultimaActualizacionHp'];
      if (tsHp is Timestamp) ultimaActualizacionHp = tsHp.toDate();

      DateTime? reyDesde;
      final reyDesdeRaw = data['rey_desde'];
      if (reyDesdeRaw is Timestamp) reyDesde = reyDesdeRaw.toDate();

      DateTime? fechaDesdeDueno;
      final fechaDesdeDuenoRaw = data['fecha_desde_dueno'];
      if (fechaDesdeDuenoRaw is Timestamp) fechaDesdeDueno = fechaDesdeDuenoRaw.toDate();

      final escudoActivo = data['escudo_activo'] as bool? ?? false;
      DateTime? escudoExpira;
      final escudoExpiraRaw = data['escudo_expira'];
      if (escudoExpiraRaw is Timestamp) escudoExpira = escudoExpiraRaw.toDate();

      int hpGuardado = kHpMax;
      if (data['hp'] != null) {
        hpGuardado = (data['hp'] as num).toInt();
      } else if (ultimaVisita != null) {
        final dias = DateTime.now().difference(ultimaVisita).inDays;
        hpGuardado = (kHpMax - kHpDecayPorDia * dias).round().clamp(0, kHpMax);
      }

      resultado.add(TerritoryData(
        docId:                  doc.id,
        ownerId:                uid,
        ownerNickname:          nickPlayer,
        color:                  color,
        puntos:                 puntos,
        centro:                 LatLng(latC, lngC),
        esMio:                  uid == myUid,
        esFantasma:             esFantasmaDoc,
        ultimaVisita:           ultimaVisita,
        reyId:                  data['rey_id'] as String?,
        reyNickname:            data['rey_nickname'] as String?,
        reyDesde:               reyDesde,
        nombreTerritorio:       data['nombre_territorio'] as String?,
        hpGuardado:             hpGuardado,
        ultimaActualizacionHp:  ultimaActualizacionHp,
        velocidadConquistaKmh:  (data['velocidadConquistaKmh'] as num?)?.toDouble() ?? 5.0,
        fechaDesdeDueno:        fechaDesdeDueno,
        escudoActivo:           escudoActivo,
        escudoExpira:           escudoExpira,
        modo:                   data['modo'] as String?,
      ));
    }

    return resultado;
  }

  // ── Actualizar última visita (legacy — usa reforzarTerritorio si es propio) ─
  static Future<void> actualizarUltimaVisita(String docId) async {
    await reforzarTerritorio(docId);
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

      final diasControlado =
          DateTime.now().difference(fechaDesdeDueno.toDate()).inDays;

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
          (punto.longitude <
              (xj - xi) * (punto.latitude - yi) / (yj - yi) + xi);
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

  // ── Conquista legacy via Cloud Function (territorios sin HP) ─────────────
  static Future<bool> conquistarTerritorio({
    required String docId,
    required String duenoAnteriorId,
    required double latUsuario,
    required double lngUsuario,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    if (duenoAnteriorId == user.uid) {
      await reforzarTerritorio(docId);
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
      debugPrint('❌ conquistarTerritorio [${e.code}]: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ Error inesperado en conquistarTerritorio: $e');
      return false;
    }
  }

  // ── Renombrar territorio v6 ───────────────────────────────────────────────
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

  // ── Escudo ────────────────────────────────────────────────────────────────
  // Precios: 24h → 50 monedas, 48h → 90 monedas, 72h → 120 monedas
  static const Map<int, int> kPreciosEscudo = {24: 50, 48: 90, 72: 120};

  /// Llama a la CF 'activarEscudo' y devuelve la nueva fecha de expiración.
  /// Lanza FirebaseFunctionsException si no hay monedas o parámetros inválidos.
  static Future<DateTime> activarEscudo({
    required String territorioId,
    required int horas, // 24 | 48 | 72
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('activarEscudo');
    final result = await callable.call({
      'territorioId': territorioId,
      'horas':        horas,
    });
    final data = result.data as Map<String, dynamic>;
    final expiraMs = (data['escudoExpira'] as num).toInt();
    return DateTime.fromMillisecondsSinceEpoch(expiraMs);
  }

  static Future<List<Map<String, dynamic>>> obtenerReyes(
      {int limit = 20}) async {
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
          'hp':          (d['hp'] as num?)?.toInt() ?? kHpMax,
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

  // ══════════════════════════════════════════════════════════════════════════
  // CARGAR territorios fantasma cercanos desde Firestore
  // ══════════════════════════════════════════════════════════════════════════
  static Future<List<TerritoryData>> cargarTerritoriosFantasmaCercanos({
    required LatLng centro,
  }) async {
    const kRad = 0.045; // ~5 km
    try {
      final snap = await _db
          .collection('territories')
          .where('userId', isEqualTo: kGhostUserId)
          .where('centroLat', isGreaterThan: centro.latitude  - kRad)
          .where('centroLat', isLessThan:    centro.latitude  + kRad)
          .get();

      final resultado = <TerritoryData>[];
      for (final doc in snap.docs) {
        final data      = doc.data();
        final rawPuntos = data['puntos'] as List<dynamic>?;
        if (rawPuntos == null || rawPuntos.isEmpty) continue;

        final cLng = (data['centroLng'] as num?)?.toDouble() ?? 0;
        if ((cLng - centro.longitude).abs() > kRad) continue;

        final puntos = rawPuntos.map((p) {
          final m = p as Map<String, dynamic>;
          return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
        }).toList();

        final cLat = (data['centroLat'] as num?)?.toDouble() ??
            puntos.map((p) => p.latitude).reduce((a, b) => a + b) / puntos.length;

        DateTime? ultimaVisita;
        final tsV = data['ultima_visita'];
        if (tsV is Timestamp) ultimaVisita = tsV.toDate();

        DateTime? ultimaActualizacionHp;
        final tsHp = data['ultimaActualizacionHp'];
        if (tsHp is Timestamp) ultimaActualizacionHp = tsHp.toDate();

        final hpGuardado = (data['hp'] as num?)?.toInt() ?? kHpMax;

        resultado.add(TerritoryData(
          docId:                 doc.id,
          ownerId:               kGhostUserId,
          ownerNickname:         data['nickname'] as String? ?? 'GhostBot',
          color:                 Color((data['color'] as num?)?.toInt() ?? 0xFF5588CC),
          puntos:                puntos,
          centro:                LatLng(cLat, cLng),
          esMio:                 false,
          esFantasma:            true,
          ultimaVisita:          ultimaVisita,
          hpGuardado:            hpGuardado,
          ultimaActualizacionHp: ultimaActualizacionHp,
        ));
      }
      debugPrint('👻 Cargados ${resultado.length} fantasmas de Firestore');
      return resultado;
    } catch (e) {
      debugPrint('Error cargando fantasmas: $e');
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CREAR territorios fantasma en Firestore donde no hay nadie
  // ══════════════════════════════════════════════════════════════════════════
  static Future<void> crearTerritoriosFantasmaEnZona({
    required LatLng centro,
    required List<TerritoryData> todosExistentes, // reales + fantasmas ya cargados
    int max = 15,
  }) async {
    final now = DateTime.now();
    final rng = math.Random(
      (centro.latitude  * 90).round() ^
      (centro.longitude * 90).round() ^
      ((now.month * 31 + now.day) * 31337),
    );

    const List<int> botColoresVal = [
      0xFF4A7FBB, 0xFF4EAA6A, 0xFFBB5A4A, 0xFF7A4EBB, 0xFF4EBBAA,
      0xFFBB9A4E, 0xFF4E5EAA, 0xFF9A4EBB, 0xFF6EBB4E, 0xFFBB724E,
    ];
    const List<String> botNicks = [
      'PhantomRunner', 'GhostRaider', 'ShadowWalker', 'NightPatrol',
      'UrbanClaimer',  'ZoneMaster',  'StreetKing',   'MapHunter',
      'DarkStrider',   'SilentRider', 'NightOwl',     'AreaKeeper',
      'RoutePhantom',  'ZoneBuster',  'PathFinder',   'CityGhost',
    ];

    const double espacio    = 0.0022; // ~245 m entre centros
    const double radioBase  = 0.00055; // ~61 m → ~9 000 m² de media
    const double margen     = 0.0016; // si hay algo a <178 m, no crear

    int created = 0;
    for (int row = -7; row <= 7 && created < max; row++) {
      for (int col = -7; col <= 7 && created < max; col++) {
        final lat = centro.latitude  + row * espacio * math.sqrt(3) / 2;
        final lng = centro.longitude + col * espacio + (row % 2) * espacio / 2;

        final ocupado = todosExistentes.any((t) =>
          (t.centro.latitude  - lat).abs() < margen &&
          (t.centro.longitude - lng).abs() < margen);
        if (ocupado) continue;

        final r      = radioBase * (0.55 + rng.nextDouble() * 0.85);
        final puntos = _generarPoligonoFantasma(lat, lng, r, rng);
        final colorVal = botColoresVal[rng.nextInt(botColoresVal.length)];
        final nick     = botNicks[rng.nextInt(botNicks.length)];
        final areaM2   = calcularAreaM2(puntos);
        if (areaM2 < kAreaMinimaM2) continue;

        final puntosList = puntos
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList();

        try {
          await _db.collection('territories').add({
            'userId':                kGhostUserId,
            'nickname':              nick,
            'puntos':                puntosList,
            'centro':                {'lat': lat, 'lng': lng},
            'centroLat':             lat,
            'centroLng':             lng,
            'color':                 colorVal,
            'ultima_visita':         FieldValue.serverTimestamp(),
            'fecha_creacion':        FieldValue.serverTimestamp(),
            'fecha_desde_dueno':     FieldValue.serverTimestamp(),
            'modo':                  'competitivo',
            'esFantasma':            true,
            'area_m2':               areaM2,
            'hp':                    kHpMax,
            'hpMax':                 kHpMax,
            'velocidadConquistaKmh': 5.0,
            'ultimaActualizacionHp': FieldValue.serverTimestamp(),
            'rey_id':                null,
            'rey_nickname':          null,
            'rey_desde':             null,
            'nombre_territorio':     null,
          });
          created++;
        } catch (e) {
          debugPrint('Error creando fantasma: $e');
        }
      }
    }
    debugPrint('👻 Creados $created fantasmas en Firestore');
    if (created > 0) invalidarCache();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TERRITORIOS FANTASMA — relleno visual para mapas vacíos (modo competitivo)
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Genera hasta [maxFantasmas] territorios solo-visuales alrededor de [centro].
  // Nunca se superponen con territorios reales de [reales].
  // Son puramente locales (no se guardan en Firestore) y no son interactuables.
  // ──────────────────────────────────────────────────────────────────────────
  static List<TerritoryData> generarTerritoriosFantasma({
    required LatLng centro,
    required List<TerritoryData> reales,
    int maxFantasmas = 28,
  }) {
    // Semilla basada en posición redondeada (~1km precisión) + día del año
    // → mismos fantasmas durante la misma sesión/día en la misma zona
    final now  = DateTime.now();
    final seed = (centro.latitude  * 90).round() ^
                 (centro.longitude * 90).round() ^
                 ((now.month * 31 + now.day) * 31337);
    final rng = math.Random(seed);

    // Paleta de colores bot (saturados pero no idénticos a los del juego)
    const List<Color> botColores = [
      Color(0xFF4A7FBB), Color(0xFF4EAA6A), Color(0xFFBB5A4A),
      Color(0xFF7A4EBB), Color(0xFF4EBBAA), Color(0xFFBB9A4E),
      Color(0xFF4E5EAA), Color(0xFF9A4EBB), Color(0xFF6EBB4E),
      Color(0xFFBB724E),
    ];

    const List<String> botNicks = [
      'PhantomRunner', 'GhostRaider', 'ShadowWalker', 'NightPatrol',
      'UrbanClaimer',  'ZoneMaster',  'StreetKing',   'MapHunter',
      'DarkStrider',   'SilentRider', 'NightOwl',     'AreaKeeper',
      'RoutePhantom',  'ZoneBuster',  'PathFinder',   'CityGhost',
      'TerrainBot',    'BorderGuard', 'RunningShade', 'GroundZero',
    ];

    // Espaciado en la rejilla hexagonal
    const double espacio    = 0.0022; // ~245 m entre centros
    const double radioBase  = 0.00055; // ~61 m circumradius → ~9 000 m² de media
    const double margenReal = 0.0016; // si hay un real a <178 m, no ponemos fantasma

    final List<TerritoryData> resultado = [];
    int added = 0;

    for (int row = -7; row <= 7 && added < maxFantasmas; row++) {
      for (int col = -7; col <= 7 && added < maxFantasmas; col++) {
        final lat = centro.latitude  + row * espacio * math.sqrt(3) / 2;
        final lng = centro.longitude + col * espacio + (row % 2) * espacio / 2;

        // ¿Hay un territorio real demasiado cerca? → prevalece el real
        final ocupado = reales.any((t) =>
          (t.centro.latitude  - lat).abs() < margenReal &&
          (t.centro.longitude - lng).abs() < margenReal);
        if (ocupado) continue;

        // Radio variable → formas con tamaño orgánico
        final r      = radioBase * (0.55 + rng.nextDouble() * 0.85);
        final puntos = _generarPoligonoFantasma(lat, lng, r, rng);

        resultado.add(TerritoryData(
          docId:                 'ghost_${row}_$col',
          ownerId:               'ghost',
          ownerNickname:         botNicks[rng.nextInt(botNicks.length)],
          color:                 botColores[rng.nextInt(botColores.length)],
          puntos:                puntos,
          centro:                LatLng(lat, lng),
          esMio:                 false,
          esFantasma:            true,
          hpGuardado:            55,
          ultimaActualizacionHp: DateTime.now().subtract(const Duration(days: 2)),
        ));
        added++;
      }
    }

    debugPrint('👻 Generados ${resultado.length} territorios fantasma');
    return resultado;
  }

  /// Polígono irregular de 7 vértices centrado en (lat, lng) con radio r grados.
  static List<LatLng> _generarPoligonoFantasma(
      double lat, double lng, double r, math.Random rng) {
    const lados   = 7;
    final cosLat  = math.cos(lat * math.pi / 180);
    final offset  = rng.nextDouble() * 2 * math.pi; // rotación aleatoria
    return List.generate(lados, (i) {
      final angle  = offset + (i / lados) * 2 * math.pi;
      final jitter = 0.55 + rng.nextDouble() * 0.9;
      return LatLng(
        lat + r * jitter * math.sin(angle),
        lng + r * jitter * math.cos(angle) / (cosLat > 0.01 ? cosLat : 1),
      );
    });
  }
}

// =============================================================================
// GLOBAL TERRITORY — modelo compartido entre LiveActivity y FullscreenMap
// =============================================================================

const Color kTierColorSmall  = Color(0xFF30D158);
const Color kTierColorMedium = Color(0xFF636366);
const Color kTierColorLegend = Color(0xFFFFD60A);

enum TerritoryTier { pequeno, mediano, legendario }

class GlobalTerritory {
  final String id;
  final String name;
  final String epicName;
  final String inspiration;
  final String icon;
  final TerritoryTier tier;
  final double baseKm;
  final int baseReward;
  final bool rewardLeague;
  final LatLng center;
  final List<LatLng> points;
  final String? ownerNickname;
  final String? ownerUid;
  final Color? ownerColor;
  final int difficultyLevel;
  final int conquestCount;
  final Color territoryColor;
  final double clausulaKm;

  const GlobalTerritory({
    required this.id,
    required this.name,
    required this.epicName,
    required this.inspiration,
    required this.icon,
    required this.tier,
    required this.baseKm,
    required this.baseReward,
    required this.rewardLeague,
    required this.center,
    required this.points,
    this.ownerNickname,
    this.ownerUid,
    this.ownerColor,
    this.difficultyLevel = 1,
    this.conquestCount = 0,
    required this.territoryColor,
    double? clausulaKm,
  }) : clausulaKm = clausulaKm ?? baseKm;

  GlobalTerritory copyWith({
    String?     ownerNickname,
    String?     ownerUid,
    Color?      ownerColor,
    bool        clearOwner = false,
    int?        difficultyLevel,
    int?        conquestCount,
    double?     clausulaKm,
  }) => GlobalTerritory(
    id:              id,
    name:            name,
    epicName:        epicName,
    inspiration:     inspiration,
    icon:            icon,
    tier:            tier,
    baseKm:          baseKm,
    baseReward:      baseReward,
    rewardLeague:    rewardLeague,
    center:          center,
    points:          points,
    ownerNickname:   clearOwner ? null : (ownerNickname ?? this.ownerNickname),
    ownerUid:        clearOwner ? null : (ownerUid      ?? this.ownerUid),
    ownerColor:      clearOwner ? null : (ownerColor    ?? this.ownerColor),
    difficultyLevel: difficultyLevel ?? this.difficultyLevel,
    conquestCount:   conquestCount   ?? this.conquestCount,
    territoryColor:  territoryColor,
    clausulaKm:      clausulaKm ?? this.clausulaKm,
  );

  Color  get displayColor  => ownerColor ?? territoryColor;
  double get kmRequired    => clausulaKm;
  int    get rewardActual  => (baseReward * (1 + (difficultyLevel - 1) * 0.15)).round();
  bool   get isOwned       => ownerUid != null;
  bool   get isMine        => ownerUid == FirebaseAuth.instance.currentUser?.uid;

  Color get tierColor {
    switch (tier) {
      case TerritoryTier.pequeno:    return kTierColorSmall;
      case TerritoryTier.mediano:    return kTierColorMedium;
      case TerritoryTier.legendario: return kTierColorLegend;
    }
  }

  String get tierLabel {
    switch (tier) {
      case TerritoryTier.pequeno:    return 'COMÚN';
      case TerritoryTier.mediano:    return 'ÉPICO';
      case TerritoryTier.legendario: return 'LEGENDARIO';
    }
  }

  // Parsea un documento Firestore; devuelve null si las coordenadas son 0,0.
  static GlobalTerritory? fromFirestore(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();

    final tierStr = d['tier'] as String? ?? 'pequeno';
    final tier    = tierStr == 'legendario'
        ? TerritoryTier.legendario
        : tierStr == 'mediano'
            ? TerritoryTier.mediano
            : TerritoryTier.pequeno;

    final centroMap = d['centro'] as Map<String, dynamic>?;
    final centerLat = centroMap != null
        ? (centroMap['lat'] as num?)?.toDouble() ?? 0.0
        : (d['centroLat'] as num?)?.toDouble() ?? 0.0;
    final centerLng = centroMap != null
        ? (centroMap['lng'] as num?)?.toDouble() ?? 0.0
        : (d['centroLng'] as num?)?.toDouble() ?? 0.0;

    if (centerLat == 0 && centerLng == 0) return null;

    final center = LatLng(centerLat, centerLng);

    final rawPts = d['puntos'] as List<dynamic>?;
    List<LatLng> pts = [];
    if (rawPts != null && rawPts.isNotEmpty) {
      pts = rawPts.map((p) {
        final m = p as Map<String, dynamic>;
        return LatLng(
          (m['lat'] as num).toDouble(),
          (m['lng'] as num? ?? m['latitude'] as num? ?? 0).toDouble(),
        );
      }).toList();
    }
    if (pts.isEmpty) {
      final radius = tier == TerritoryTier.legendario ? 0.02 : 0.012;
      pts = buildGlobalHexPoints(center, radius);
    }

    final baseKm     = (d['baseKm']     as num?)?.toDouble() ?? 5.0;
    final clausulaKm = (d['clausulaKm'] as num?)?.toDouble() ?? baseKm;
    final ownerColorInt = d['ownerColor'] as int?;

    final tierColor = tier == TerritoryTier.legendario
        ? kTierColorLegend
        : tier == TerritoryTier.mediano
            ? kTierColorMedium
            : kTierColorSmall;

    return GlobalTerritory(
      id:              doc.id,
      name:            d['nombre']      as String? ?? d['epicName']  as String? ?? doc.id,
      epicName:        d['epicName']    as String? ?? d['nombre']    as String? ?? doc.id,
      inspiration:     d['inspiration'] as String? ?? '',
      icon:            d['icon']        as String? ?? '🏴',
      tier:            tier,
      baseKm:          baseKm,
      clausulaKm:      clausulaKm,
      baseReward:      (d['baseReward']      as num?)?.toInt() ?? 50,
      rewardLeague:    d['rewardLeague']     as bool? ?? false,
      center:          center,
      points:          pts,
      ownerNickname:   d['ownerNickname']    as String?,
      ownerUid:        d['ownerUid']         as String?,
      ownerColor:      ownerColorInt != null ? Color(ownerColorInt) : null,
      difficultyLevel: (d['difficultyLevel'] as num?)?.toInt() ?? 1,
      conquestCount:   (d['conquestCount']   as num?)?.toInt() ?? 0,
      territoryColor:  tierColor,
    );
  }
}

/// Territorios de ejemplo usados por AMBAS pantallas cuando Firestore
/// no tiene datos con activo:true. Los IDs deben coincidir con los de Firestore.
List<GlobalTerritory> buildSampleGlobalTerritories() => [
  GlobalTerritory(
    id: 'gt_paris', name: 'El Barrio Eterno',
    epicName: 'La Ciudad de la Luz', inspiration: 'París', icon: '🗼',
    tier: TerritoryTier.pequeno, baseKm: 5, baseReward: 120, rewardLeague: false,
    center: const LatLng(48.8566, 2.3522),
    points: buildGlobalHexPoints(const LatLng(48.8566, 2.3522), 0.01),
    territoryColor: kTierColorSmall, difficultyLevel: 3, clausulaKm: 5,
  ),
  GlobalTerritory(
    id: 'gt_nyc', name: 'La Gran Fortaleza',
    epicName: 'La Gran Manzana', inspiration: 'Nueva York', icon: '🗽',
    tier: TerritoryTier.mediano, baseKm: 8, baseReward: 200, rewardLeague: false,
    center: const LatLng(40.7128, -74.0060),
    points: buildGlobalHexPoints(const LatLng(40.7128, -74.0060), 0.012),
    territoryColor: kTierColorMedium, difficultyLevel: 5, clausulaKm: 8,
  ),
  GlobalTerritory(
    id: 'gt_tokyo', name: 'El Corazón del Mapa',
    epicName: 'Tokio Eterno', inspiration: 'Tokio', icon: '⛩️',
    tier: TerritoryTier.legendario, baseKm: 12, baseReward: 350, rewardLeague: true,
    center: const LatLng(35.6762, 139.6503),
    points: buildGlobalHexPoints(const LatLng(35.6762, 139.6503), 0.02),
    territoryColor: kTierColorLegend, difficultyLevel: 8, clausulaKm: 12,
  ),
  GlobalTerritory(
    id: 'gt_madrid', name: 'La Ciudad de las Espadas',
    epicName: 'La Villa y Corte', inspiration: 'Madrid', icon: '🏛️',
    tier: TerritoryTier.pequeno, baseKm: 5, baseReward: 100, rewardLeague: false,
    center: const LatLng(40.4168, -3.7038),
    points: buildGlobalHexPoints(const LatLng(40.4168, -3.7038), 0.01),
    territoryColor: kTierColorSmall, difficultyLevel: 2, clausulaKm: 5,
  ),
  GlobalTerritory(
    id: 'gt_sydney', name: 'La Ciudadela del Pacífico',
    epicName: 'Ciudad del Puerto', inspiration: 'Sídney', icon: '🦘',
    tier: TerritoryTier.mediano, baseKm: 10, baseReward: 250, rewardLeague: false,
    center: const LatLng(-33.8688, 151.2093),
    points: buildGlobalHexPoints(const LatLng(-33.8688, 151.2093), 0.012),
    territoryColor: kTierColorMedium, difficultyLevel: 6, clausulaKm: 10,
  ),
  GlobalTerritory(
    id: 'gt_cairo', name: 'El Oasis Milenario',
    epicName: 'La Ciudad Milenaria', inspiration: 'El Cairo', icon: '🏺',
    tier: TerritoryTier.pequeno, baseKm: 7, baseReward: 150, rewardLeague: false,
    center: const LatLng(30.0444, 31.2357),
    points: buildGlobalHexPoints(const LatLng(30.0444, 31.2357), 0.01),
    territoryColor: kTierColorSmall, difficultyLevel: 4, clausulaKm: 7,
  ),
];

List<LatLng> buildGlobalHexPoints(LatLng center, double radius) {
  return List.generate(6, (i) {
    final angle = (i * 60 - 30) * math.pi / 180;
    return LatLng(
      center.latitude  + radius * math.sin(angle),
      center.longitude + radius * math.cos(angle),
    );
  });
}