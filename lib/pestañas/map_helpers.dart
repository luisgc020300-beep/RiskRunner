// lib/pestañas/map_helpers.dart
// Modelos y servicio de datos del mapa extraídos para reducir el tamaño del archivo principal.
part of 'fullscreen_map_screen.dart';

// ── Estadística de sheet ──────────────────────────────────────────────────────

class _ShStat {
  final String value, label;
  const _ShStat(this.value, this.label);
}

// ── Barrio (modo solitario) ───────────────────────────────────────────────────

class _BarrioData {
  final String nombre;
  final List<LatLng> puntos;
  final double areaM2;
  double porcentajeCubierto;

  _BarrioData({
    required this.nombre,
    required this.puntos,
    required this.areaM2,
    this.porcentajeCubierto = 0.0,
  });

  LatLng get centro {
    final lat =
        puntos.map((p) => p.latitude).reduce((a, b) => a + b) / puntos.length;
    final lng =
        puntos.map((p) => p.longitude).reduce((a, b) => a + b) / puntos.length;
    return LatLng(lat, lng);
  }
}

// ── Modelos Mi Ciudad ─────────────────────────────────────────────────────────

class _UserGroup {
  final String ownerId, nickname;
  final int nivel;
  final bool esMio;
  final List<_TerDet> territorios;
  _UserGroup({
    required this.ownerId,
    required this.nickname,
    required this.nivel,
    required this.esMio,
    required this.territorios,
  });
}

class _TerDet {
  final String docId;
  final double dist;
  final int? diasSinVisitar;
  final List<LatLng> puntos;
  final String ownerId;
  final String? nombreTerritorio;
  _TerDet({
    required this.docId,
    required this.dist,
    this.diasSinVisitar,
    this.puntos = const [],
    this.ownerId = '',
    this.nombreTerritorio,
  });
}

// ── Servicio de datos ─────────────────────────────────────────────────────────

class _MapDataService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const double _kRadGrados = 0.045;

  Future<List<_UserGroup>> cargarGruposCercanos(
      LatLng centro, String myUid,
      {String modo = 'competitivo'}) async {
    final latMin = centro.latitude - _kRadGrados;
    final latMax = centro.latitude + _kRadGrados;
    final snap = await _db
        .collection('territories')
        .where('centroLat', isGreaterThan: latMin)
        .where('centroLat', isLessThan: latMax)
        .get();

    final Map<String, List<_TerDet>> tersPorOwner = {};
    for (final doc in snap.docs) {
      final data = (doc.data()) as Map<String, dynamic>;
      final rawPts = data['puntos'] as List<dynamic>?;
      if (rawPts == null || rawPts.isEmpty) continue;
      final docModo = data['modo'] as String?;
      if (modo == 'solitario') {
        if (docModo != 'solitario') continue;
        final docOwner = data['userId'] as String? ?? '';
        if (docOwner != myUid) continue;
      } else {
        if (docModo == 'solitario') continue;
      }
      final pts = _parsePuntos(rawPts);
      final c = _centroide(pts);
      final dist = Geolocator.distanceBetween(
          centro.latitude, centro.longitude, c.latitude, c.longitude);
      if (dist > 5000) continue;
      final ownerId = data['userId'] as String? ?? '';
      if (ownerId.isEmpty) continue;
      tersPorOwner
          .putIfAbsent(ownerId, () => [])
          .add(_TerDet(docId: doc.id, dist: dist / 1000, puntos: pts, ownerId: ownerId));
    }

    if (tersPorOwner.isEmpty) return [];

    final ownerIds = tersPorOwner.keys.toList();
    final chunks = _chunked(ownerIds, 30);
    final Map<String, Map<String, dynamic>> playersMap = {};
    final results = await Future.wait(
      chunks.map((chunk) async {
        try {
          return await _db
              .collection('players')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
        } catch (_) {
          return null;
        }
      }),
    );
    for (final snap in results) {
      if (snap == null) continue;
      for (final p in snap.docs) {
        playersMap[p.id] = p.data();
      }
    }

    final Map<String, _UserGroup> grupos = {};
    for (final ownerId in tersPorOwner.keys) {
      final pData = playersMap[ownerId];
      final nick =
          ownerId == myUid ? 'YO' : (pData?['nickname'] as String? ?? ownerId);
      final nivel = (pData?['nivel'] as num? ?? 1).toInt();
      grupos[ownerId] = _UserGroup(
        ownerId: ownerId,
        nickname: nick,
        nivel: nivel,
        esMio: ownerId == myUid,
        territorios: tersPorOwner[ownerId]!,
      );
    }
    return grupos.values.toList()
      ..sort((a, b) {
        if (a.esMio) return -1;
        if (b.esMio) return 1;
        return a.nickname.compareTo(b.nickname);
      });
  }

  Future<List<_TerDet>> cargarDetalles(String ownerId, LatLng centro,
      {String modo = 'competitivo'}) async {
    final snap = await _db
        .collection('territories')
        .where('userId', isEqualTo: ownerId)
        .get();
    final List<_TerDet> dets = [];
    for (final doc in snap.docs) {
      final data = doc.data();
      final docModo = data['modo'] as String?;
      if (modo == 'solitario') {
        if (docModo != 'solitario') continue;
      } else {
        if (docModo == 'solitario') continue;
      }
      final rawPts = data['puntos'] as List<dynamic>?;
      if (rawPts == null || rawPts.isEmpty) continue;
      final pts = _parsePuntos(rawPts);
      final c = _centroide(pts);
      final distM = Geolocator.distanceBetween(
          centro.latitude, centro.longitude, c.latitude, c.longitude);
      if (distM > 5000) continue;
      final tsV = data['ultima_visita'] as Timestamp?;
      final dias =
          tsV == null ? 0 : DateTime.now().difference(tsV.toDate()).inDays;
      dets.add(_TerDet(
        docId: doc.id,
        dist: distM / 1000,
        diasSinVisitar: dias,
        puntos: pts,
        ownerId: ownerId,
        nombreTerritorio: data['nombre_territorio'] as String?,
      ));
    }
    return dets;
  }

  static List<LatLng> _parsePuntos(List<dynamic> raw) => raw.map((p) {
        final m = p as Map<String, dynamic>;
        return LatLng(
            (m['lat'] as num).toDouble(),
            m['lon'] != null
                ? (m['lon'] as num).toDouble()
                : (m['lng'] as num).toDouble());
      }).toList();

  static LatLng _centroide(List<LatLng> pts) => LatLng(
        pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length,
        pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length,
      );

  static List<List<T>> _chunked<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      chunks.add(list.sublist(i, math.min(i + size, list.length)));
    }
    return chunks;
  }
}
