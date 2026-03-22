// lib/services/subscription_service.dart
//
// ══════════════════════════════════════════════════════════════════════════════
//  RUNNER RISK — Sistema de Suscripción Premium
//  purchases_flutter ^9.x
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

// =============================================================================
// CONFIGURACIÓN
// =============================================================================

class _RCConfig {
  static const String apiKeyAndroid      = 'TU_KEY_ANDROID_AQUI';
  static const String apiKeyIOS          = 'TU_KEY_IOS_AQUI';
  static const String entitlementPremium = 'premium';
}

// =============================================================================
// MODELO DE ESTADO
// =============================================================================

enum SubscriptionPlan { none, monthly, annual }

class SubscriptionStatus {
  final bool isPremium;
  final SubscriptionPlan plan;
  final DateTime? expirationDate;
  final bool isInTrial;
  final String? productIdentifier;

  const SubscriptionStatus({
    required this.isPremium,
    required this.plan,
    this.expirationDate,
    this.isInTrial = false,
    this.productIdentifier,
  });

  static const SubscriptionStatus free = SubscriptionStatus(
    isPremium: false,
    plan: SubscriptionPlan.none,
  );

  int? get daysRemaining {
    if (expirationDate == null) return null;
    final diff = expirationDate!.difference(DateTime.now()).inDays;
    return diff > 0 ? diff : 0;
  }

  static double get annualSavingPercent {
    const monthlyYearCost = 4.99 * 12;
    const annualCost      = 39.99;
    return ((monthlyYearCost - annualCost) / monthlyYearCost * 100);
  }
}

// =============================================================================
// FEATURES PREMIUM
// =============================================================================

class PremiumFeatures {
  /// Radio del radar: 300m free / 500m premium
  static const double radioRadarFreeM    = 300.0;
  static const double radioRadarPremiumM = 500.0;

  /// Historial de carreras: 30 free / 200 premium
  static const int limitHistorialFree    = 30;
  static const int limitHistorialPremium = 200;

  /// Rutas guardadas: 5 free / ilimitadas premium
  static const int rutasGuardadasFree    = 5;
  static const int rutasGuardadasPremium = 9999;

  /// Días de escudo de bienvenida al suscribirse
  static const int diasEscudoBienvenida  = 7;

  /// Monedas de bienvenida al suscribirse
  static const int monedasBienvenida     = 500;
}

// =============================================================================
// RESULTADO DE COMPRA
// =============================================================================

class BuyResult {
  final bool success;
  final bool cancelled;
  final String? error;
  final SubscriptionStatus? status;

  const BuyResult._({
    required this.success,
    required this.cancelled,
    this.error,
    this.status,
  });

  factory BuyResult.success(SubscriptionStatus s) =>
      BuyResult._(success: true, cancelled: false, status: s);

  factory BuyResult.cancelled() =>
      BuyResult._(success: false, cancelled: true);

  factory BuyResult.error(String msg) =>
      BuyResult._(success: false, cancelled: false, error: msg);
}

// =============================================================================
// SERVICIO PRINCIPAL
// =============================================================================

