// lib/services/notification_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

// Handler global para notificaciones cuando la app está cerrada
// DEBE estar fuera de la clase y ser una función top-level
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📩 Notificación en background: ${message.notification?.title}');
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
    // Las notificaciones ya se guardan en Firestore desde Cloud Functions
    // Puedes añadir aquí un snackbar si quieres mostrar algo en pantalla
  }

  static void _onNotificacionAbierta(RemoteMessage message) {
    debugPrint('👆 Usuario abrió notificación: ${message.notification?.title}');
    // Aquí puedes navegar a la pantalla correcta según message.data['tipo']
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