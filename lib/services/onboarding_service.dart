import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Estado del onboarding de un usuario.
/// - [slidesVistos]: si ya vio los slides iniciales (se muestran solo una vez)
/// - [runActual]: cuántas carreras ha completado (0-5+)
///   Run 0 → nunca ha corrido (mostrar slides)
///   Run 1 → primera carrera completada
///   Run 2 → segunda, etc.
/// - [tooltipsVistos]: set de IDs de tooltips ya mostrados
class OnboardingState {
  final bool slidesVistos;
  final int runActual;
  final Set<String> tooltipsVistos;

  const OnboardingState({
    required this.slidesVistos,
    required this.runActual,
    required this.tooltipsVistos,
  });

  bool get onboardingCompleto => runActual >= 5;

  /// Qué tooltips corresponden a este run (se muestran UNA vez)
  List<String> get tooltipsPendientes {
    final todos = _tooltipsPorRun[runActual] ?? [];
    return todos.where((id) => !tooltipsVistos.contains(id)).toList();
  }

  static const Map<int, List<String>> _tooltipsPorRun = {
    0: ['bienvenida', 'primer_run', 'color_territorio'],
    1: ['conquista_territorio', 'mapa_live', 'color_hint', 'pausa_retirada'],
    2: ['deterioro_zonas', 'refuerzo_territorio', 'frecuencia_importa'],
    3: ['otros_jugadores', 'zona_rival', 'mapa_global'],
    4: ['invasion_posible', 'rival_notificado', 'defiende_tu_zona'],
    5: ['ligas_intro', 'puntos_liga', 'ranking_semanal'],
  };
}

class OnboardingService {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static String? get _uid => _auth.currentUser?.uid;

  /// Lee el estado actual del onboarding desde Firestore
  static Future<OnboardingState> cargarEstado() async {
    final uid = _uid;
    if (uid == null) {
      return const OnboardingState(slidesVistos: false, runActual: 0, tooltipsVistos: {});
    }
    try {
      final doc = await _db.collection('players').doc(uid).get();
      if (!doc.exists) {
        return const OnboardingState(slidesVistos: false, runActual: 0, tooltipsVistos: {});
      }
      final data = doc.data()!;
      final slides  = (data['onboarding_slides_vistos'] as bool?) ?? false;
      final run     = (data['onboarding_run_actual']    as num?)?.toInt() ?? 0;
      final tvRaw   = (data['onboarding_tooltips_vistos'] as List<dynamic>?) ?? [];
      final tv      = tvRaw.map((e) => e.toString()).toSet();
      return OnboardingState(slidesVistos: slides, runActual: run, tooltipsVistos: tv);
    } catch (e) {
      return const OnboardingState(slidesVistos: false, runActual: 0, tooltipsVistos: {});
    }
  }

  /// Marca los slides como vistos
  static Future<void> marcarSlidesVistos() async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('players').doc(uid).set(
      {'onboarding_slides_vistos': true},
      SetOptions(merge: true),
    );
  }

  /// Incrementa el contador de runs completados
  static Future<void> registrarRunCompletado() async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('players').doc(uid).set(
      {'onboarding_run_actual': FieldValue.increment(1)},
      SetOptions(merge: true),
    );
  }

  /// Marca un tooltip concreto como visto
  static Future<void> marcarTooltipVisto(String tooltipId) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('players').doc(uid).set({
      'onboarding_tooltips_vistos': FieldValue.arrayUnion([tooltipId]),
    }, SetOptions(merge: true));
  }

  /// Marca varios tooltips como vistos de una vez
  static Future<void> marcarTooltipsVistos(List<String> ids) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('players').doc(uid).set({
      'onboarding_tooltips_vistos': FieldValue.arrayUnion(ids),
    }, SetOptions(merge: true));
  }

  /// Reset completo (para testing)
  static Future<void> resetearOnboarding() async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('players').doc(uid).set({
      'onboarding_slides_vistos':    false,
      'onboarding_run_actual':       0,
      'onboarding_tooltips_vistos':  [],
    }, SetOptions(merge: true));
  }
}