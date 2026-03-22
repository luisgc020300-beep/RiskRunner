// lib/services/zona_service.dart
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

// ═══════════════════════════════════════════════════════════
//  MODELOS
// ═══════════════════════════════════════════════════════════

class ZonaInfo {
  final String id;
  final String nombre;
  final String? nombreCorto;
  final List<LatLng> poligono;
  final String? reyActualId;
  final String? reyActualNick;
  final int temporadaActual;

  const ZonaInfo({
    required this.id,
    required this.nombre,
    this.nombreCorto,
    required this.poligono,
    this.reyActualId,
    this.reyActualNick,
    required this.temporadaActual,
  });

  factory ZonaInfo.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawPts = d['poligono'] as List<dynamic>? ?? [];
    final pts = rawPts.map((p) {
      final m = p as Map<String, dynamic>;
      return LatLng(
          (m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
    }).toList();
    return ZonaInfo(
      id: doc.id,
      nombre: d['nombre'] as String? ?? '',
      nombreCorto: d['nombre_corto'] as String?,
      poligono: pts,
      reyActualId: d['rey_actual_id'] as String?,
      reyActualNick: d['rey_actual_nick'] as String?,
      temporadaActual: (d['temporada_actual'] as num? ?? 1).toInt(),
    );
  }
}

class TituloRey {
  final String id;
  final String userId;
  final String userNick;
  final String zonaId;
  final String zonaNombre;
  final String? zonaNombreCorto;
  final int temporada;
  final double areaM2;
  final int monedasRecompensa;
  final DateTime fechaOtorgado;
  final bool coronaDesbloqueada;

  const TituloRey({
    required this.id,
    required this.userId,
    required this.userNick,
    required this.zonaId,
    required this.zonaNombre,
    this.zonaNombreCorto,
    required this.temporada,
    required this.areaM2,
    required this.monedasRecompensa,
    required this.fechaOtorgado,
    required this.coronaDesbloqueada,
  });

  factory TituloRey.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return TituloRey(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      userNick: d['userNick'] as String? ?? '',
      zonaId: d['zonaId'] as String? ?? '',
      zonaNombre: d['zonaNombre'] as String? ?? '',
      zonaNombreCorto: d['zonaNombreCorto'] as String?,
      temporada: (d['temporada'] as num? ?? 1).toInt(),
      areaM2: (d['areaM2'] as num? ?? 0).toDouble(),
      monedasRecompensa: (d['monedasRecompensa'] as num? ?? 0).toInt(),
      fechaOtorgado:
          (d['fechaOtorgado'] as Timestamp?)?.toDate() ?? DateTime.now(),
      coronaDesbloqueada: d['coronaDesbloqueada'] as bool? ?? true,
    );
  }

  String get zonaNombreDisplay => zonaNombreCorto ?? zonaNombre;
  String get bannerLabel => 'Rey de $zonaNombreDisplay · T$temporada';
  String get bannerLabelActivo => '👑 Rey de $zonaNombreDisplay';
}

class TemporadaInfo {
  final String id;
  final int numero;
  final DateTime inicio;
  final DateTime fin;
  final bool activa;
  final int monedasBase;

  const TemporadaInfo({
    required this.id,
    required this.numero,
    required this.inicio,
    required this.fin,
    required this.activa,
    required this.monedasBase,
  });

  factory TemporadaInfo.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return TemporadaInfo(
      id: doc.id,
      numero: (d['numero'] as num? ?? 1).toInt(),
      inicio: (d['inicio'] as Timestamp).toDate(),
      fin: (d['fin'] as Timestamp).toDate(),
      activa: d['activa'] as bool? ?? false,
      monedasBase: (d['monedas_base'] as num? ?? 500).toInt(),
    );
  }

  String get label => 'Temporada $numero';
  bool get haTerminado => DateTime.now().isAfter(fin);

  /// Días restantes hasta el fin de temporada
  int get diasRestantes {
    final diff = fin.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }
}

// ═══════════════════════════════════════════════════════════
//  SERVICIO PRINCIPAL
// ═══════════════════════════════════════════════════════════

class ZonaService {
  static final _db = FirebaseFirestore.instance;

  // ── Queries ─────────────────────────────────────────────

  static Future<List<ZonaInfo>> getTodasLasZonas() async {
    final snap = await _db.collection('zonas').orderBy('nombre').get();
    return snap.docs.map(ZonaInfo.fromFirestore).toList();
  }

