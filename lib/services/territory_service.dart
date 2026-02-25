import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Cuántos días sin visitar antes de que un territorio se deteriore visualmente
const int kDiasParaDeterioroVisual = 5;

/// Cuántos días sin visitar antes de que sea conquistable sin pasar por encima
const int kDiasParaDeterioroFuncional = 10;

class TerritoryData {
  final String docId;
  final String ownerId;
  final String ownerNickname;
  final Color color;
  final List<LatLng> puntos;
  final LatLng centro;
  final DateTime? ultimaVisita;
  final bool esMio;

  TerritoryData({
    required this.docId,
    required this.ownerId,
    required this.ownerNickname,
    required this.color,
    required this.puntos,
    required this.centro,
    required this.esMio,
    this.ultimaVisita,
  });

  /// Días desde la última visita (null = nunca visitado desde que existe el campo)
  int get diasSinVisitar {
    if (ultimaVisita == null) return 0;
    return DateTime.now().difference(ultimaVisita!).inDays;
  }

  /// Deterioro visual: semitransparente si llevas más de 5 días sin visitar
  bool get estaDeterirado => diasSinVisitar >= kDiasParaDeterioroVisual;

  /// Deterioro funcional: conquistable sin pasar exactamente por encima
  bool get esConquistableSinPasar => diasSinVisitar >= kDiasParaDeterioroFuncional;

  /// Opacidad visual según el deterioro
  double get opacidadRelleno {
    if (diasSinVisitar >= kDiasParaDeterioroFuncional) return 0.12;
    if (diasSinVisitar >= kDiasParaDeterioroVisual) return 0.22;
    return 0.45;
  }

  double get opacidadBorde {
    if (diasSinVisitar >= kDiasParaDeterioroFuncional) return 0.3;
    if (diasSinVisitar >= kDiasParaDeterioroVisual) return 0.55;
    return 1.0;
  }
}

class TerritoryService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Cargar todos los territorios relevantes para el home / mapa ───────────
  static Future<List<TerritoryData>> cargarTodosLosTerritorios() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    // 1. Mis amigos
    final friendsSnap = await _db
        .collection('friendships')
        .where('status', isEqualTo: 'accepted')
        .get();

    final List<String> amigoIds = [];
    for (var doc in friendsSnap.docs) {
      final data = doc.data();
      if (data['senderId'] == user.uid) {
        amigoIds.add(data['receiverId'] as String);
      } else if (data['receiverId'] == user.uid) {
        amigoIds.add(data['senderId'] as String);
      }
    }

    // 2. IDs a cargar: yo + amigos
    final List<String> todosIds = [user.uid, ...amigoIds];

    // 3. Para cada usuario, cargamos color, nickname y territorios
    final List<TerritoryData> resultado = [];

    for (final uid in todosIds) {
      // Datos del jugador
      Color color = uid == user.uid ? Colors.orange : Colors.blue;
      String nickname = '';
      try {
        final playerDoc = await _db.collection('players').doc(uid).get();
        if (playerDoc.exists) {
          final data = playerDoc.data()!;
          final colorInt = (data['territorio_color'] as num?)?.toInt();
          if (colorInt != null) color = Color(colorInt);
          nickname = data['nickname'] ?? '';
        }
      } catch (_) {}

      // Territorios del jugador
      final territoriosSnap = await _db
          .collection('territories')
          .where('userId', isEqualTo: uid)
          .get();

      for (var doc in territoriosSnap.docs) {
        final data = doc.data();
        final rawPuntos = data['puntos'] as List<dynamic>?;
        if (rawPuntos == null || rawPuntos.isEmpty) continue;

        final List<LatLng> puntos = rawPuntos.map((p) {
          final map = p as Map<String, dynamic>;
          return LatLng(
            (map['lat'] as num).toDouble(),
            (map['lng'] as num).toDouble(),
          );
        }).toList();

        final double latC = puntos.map((p) => p.latitude).reduce((a, b) => a + b) / puntos.length;
        final double lngC = puntos.map((p) => p.longitude).reduce((a, b) => a + b) / puntos.length;

        // Última visita
        DateTime? ultimaVisita;
        final tsRaw = data['ultima_visita'];
        if (tsRaw is Timestamp) {
          ultimaVisita = tsRaw.toDate();
        }

        resultado.add(TerritoryData(
          docId: doc.id,
          ownerId: uid,
          ownerNickname: nickname,
          color: color,
          puntos: puntos,
          centro: LatLng(latC, lngC),
          esMio: uid == user.uid,
          ultimaVisita: ultimaVisita,
        ));
      }
    }

    return resultado;
  }

  // ── Actualizar última visita cuando el usuario pasa por su territorio ─────
  static Future<void> actualizarUltimaVisita(String docId) async {
    try {
      await _db.collection('territories').doc(docId).update({
        'ultima_visita': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error actualizando ultima_visita: $e");
    }
  }

  // ── Detectar si el usuario está en algún territorio ───────────────────────
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
      final bool cruza = ((yi > punto.latitude) != (yj > punto.latitude)) &&
          (punto.longitude <
              (xj - xi) * (punto.latitude - yi) / (yj - yi) + xi);
      if (cruza) intersecciones++;
    }
    return intersecciones % 2 == 1;
  }

  // ── Crear notificación de invasión ────────────────────────────────────────
  static Future<void> crearNotificacionInvasion({
    required String toUserId,
    required String fromNickname,
    required String territoryId,
  }) async {
    try {
      // Evitar spam: solo crear si no hay una notificación de invasión
      // del mismo usuario en los últimos 10 minutos
      final hace10min = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 10)));

      final recientes = await FirebaseFirestore.instance
          .collection('notifications')
          .where('toUserId', isEqualTo: toUserId)
          .where('type', isEqualTo: 'territory_invasion')
          .where('timestamp', isGreaterThan: hace10min)
          .get();

      if (recientes.docs.isNotEmpty) return; // Ya hay una reciente, no spameamos

      await FirebaseFirestore.instance.collection('notifications').add({
        'toUserId': toUserId,
        'type': 'territory_invasion',
        'message': '⚔️ $fromNickname está invadiendo tu territorio AHORA MISMO. ¡Sal a defenderlo!',
        'fromNickname': fromNickname,
        'territoryId': territoryId,
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error creando notificación de invasión: $e");
    }
  }
}