class SubscriptionService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static final StreamController<SubscriptionStatus> _statusController =
      StreamController<SubscriptionStatus>.broadcast();

  static Stream<SubscriptionStatus> get statusStream =>
      _statusController.stream;

  static SubscriptionStatus _currentStatus = SubscriptionStatus.free;
  static SubscriptionStatus get currentStatus => _currentStatus;

  // ── INICIALIZAR ───────────────────────────────────────────────────────────

  static Future<void> inicializar(String userId) async {
    try {
      await rc.Purchases.setLogLevel(rc.LogLevel.error);

      final configuration = rc.PurchasesConfiguration(
        Platform.isAndroid ? _RCConfig.apiKeyAndroid : _RCConfig.apiKeyIOS,
      )..appUserID = userId;

      await rc.Purchases.configure(configuration);
      rc.Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdated);
      await refreshStatus();

      debugPrint('✅ RevenueCat inicializado para usuario: $userId');
    } catch (e) {
      debugPrint('❌ Error inicializando RevenueCat: $e');
      await _cargarEstadoDesdeFirestore(userId);
    }
  }

  // ── ESCUCHAR CAMBIOS ──────────────────────────────────────────────────────

  static void _onCustomerInfoUpdated(rc.CustomerInfo info) {
    final status = _parseCustomerInfo(info);
    _currentStatus = status;
    _statusController.add(status);
    _sincronizarConFirestore(status);
    debugPrint('🔄 CustomerInfo actualizado — Premium: ${status.isPremium}');
  }

  // ── REFRESCAR ─────────────────────────────────────────────────────────────

  static Future<SubscriptionStatus> refreshStatus() async {
    try {
      final info   = await rc.Purchases.getCustomerInfo();
      final status = _parseCustomerInfo(info);
      _currentStatus = status;
      _statusController.add(status);
      await _sincronizarConFirestore(status);
      return status;
    } catch (e) {
      debugPrint('❌ Error refrescando estado RevenueCat: $e');
      return _currentStatus;
    }
  }

  // ── OFFERINGS ─────────────────────────────────────────────────────────────

  static Future<rc.Offerings?> obtenerOfferings() async {
    try {
      return await rc.Purchases.getOfferings();
    } catch (e) {
      debugPrint('❌ Error obteniendo offerings: $e');
      return null;
    }
  }

  // ── COMPRAR ───────────────────────────────────────────────────────────────

  static Future<BuyResult> comprar(rc.Package package) async {
    try {
      final rc.PurchaseResult result =
          await rc.Purchases.purchasePackage(package);

      final status = _parseCustomerInfo(result.customerInfo);
      _currentStatus = status;
      _statusController.add(status);
      await _sincronizarConFirestore(status);

      if (status.isPremium) {
        await _darRecompensaBienvenida();
        await _activarFeaturesPremium();
      }

      return BuyResult.success(status);
    } on PlatformException catch (e) {
      final errorCode = rc.PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == rc.PurchasesErrorCode.purchaseCancelledError) {
        return BuyResult.cancelled();
      }
      debugPrint('❌ Error de compra RevenueCat: ${e.message}');
      return BuyResult.error(e.message ?? 'Error desconocido');
    } catch (e) {
      debugPrint('❌ Error inesperado en compra: $e');
      return BuyResult.error(e.toString());
    }
  }

  // ── RESTAURAR ─────────────────────────────────────────────────────────────

  static Future<SubscriptionStatus> restaurarCompras() async {
    try {
      final info   = await rc.Purchases.restorePurchases();
      final status = _parseCustomerInfo(info);
      _currentStatus = status;
      _statusController.add(status);
      await _sincronizarConFirestore(status);
      return status;
    } on PlatformException catch (e) {
      debugPrint('❌ Error restaurando compras: ${e.message}');
      return _currentStatus;
    } catch (e) {
      debugPrint('❌ Error inesperado restaurando: $e');
      return _currentStatus;
    }
  }

  // ── PARSEAR CustomerInfo ──────────────────────────────────────────────────

  static SubscriptionStatus _parseCustomerInfo(rc.CustomerInfo info) {
    final entitlement =
        info.entitlements.active[_RCConfig.entitlementPremium];

    if (entitlement == null) return SubscriptionStatus.free;

    final productId = entitlement.productIdentifier;
    final plan      = productId.contains('annual')
        ? SubscriptionPlan.annual
        : SubscriptionPlan.monthly;

    DateTime? expiration;
    final expStr = entitlement.expirationDate;
    if (expStr != null) expiration = DateTime.tryParse(expStr);

    return SubscriptionStatus(
      isPremium:         true,
      plan:              plan,
      expirationDate:    expiration,
      isInTrial:         entitlement.periodType == rc.PeriodType.trial,
      productIdentifier: productId,
    );
  }

  // ── FIRESTORE SYNC ────────────────────────────────────────────────────────

  static Future<void> _sincronizarConFirestore(
      SubscriptionStatus status) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('players').doc(uid).update({
        'is_premium':           status.isPremium,
        'subscription_plan':    status.plan.name,
        'subscription_expires': status.expirationDate != null
            ? Timestamp.fromDate(status.expirationDate!)
            : null,
        'premium_updated_at':   FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error sincronizando premium con Firestore: $e');
    }
  }

  // ── ACTIVAR FEATURES AL SUSCRIBIRSE ──────────────────────────────────────

  static Future<void> _activarFeaturesPremium() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('players').doc(uid).update({
        'premium_radio_radar':         PremiumFeatures.radioRadarPremiumM,
        'premium_historial_limite':    PremiumFeatures.limitHistorialPremium,
        'premium_rutas_limite':        PremiumFeatures.rutasGuardadasPremium,
        'premium_estilos_mapa':        true,
        'premium_stats_avanzadas':     true,
        'premium_retos_extra':         true,
        'premium_animacion_conquista': true,
      });
      debugPrint('✅ Features Premium activadas en Firestore');
    } catch (e) {
      debugPrint('Error activando features premium: $e');
    }
  }

  // ── RECOMPENSA BIENVENIDA ─────────────────────────────────────────────────
  // FIX: ahora escribe escudo_activo + escudo_expira que son los campos
  // que lee el juego en home_screen para verificar si el territorio
  // está protegido. Antes escribía 'proteccion_hasta' que nadie leía.

  static Future<void> _darRecompensaBienvenida() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc       = await _db.collection('players').doc(uid).get();
      final yaRecibio = (doc.data()?['premium_welcome_reward'] as bool?) ?? false;
      if (yaRecibio) return;

      final escudoExpira = DateTime.now()
          .add(Duration(days: PremiumFeatures.diasEscudoBienvenida));

      await _db.collection('players').doc(uid).update({
        // Monedas de bienvenida
        'monedas':                FieldValue.increment(
            PremiumFeatures.monedasBienvenida),
        // Flag para no dar la recompensa dos veces
        'premium_welcome_reward': true,
        // ── Escudo: campos que lee el juego ──────────────────────────────
        // home_screen.dart lee escudo_activo + escudo_expira
        // NO el campo 'proteccion_hasta' que había antes
        'escudo_activo':          true,
        'escudo_expira':          Timestamp.fromDate(escudoExpira),
      });

      await _db.collection('notifications').add({
        'toUserId':  uid,
        'type':      'premium_welcome',
        'message':
            '👑 ¡Bienvenido a Runner Risk Premium! '
            'Te hemos regalado ${PremiumFeatures.monedasBienvenida} 🪙 '
            'y ${PremiumFeatures.diasEscudoBienvenida} días de escudo extra.',
        'read':      false,
        'timestamp': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Recompensa de bienvenida premium entregada — '
          'escudo hasta: $escudoExpira');
    } catch (e) {
      debugPrint('Error entregando recompensa premium: $e');
    }
  }

  // ── FALLBACK FIRESTORE ────────────────────────────────────────────────────

  static Future<void> _cargarEstadoDesdeFirestore(String userId) async {
    try {
      final doc = await _db.collection('players').doc(userId).get();
      if (!doc.exists) return;
      final data      = doc.data()!;
      final isPremium = (data['is_premium'] as bool?) ?? false;
      final planStr   = (data['subscription_plan'] as String?) ?? 'none';
      final expTs     = data['subscription_expires'] as Timestamp?;

      final plan = SubscriptionPlan.values.firstWhere(
        (p) => p.name == planStr,
        orElse: () => SubscriptionPlan.none,
      );

      _currentStatus = SubscriptionStatus(
        isPremium:      isPremium,
        plan:           plan,
        expirationDate: expTs?.toDate(),
      );
      _statusController.add(_currentStatus);
    } catch (e) {
      debugPrint('Error cargando estado desde Firestore: $e');
    }
  }

  // ── HELPERS DE COMPROBACIÓN ───────────────────────────────────────────────

  static bool tieneAcceso(bool featurePremium) {
    if (!featurePremium) return true;
    return _currentStatus.isPremium;
  }

  static double get radioRadar => _currentStatus.isPremium
      ? PremiumFeatures.radioRadarPremiumM
      : PremiumFeatures.radioRadarFreeM;

  static int get limiteHistorial => _currentStatus.isPremium
      ? PremiumFeatures.limitHistorialPremium
      : PremiumFeatures.limitHistorialFree;

  static int get limiteRutas => _currentStatus.isPremium
      ? PremiumFeatures.rutasGuardadasPremium
      : PremiumFeatures.rutasGuardadasFree;

  static bool get animacionConquistaEspecial => _currentStatus.isPremium;
  static bool get estilosMapaActivos         => _currentStatus.isPremium;
  static bool get statsAvanzadasActivas      => _currentStatus.isPremium;
  static bool get retosExtraActivos          => _currentStatus.isPremium;

  // ── CLEANUP ───────────────────────────────────────────────────────────────

  static void dispose() {
    _statusController.close();
  }
}