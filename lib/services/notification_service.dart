// lib/services/notification_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'territory_service.dart';
import '../main.dart' show navigatorKey;

// Handler global para notificaciones cuando la app está cerrada
// DEBE estar fuera de la clase y ser una función top-level
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📩 Notificación en background: ${message.notification?.title}');
  // No invalidamos caché aquí — la app no está en memoria,
  // cuando el usuario la abra el caché estará vacío por defecto.
}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ==========================================================================
  // INICIALIZAR — se llama desde main.dart cuando el usuario está logado
  // ==========================================================================
  static Future<void> inicializar() async {
    // 1. Pedir permisos (iOS y Android 13+)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('🔔 Permisos notificaciones: ${settings.authorizationStatus}');

    // 2. Guardar token FCM en Firestore
    await _guardarToken();

    // 3. Escuchar renovaciones de token
    _messaging.onTokenRefresh.listen(_actualizarToken);

    // 4. Notificaciones mientras la app está abierta
    FirebaseMessaging.onMessage.listen(_onMensajePrimerPlano);

    // 5. Tap en notificación desde background
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificacionAbierta);

    // 6. App abierta desde estado terminado al tocar la notificación
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) _onNotificacionAbierta(initialMessage);
  }

  // ==========================================================================
  // GUARDAR TOKEN en Firestore
  // ==========================================================================
  static Future<void> _guardarToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      await _db.collection('players').doc(user.uid).update({
        'fcm_token': token,
        'fcm_token_updated': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ FCM token guardado');
    } catch (e) {
      debugPrint('❌ Error guardando FCM token: $e');
    }
  }

  static Future<void> _actualizarToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await _db.collection('players').doc(user.uid).update({
        'fcm_token': token,
        'fcm_token_updated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('❌ Error actualizando FCM token: $e');
    }
  }

  // ==========================================================================
  // HANDLERS de recepción
  // ==========================================================================
  static void _onMensajePrimerPlano(RemoteMessage message) {
    debugPrint('📩 Notificación en primer plano: ${message.notification?.title}');

    // Si alguien nos invade o conquista un territorio, invalidamos el caché
    // para que el mapa muestre los datos reales en la próxima carga.
    // Coste: cero — solo pone a null dos variables en memoria.
    final tipo = message.data['type'] as String?;
    if (tipo == 'territory_invasion' || tipo == 'territory_conquest') {
      TerritoryService.invalidarCachePorConquista();
    }
  }

  static void _onNotificacionAbierta(RemoteMessage message) {
    debugPrint('👆 Usuario abrió notificación: ${message.notification?.title}');
    final data = message.data;
    final tipo = data['type'] as String?;
    _navegarPorTipo(tipo, data);
  }

  static void _navegarPorTipo(String? tipo, Map<String, dynamic> data) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    switch (tipo) {
      case 'territory_lost':
      case 'territory_weakened':
      case 'territory_under_attack':
      case 'territory_bitten':
      case 'territory_king_lost':
        nav.pushNamed('/mapa');

      case 'follow':
        final fromUserId = data['fromUserId'] as String?;
        if (fromUserId != null) {
          nav.pushNamed('/perfil', arguments: {'userId': fromUserId});
        } else {
          nav.pushNamed('/notificaciones');
        }

      case 'desafio_ganado':
      case 'desafio_perdido':
        final desafioId = data['desafioId'] as String?;
        nav.pushNamed('/desafios', arguments: {'desafioId': desafioId});

      case 'guerra_global_recompensa':
      case 'global_territory_conquered':
      case 'global_territory_lost':
        nav.pushNamed('/mapa');

      default:
        nav.pushNamed('/notificaciones');
    }
  }

  // ==========================================================================
  // ESCUCHAR notificaciones (centro de notificaciones dentro de la app)
  // ==========================================================================
  static Stream<QuerySnapshot> escucharNotificaciones(String userId) {
    return _db
        .collection('notifications')
        .where('toUserId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
  }

  // ==========================================================================
  // MARCAR como leída
  // ==========================================================================
  static Future<void> marcarLeida(String notifId) async {
    try {
      await _db.collection('notifications').doc(notifId).update({'read': true});
    } catch (e) {
      debugPrint('❌ Error marcando notificación como leída: $e');
    }
  }

  // ==========================================================================
  // MARCAR TODAS como leídas
  // ==========================================================================
  static Future<void> marcarTodasLeidas(String userId) async {
    try {
      final snap = await _db
          .collection('notifications')
          .where('toUserId', isEqualTo: userId)
          .where('read', isEqualTo: false)
          .get();
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('❌ Error marcando todas como leídas: $e');
    }
  }

  // ==========================================================================
  // CONTAR no leídas (para el badge del icono)
  // ==========================================================================
  static Stream<int> contarNoLeidas(String userId) {
    return _db
        .collection('notifications')
        .where('toUserId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }
}