  static Future<TemporadaInfo?> getTemporadaActiva() async {
    try {
      final snap = await _db
          .collection('temporadas')
          .where('activa', isEqualTo: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return TemporadaInfo.fromFirestore(snap.docs.first);
    } catch (_) {
      return null;
    }
  }

  static Future<List<TituloRey>> getTitulosDeUsuario(String userId) async {
    final snap = await _db
        .collection('titulos_rey')
        .where('userId', isEqualTo: userId)
        .orderBy('temporada', descending: true)
        .get();
    return snap.docs.map(TituloRey.fromFirestore).toList();
  }

  static Future<List<TituloRey>> getTitulosActivosDeUsuario(
      String userId) async {
    final temporada = await getTemporadaActiva();
    if (temporada == null) return [];
    final snap = await _db
        .collection('titulos_rey')
        .where('userId', isEqualTo: userId)
        .where('temporada', isEqualTo: temporada.numero)
        .get();
    return snap.docs.map(TituloRey.fromFirestore).toList();
  }

  static Future<bool> tieneCoronaDesbloqueada(String userId) async {
    final snap = await _db
        .collection('titulos_rey')
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  // ── Cálculo de dominio ───────────────────────────────────

  static double calcularAreaInterseccion(
      List<LatLng> territorio, List<LatLng> zona) {
    if (territorio.length < 3 || zona.length < 3) return 0;
    final interseccion = _sutherlandHodgman(territorio, zona);
    if (interseccion.length < 3) return 0;
    return _areaPoligonoMetros(interseccion);
  }

  static Future<double> calcularDominioEnZona(
      String userId, ZonaInfo zona) async {
    final snap = await _db
        .collection('territories')
        .where('userId', isEqualTo: userId)
        .get();
    double total = 0;
    for (final doc in snap.docs) {
      final rawPts = doc.data()['puntos'] as List<dynamic>? ?? [];
      if (rawPts.isEmpty) continue;
      final pts = rawPts.map((p) {
        final m = p as Map<String, dynamic>;
        return LatLng(
            (m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
      }).toList();
      total += calcularAreaInterseccion(pts, zona.poligono);
    }
    return total;
  }

  static Future<Map<String, double>> calcularDominioZonaCompleto(
      ZonaInfo zona) async {
    final snap = await _db.collection('territories').get();
    final Map<String, double> dominio = {};
    for (final doc in snap.docs) {
      final data = doc.data();
      final uid = data['userId'] as String? ?? '';
      if (uid.isEmpty) continue;
      final rawPts = data['puntos'] as List<dynamic>? ?? [];
      if (rawPts.isEmpty) continue;
      final pts = rawPts.map((p) {
        final m = p as Map<String, dynamic>;
        return LatLng(
            (m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
      }).toList();
      final area = calcularAreaInterseccion(pts, zona.poligono);
      if (area > 0) dominio[uid] = (dominio[uid] ?? 0) + area;
    }
    return dominio;
  }

  // ── Cierre de temporada ──────────────────────────────────

  /// Cierra la temporada activa, otorga títulos y recompensas.
  /// Devuelve cuántos títulos se otorgaron.
  static Future<int> cerrarTemporada(String temporadaId) async {
    final temporadaDoc =
        await _db.collection('temporadas').doc(temporadaId).get();
    if (!temporadaDoc.exists) throw Exception('Temporada no encontrada');
    final temporada = TemporadaInfo.fromFirestore(temporadaDoc);
    if (!temporada.activa) throw Exception('La temporada ya está cerrada');

    final zonas = await getTodasLasZonas();
    int titulosOtorgados = 0;
    final batch = _db.batch();

    for (final zona in zonas) {
      final dominio = await calcularDominioZonaCompleto(zona);
      if (dominio.isEmpty) continue;

      final ganadorId =
          dominio.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      final areaDominada = dominio[ganadorId]!;

      // Mínimo 100m² para recibir el título
      if (areaDominada < 100) continue;

      final playerDoc =
          await _db.collection('players').doc(ganadorId).get();
      if (!playerDoc.exists) continue;
      final playerData = playerDoc.data()!;
      final nick = playerData['nickname'] as String? ?? 'Runner';
      final monedas = temporada.monedasBase;

      // Crear título histórico
      final tituloRef = _db.collection('titulos_rey').doc();
      batch.set(tituloRef, {
        'userId': ganadorId,
        'userNick': nick,
        'zonaId': zona.id,
        'zonaNombre': zona.nombre,
        'zonaNombreCorto': zona.nombreCorto,
        'temporada': temporada.numero,
        'areaM2': areaDominada,
        'monedasRecompensa': monedas,
        'coronaDesbloqueada': true,
        'fechaOtorgado': FieldValue.serverTimestamp(),
      });

      // Actualizar zona con el nuevo rey
      batch.update(_db.collection('zonas').doc(zona.id), {
        'rey_actual_id': ganadorId,
        'rey_actual_nick': nick,
        'temporada_actual': temporada.numero,
      });

      // Entregar monedas
      batch.update(_db.collection('players').doc(ganadorId), {
        'monedas': FieldValue.increment(monedas),
        'avatar_config.coronaDesbloqueada': true,
      });

      // Notificación al ganador
      final notifRef = _db.collection('notifications').doc();
      batch.set(notifRef, {
        'toUserId': ganadorId,
        'type': 'titulo_rey',
        'zonaId': zona.id,
        'zonaNombre': zona.nombreCorto ?? zona.nombre,
        'temporada': temporada.numero,
        'monedasRecompensa': monedas,
        'message':
            '👑 ¡Eres el Rey de ${zona.nombreCorto ?? zona.nombre} en la T${temporada.numero}! +$monedas 🪙',
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      });

      titulosOtorgados++;
    }

    // Cerrar temporada
    batch.update(_db.collection('temporadas').doc(temporadaId), {
      'activa': false,
      'fecha_cierre': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    return titulosOtorgados;
  }

  /// Crea una nueva temporada activa
  static Future<String> crearNuevaTemporada({
    required int numero,
    required DateTime inicio,
    required DateTime fin,
    int monedasBase = 500,
  }) async {
    final ref = await _db.collection('temporadas').add({
      'numero': numero,
      'inicio': Timestamp.fromDate(inicio),
      'fin': Timestamp.fromDate(fin),
      'activa': true,
      'monedas_base': monedasBase,
      'creada': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  // ── Geometría ────────────────────────────────────────────

  static List<LatLng> _sutherlandHodgman(
      List<LatLng> subject, List<LatLng> clip) {
    List<LatLng> output = List.from(subject);
    if (output.isEmpty) return [];
    for (int i = 0; i < clip.length; i++) {
      if (output.isEmpty) return [];
      final List<LatLng> input = List.from(output);
      output.clear();
      final LatLng edgeStart = clip[i];
      final LatLng edgeEnd = clip[(i + 1) % clip.length];
      for (int j = 0; j < input.length; j++) {
        final LatLng current = input[j];
        final LatLng previous =
            input[(j + input.length - 1) % input.length];
        final bool currentInside = _isInside(current, edgeStart, edgeEnd);
        final bool previousInside = _isInside(previous, edgeStart, edgeEnd);
        if (currentInside) {
          if (!previousInside) {
            final inter =
                _intersection(previous, current, edgeStart, edgeEnd);
            if (inter != null) output.add(inter);
          }
          output.add(current);
        } else if (previousInside) {
          final inter =
              _intersection(previous, current, edgeStart, edgeEnd);
          if (inter != null) output.add(inter);
        }
      }
    }
    return output;
  }

  static bool _isInside(LatLng p, LatLng a, LatLng b) {
    return (b.longitude - a.longitude) * (p.latitude - a.latitude) -
            (b.latitude - a.latitude) * (p.longitude - a.longitude) >=
        0;
  }

  static LatLng? _intersection(
      LatLng p1, LatLng p2, LatLng p3, LatLng p4) {
    final d1lat = p2.latitude - p1.latitude;
    final d1lng = p2.longitude - p1.longitude;
    final d2lat = p4.latitude - p3.latitude;
    final d2lng = p4.longitude - p3.longitude;
    final denom = d1lat * d2lng - d1lng * d2lat;
    if (denom.abs() < 1e-10) return null;
    final t = ((p3.latitude - p1.latitude) * d2lng -
            (p3.longitude - p1.longitude) * d2lat) /
        denom;
    return LatLng(
        p1.latitude + t * d1lat, p1.longitude + t * d1lng);
  }

  static double _areaPoligonoMetros(List<LatLng> pts) {
    if (pts.length < 3) return 0;
    const R = 6371000.0;
    double area = 0;
    for (int i = 0; i < pts.length; i++) {
      final j = (i + 1) % pts.length;
      final lat1 = pts[i].latitude * math.pi / 180;
      final lat2 = pts[j].latitude * math.pi / 180;
      final dLng =
          (pts[j].longitude - pts[i].longitude) * math.pi / 180;
      area += dLng * (2 + math.sin(lat1) + math.sin(lat2));
    }
    return (area * R * R / 2).abs();
  }
}