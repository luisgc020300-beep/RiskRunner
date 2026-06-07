// lib/services/training_plan_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ── Tipos de sesión ───────────────────────────────────────────────────────────
enum SessionType { rest, easy, intervals, tempo, longRun, race }

extension SessionTypeX on SessionType {
  String get label {
    switch (this) {
      case SessionType.rest:      return 'Descanso';
      case SessionType.easy:      return 'Rodaje fácil';
      case SessionType.intervals: return 'Intervalos';
      case SessionType.tempo:     return 'Tempo';
      case SessionType.longRun:   return 'Tirada larga';
      case SessionType.race:      return '¡Carrera!';
    }
  }

  IconData get icon {
    switch (this) {
      case SessionType.rest:      return Icons.bedtime_outlined;
      case SessionType.easy:      return Icons.directions_run_rounded;
      case SessionType.intervals: return Icons.flash_on_rounded;
      case SessionType.tempo:     return Icons.speed_rounded;
      case SessionType.longRun:   return Icons.route_rounded;
      case SessionType.race:      return Icons.emoji_events_rounded;
    }
  }

  Color get color {
    switch (this) {
      case SessionType.rest:      return const Color(0xFF636366);
      case SessionType.easy:      return const Color(0xFF34C759);
      case SessionType.intervals: return const Color(0xFFFF9500);
      case SessionType.tempo:     return const Color(0xFF0A84FF);
      case SessionType.longRun:   return const Color(0xFFBF5AF2);
      case SessionType.race:      return const Color(0xFFE02020);
    }
  }

  bool get isRun => this != SessionType.rest;
}

// ── Modelos ───────────────────────────────────────────────────────────────────
class TrainingSession {
  final int week;       // 1-indexed
  final int slot;       // 1-indexed position within the week (1..N)
  final int weekday;    // 1=Mon..7=Sun
  final SessionType type;
  final double targetKm;
  final String note;

  const TrainingSession({
    required this.week,
    required this.slot,
    required this.weekday,
    required this.type,
    required this.targetKm,
    required this.note,
  });

  String get key => '$week-$slot';
}

class TrainingPlan {
  final String id;
  final String name;
  final String subtitle;
  final String targetLabel;
  final int weeks;
  final int sessionsPerWeek;
  final Color color;
  final IconData icon;
  final List<TrainingSession> sessions;

  const TrainingPlan({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.targetLabel,
    required this.weeks,
    required this.sessionsPerWeek,
    required this.color,
    required this.icon,
    required this.sessions,
  });

  List<TrainingSession> week(int w) =>
      sessions.where((s) => s.week == w).toList()
        ..sort((a, b) => a.slot.compareTo(b.slot));

  int get totalSessions =>
      sessions.where((s) => s.type != SessionType.rest).length;
}

class UserPlanState {
  final String planId;
  final DateTime startDate;
  final List<String> completedSessions;
  // Solo para planes generados por IA
  final Map<String, dynamic>? aiPlanData;

  const UserPlanState({
    required this.planId,
    required this.startDate,
    required this.completedSessions,
    this.aiPlanData,
  });

  factory UserPlanState.fromMap(Map<String, dynamic> d) => UserPlanState(
    planId: d['planId'] as String,
    startDate: (d['startDate'] as Timestamp).toDate(),
    completedSessions: List<String>.from(d['completedSessions'] ?? []),
    aiPlanData: d['aiPlanData'] as Map<String, dynamic>?,
  );

  Map<String, dynamic> toMap() => {
    'planId': planId,
    'startDate': Timestamp.fromDate(startDate),
    'completedSessions': completedSessions,
    if (aiPlanData != null) 'aiPlanData': aiPlanData,
  };

  // Semana actual (1-indexed) según cuántos días han pasado desde el inicio
  int get currentWeek {
    final days = DateTime.now().difference(startDate).inDays;
    return (days ~/ 7) + 1;
  }

  bool isCompleted(String key) => completedSessions.contains(key);

  double progressIn(TrainingPlan plan) {
    final total = plan.totalSessions;
    if (total == 0) return 0;
    return completedSessions.length / total;
  }
}

// ── Servicio Firestore ────────────────────────────────────────────────────────
class TrainingPlanService {
  static final _db = FirebaseFirestore.instance;

  static DocumentReference _ref(String uid) =>
      _db.collection('training_plans').doc(uid);

  static Future<UserPlanState?> loadState(String uid) async {
    final snap = await _ref(uid).get();
    if (!snap.exists) return null;
    try {
      return UserPlanState.fromMap(snap.data() as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Stream<UserPlanState?> stream(String uid) =>
      _ref(uid).snapshots().map((snap) {
        if (!snap.exists) return null;
        try {
          return UserPlanState.fromMap(snap.data() as Map<String, dynamic>);
        } catch (_) {
          return null;
        }
      });

  static Future<void> startPlan(String uid, String planId) async {
    await _ref(uid).set(UserPlanState(
      planId: planId,
      startDate: DateTime.now(),
      completedSessions: [],
    ).toMap());
  }

  static Future<void> markSession(
      String uid, String sessionKey, bool completed) async {
    if (completed) {
      await _ref(uid).update({
        'completedSessions': FieldValue.arrayUnion([sessionKey]),
      });
    } else {
      await _ref(uid).update({
        'completedSessions': FieldValue.arrayRemove([sessionKey]),
      });
    }
  }

  static Future<void> abandonPlan(String uid) async {
    await _ref(uid).delete();
  }

  static Future<void> startAiPlan(
      String uid, Map<String, dynamic> aiPlanData) async {
    await _ref(uid).set(UserPlanState(
      planId: 'plan_ai',
      startDate: DateTime.now(),
      completedSessions: [],
      aiPlanData: aiPlanData,
    ).toMap());
  }
}

// ── Constructor de plan desde datos IA ───────────────────────────────────────
SessionType _parseSessionType(String s) {
  switch (s) {
    case 'rest':      return SessionType.rest;
    case 'intervals': return SessionType.intervals;
    case 'tempo':     return SessionType.tempo;
    case 'longRun':   return SessionType.longRun;
    case 'race':      return SessionType.race;
    default:          return SessionType.easy;
  }
}

TrainingPlan buildPlanFromAiData(Map<String, dynamic> data) {
  final rawSessions = (data['sessions'] as List).cast<Map<String, dynamic>>();
  final sessions = rawSessions.map((s) => TrainingSession(
    week:      (s['week']      as num).toInt(),
    slot:      (s['slot']      as num).toInt(),
    weekday:   (s['weekday']   as num).toInt(),
    type:      _parseSessionType(s['type'] as String? ?? 'easy'),
    targetKm:  (s['targetKm']  as num).toDouble(),
    note:       s['note']      as String? ?? '',
  )).toList();

  return TrainingPlan(
    id:             'plan_ai',
    name:           data['name']           as String? ?? 'Plan Personalizado',
    subtitle:       data['subtitle']       as String? ?? 'Generado por IA',
    targetLabel:    data['targetLabel']    as String? ?? 'OBJETIVO',
    weeks:          (data['weeks']         as num).toInt(),
    sessionsPerWeek:(data['sessionsPerWeek'] as num?)?.toInt() ?? 3,
    color:          const Color(0xFF0A84FF),
    icon:           Icons.auto_awesome_rounded,
    sessions:       sessions,
  );
}

// ── Planes integrados ─────────────────────────────────────────────────────────
// días de la semana: 1=Lun, 3=Mié, 6=Sáb (plan 3 días)
//                   1=Lun, 2=Mar, 4=Jue, 6=Sáb (plan 4 días)

final kPlan5K = TrainingPlan(
  id: 'plan_5k',
  name: 'Plan 5K',
  subtitle: 'Principiante · 6 semanas',
  targetLabel: '5 KM',
  weeks: 6,
  sessionsPerWeek: 3,
  color: const Color(0xFF34C759),
  icon: Icons.directions_run_rounded,
  sessions: _s5k,
);

final kPlan10K = TrainingPlan(
  id: 'plan_10k',
  name: 'Plan 10K',
  subtitle: 'Intermedio · 8 semanas',
  targetLabel: '10 KM',
  weeks: 8,
  sessionsPerWeek: 4,
  color: const Color(0xFF0A84FF),
  icon: Icons.speed_rounded,
  sessions: _s10k,
);

final kPlanHM = TrainingPlan(
  id: 'plan_hm',
  name: 'Plan Media Maratón',
  subtitle: 'Avanzado · 12 semanas',
  targetLabel: '21 KM',
  weeks: 12,
  sessionsPerWeek: 4,
  color: const Color(0xFFBF5AF2),
  icon: Icons.emoji_events_rounded,
  sessions: _sHM,
);

final kAllPlans = [kPlan5K, kPlan10K, kPlanHM];

TrainingPlan? planById(String id) =>
    kAllPlans.where((p) => p.id == id).firstOrNull;

// ── Sesiones plan 5K ─────────────────────────────────────────────────────────
// 3 sesiones/semana: slots 1(Lun), 2(Mié), 3(Sáb)
const _s5k = [
  // Semana 1 — arranque suave
  TrainingSession(week:1, slot:1, weekday:1, type:SessionType.easy,      targetKm:2.0, note:'Trota a ritmo conversacional'),
  TrainingSession(week:1, slot:2, weekday:3, type:SessionType.easy,      targetKm:2.5, note:'Sin prisa, disfruta el trayecto'),
  TrainingSession(week:1, slot:3, weekday:6, type:SessionType.easy,      targetKm:3.0, note:'Primera tirada de la semana'),
  // Semana 2 — volumen ligero
  TrainingSession(week:2, slot:1, weekday:1, type:SessionType.easy,      targetKm:2.5, note:'Ritmo cómodo, respira por la nariz'),
  TrainingSession(week:2, slot:2, weekday:3, type:SessionType.intervals,  targetKm:3.0, note:'4×400 m rápido con 1 min descanso'),
  TrainingSession(week:2, slot:3, weekday:6, type:SessionType.easy,      targetKm:4.0, note:'Tirada larga tranquila'),
  // Semana 3 — primera subida
  TrainingSession(week:3, slot:1, weekday:1, type:SessionType.easy,      targetKm:3.0, note:'Rodaje base'),
  TrainingSession(week:3, slot:2, weekday:3, type:SessionType.intervals,  targetKm:3.5, note:'5×400 m con 90 s descanso'),
  TrainingSession(week:3, slot:3, weekday:6, type:SessionType.longRun,   targetKm:4.5, note:'Ritmo muy suave, no pares'),
  // Semana 4 — recuperación
  TrainingSession(week:4, slot:1, weekday:1, type:SessionType.easy,      targetKm:2.0, note:'Semana de descarga, ve despacio'),
  TrainingSession(week:4, slot:2, weekday:3, type:SessionType.easy,      targetKm:2.5, note:'Solo activa piernas'),
  TrainingSession(week:4, slot:3, weekday:6, type:SessionType.easy,      targetKm:3.5, note:'Rodaje suave largo'),
  // Semana 5 — pico de carga
  TrainingSession(week:5, slot:1, weekday:1, type:SessionType.easy,      targetKm:3.0, note:'Rodaje base'),
  TrainingSession(week:5, slot:2, weekday:3, type:SessionType.tempo,     targetKm:4.0, note:'20 min a ritmo de carrera'),
  TrainingSession(week:5, slot:3, weekday:6, type:SessionType.longRun,   targetKm:5.0, note:'Tu primer 5K completo'),
  // Semana 6 — semana de carrera
  TrainingSession(week:6, slot:1, weekday:1, type:SessionType.easy,      targetKm:3.0, note:'Últimas piernas fáciles'),
  TrainingSession(week:6, slot:2, weekday:3, type:SessionType.easy,      targetKm:2.0, note:'Sacudida suave, sin forzar'),
  TrainingSession(week:6, slot:3, weekday:6, type:SessionType.race,      targetKm:5.0, note:'¡Da todo, eres capaz!'),
];

// ── Sesiones plan 10K ────────────────────────────────────────────────────────
// 4 sesiones/semana: slots 1(Lun), 2(Mar), 3(Jue), 4(Sáb)
const _s10k = [
  // W1
  TrainingSession(week:1, slot:1, weekday:1, type:SessionType.easy,      targetKm:5.0,  note:'Base aeróbica, ritmo cómodo'),
  TrainingSession(week:1, slot:2, weekday:2, type:SessionType.easy,      targetKm:4.0,  note:'Rodaje regenerativo'),
  TrainingSession(week:1, slot:3, weekday:4, type:SessionType.intervals,  targetKm:4.0,  note:'6×400 m con 90 s descanso'),
  TrainingSession(week:1, slot:4, weekday:6, type:SessionType.longRun,   targetKm:7.0,  note:'Ritmo muy suave'),
  // W2
  TrainingSession(week:2, slot:1, weekday:1, type:SessionType.easy,      targetKm:5.0,  note:'Rodaje base'),
  TrainingSession(week:2, slot:2, weekday:2, type:SessionType.tempo,     targetKm:4.0,  note:'25 min a ritmo 10K'),
  TrainingSession(week:2, slot:3, weekday:4, type:SessionType.intervals,  targetKm:5.0,  note:'6×600 m con 2 min descanso'),
  TrainingSession(week:2, slot:4, weekday:6, type:SessionType.longRun,   targetKm:8.0,  note:'Sin cronómetro, solo disfruta'),
  // W3
  TrainingSession(week:3, slot:1, weekday:1, type:SessionType.easy,      targetKm:6.0,  note:'Rodaje base'),
  TrainingSession(week:3, slot:2, weekday:2, type:SessionType.easy,      targetKm:4.0,  note:'Piernas frescas'),
  TrainingSession(week:3, slot:3, weekday:4, type:SessionType.intervals,  targetKm:5.0,  note:'8×400 m con 90 s descanso'),
  TrainingSession(week:3, slot:4, weekday:6, type:SessionType.longRun,   targetKm:9.0,  note:'Tirada larga, come bien antes'),
  // W4 recuperación
  TrainingSession(week:4, slot:1, weekday:1, type:SessionType.easy,      targetKm:4.0,  note:'Descarga, ve despacio'),
  TrainingSession(week:4, slot:2, weekday:2, type:SessionType.easy,      targetKm:3.0,  note:'Recuperación activa'),
  TrainingSession(week:4, slot:3, weekday:4, type:SessionType.easy,      targetKm:4.0,  note:'Rodaje ligero'),
  TrainingSession(week:4, slot:4, weekday:6, type:SessionType.longRun,   targetKm:7.0,  note:'Semana de recuperación'),
  // W5
  TrainingSession(week:5, slot:1, weekday:1, type:SessionType.easy,      targetKm:6.0,  note:'Rodaje base'),
  TrainingSession(week:5, slot:2, weekday:2, type:SessionType.tempo,     targetKm:5.0,  note:'30 min a ritmo objetivo'),
  TrainingSession(week:5, slot:3, weekday:4, type:SessionType.intervals,  targetKm:6.0,  note:'6×800 m con 2 min descanso'),
  TrainingSession(week:5, slot:4, weekday:6, type:SessionType.longRun,   targetKm:10.0, note:'Primera vez en 10K'),
  // W6
  TrainingSession(week:6, slot:1, weekday:1, type:SessionType.easy,      targetKm:6.0,  note:'Rodaje base'),
  TrainingSession(week:6, slot:2, weekday:2, type:SessionType.tempo,     targetKm:5.0,  note:'Ritmo firme sostenido'),
  TrainingSession(week:6, slot:3, weekday:4, type:SessionType.intervals,  targetKm:6.0,  note:'8×600 m fuerte'),
  TrainingSession(week:6, slot:4, weekday:6, type:SessionType.longRun,   targetKm:11.0, note:'Aguanta el ritmo uniforme'),
  // W7
  TrainingSession(week:7, slot:1, weekday:1, type:SessionType.easy,      targetKm:7.0,  note:'Volumen alto, ritmo suave'),
  TrainingSession(week:7, slot:2, weekday:2, type:SessionType.tempo,     targetKm:5.0,  note:'Aprieta los últimos minutos'),
  TrainingSession(week:7, slot:3, weekday:4, type:SessionType.intervals,  targetKm:7.0,  note:'5×1000 m con 3 min descanso'),
  TrainingSession(week:7, slot:4, weekday:6, type:SessionType.longRun,   targetKm:12.0, note:'Máxima tirada del plan'),
  // W8 carrera
  TrainingSession(week:8, slot:1, weekday:1, type:SessionType.easy,      targetKm:4.0,  note:'Solo mueve las piernas'),
  TrainingSession(week:8, slot:2, weekday:2, type:SessionType.easy,      targetKm:3.0,  note:'Relajado, nada de esfuerzo'),
  TrainingSession(week:8, slot:3, weekday:4, type:SessionType.easy,      targetKm:2.0,  note:'Sacudida previa a la carrera'),
  TrainingSession(week:8, slot:4, weekday:6, type:SessionType.race,      targetKm:10.0, note:'¡Deja todo en la pista!'),
];

// ── Sesiones media maratón ───────────────────────────────────────────────────
// 4 sesiones/semana: slots 1(Lun), 2(Mié), 3(Jue), 4(Sáb)
const _sHM = [
  // W1
  TrainingSession(week:1,  slot:1, weekday:1, type:SessionType.easy,      targetKm:6.0,  note:'Base aeróbica larga'),
  TrainingSession(week:1,  slot:2, weekday:3, type:SessionType.intervals,  targetKm:5.0,  note:'6×800 m con 2 min descanso'),
  TrainingSession(week:1,  slot:3, weekday:4, type:SessionType.easy,      targetKm:6.0,  note:'Rodaje medio fácil'),
  TrainingSession(week:1,  slot:4, weekday:6, type:SessionType.longRun,   targetKm:10.0, note:'Lento y constante'),
  // W2
  TrainingSession(week:2,  slot:1, weekday:1, type:SessionType.easy,      targetKm:7.0,  note:'Rodaje base'),
  TrainingSession(week:2,  slot:2, weekday:3, type:SessionType.tempo,     targetKm:6.0,  note:'35 min a ritmo HM'),
  TrainingSession(week:2,  slot:3, weekday:4, type:SessionType.easy,      targetKm:7.0,  note:'Piernas activas'),
  TrainingSession(week:2,  slot:4, weekday:6, type:SessionType.longRun,   targetKm:12.0, note:'Incrementa volumen'),
  // W3
  TrainingSession(week:3,  slot:1, weekday:1, type:SessionType.easy,      targetKm:8.0,  note:'Base sólida'),
  TrainingSession(week:3,  slot:2, weekday:3, type:SessionType.intervals,  targetKm:6.0,  note:'5×1000 m con 3 min descanso'),
  TrainingSession(week:3,  slot:3, weekday:4, type:SessionType.easy,      targetKm:8.0,  note:'Recuperación activa'),
  TrainingSession(week:3,  slot:4, weekday:6, type:SessionType.longRun,   targetKm:14.0, note:'Primer contacto con la distancia'),
  // W4 recuperación
  TrainingSession(week:4,  slot:1, weekday:1, type:SessionType.easy,      targetKm:5.0,  note:'Semana de descarga'),
  TrainingSession(week:4,  slot:2, weekday:3, type:SessionType.easy,      targetKm:4.0,  note:'Piernas ligeras'),
  TrainingSession(week:4,  slot:3, weekday:4, type:SessionType.easy,      targetKm:5.0,  note:'Recuperación'),
  TrainingSession(week:4,  slot:4, weekday:6, type:SessionType.longRun,   targetKm:10.0, note:'Lenta y tranquila'),
  // W5
  TrainingSession(week:5,  slot:1, weekday:1, type:SessionType.easy,      targetKm:8.0,  note:'Vuelve con energía'),
  TrainingSession(week:5,  slot:2, weekday:3, type:SessionType.tempo,     targetKm:7.0,  note:'40 min a ritmo objetivo'),
  TrainingSession(week:5,  slot:3, weekday:4, type:SessionType.easy,      targetKm:8.0,  note:'Rodaje base'),
  TrainingSession(week:5,  slot:4, weekday:6, type:SessionType.longRun,   targetKm:16.0, note:'Gestiona bien el ritmo'),
  // W6
  TrainingSession(week:6,  slot:1, weekday:1, type:SessionType.easy,      targetKm:9.0,  note:'Volumen en aumento'),
  TrainingSession(week:6,  slot:2, weekday:3, type:SessionType.intervals,  targetKm:7.0,  note:'4×2000 m con 3 min descanso'),
  TrainingSession(week:6,  slot:3, weekday:4, type:SessionType.easy,      targetKm:9.0,  note:'Rodaje'),
  TrainingSession(week:6,  slot:4, weekday:6, type:SessionType.longRun,   targetKm:18.0, note:'Cerca de la meta, mantén'),
  // W7 descarga media
  TrainingSession(week:7,  slot:1, weekday:1, type:SessionType.easy,      targetKm:8.0,  note:'Baja la carga un poco'),
  TrainingSession(week:7,  slot:2, weekday:3, type:SessionType.tempo,     targetKm:8.0,  note:'Ritmo de carrera sostenido'),
  TrainingSession(week:7,  slot:3, weekday:4, type:SessionType.easy,      targetKm:8.0,  note:'Rodaje cómodo'),
  TrainingSession(week:7,  slot:4, weekday:6, type:SessionType.longRun,   targetKm:15.0, note:'Regeneración de piernas'),
  // W8
  TrainingSession(week:8,  slot:1, weekday:1, type:SessionType.easy,      targetKm:9.0,  note:'Rodaje base'),
  TrainingSession(week:8,  slot:2, weekday:3, type:SessionType.intervals,  targetKm:8.0,  note:'5×1200 m con 3 min descanso'),
  TrainingSession(week:8,  slot:3, weekday:4, type:SessionType.easy,      targetKm:9.0,  note:'Piernas activas'),
  TrainingSession(week:8,  slot:4, weekday:6, type:SessionType.longRun,   targetKm:19.0, note:'La tirada más larga'),
  // W9
  TrainingSession(week:9,  slot:1, weekday:1, type:SessionType.easy,      targetKm:10.0, note:'Volumen pico'),
  TrainingSession(week:9,  slot:2, weekday:3, type:SessionType.tempo,     targetKm:8.0,  note:'45 min firme'),
  TrainingSession(week:9,  slot:3, weekday:4, type:SessionType.easy,      targetKm:10.0, note:'Rodaje largo fácil'),
  TrainingSession(week:9,  slot:4, weekday:6, type:SessionType.longRun,   targetKm:21.0, note:'Simulacro de carrera, ¡puedes!'),
  // W10 recuperación
  TrainingSession(week:10, slot:1, weekday:1, type:SessionType.easy,      targetKm:6.0,  note:'Descarga necesaria'),
  TrainingSession(week:10, slot:2, weekday:3, type:SessionType.easy,      targetKm:5.0,  note:'Solo mantén el movimiento'),
  TrainingSession(week:10, slot:3, weekday:4, type:SessionType.easy,      targetKm:6.0,  note:'Piernas frescas'),
  TrainingSession(week:10, slot:4, weekday:6, type:SessionType.longRun,   targetKm:14.0, note:'Lenta, sin presión'),
  // W11
  TrainingSession(week:11, slot:1, weekday:1, type:SessionType.easy,      targetKm:8.0,  note:'Última semana de carga'),
  TrainingSession(week:11, slot:2, weekday:3, type:SessionType.tempo,     targetKm:8.0,  note:'Ritmo objetivo mantenido'),
  TrainingSession(week:11, slot:3, weekday:4, type:SessionType.intervals,  targetKm:8.0,  note:'4×1000 m, toca afinar'),
  TrainingSession(week:11, slot:4, weekday:6, type:SessionType.longRun,   targetKm:19.0, note:'Última larga, confía en el proceso'),
  // W12 carrera
  TrainingSession(week:12, slot:1, weekday:1, type:SessionType.easy,      targetKm:5.0,  note:'Mantén las piernas activas'),
  TrainingSession(week:12, slot:2, weekday:3, type:SessionType.easy,      targetKm:4.0,  note:'Relajado, sin esfuerzo'),
  TrainingSession(week:12, slot:3, weekday:4, type:SessionType.easy,      targetKm:2.0,  note:'Sacudida final'),
  TrainingSession(week:12, slot:4, weekday:6, type:SessionType.race,      targetKm:21.0, note:'12 semanas de trabajo. ¡Es tu momento!'),
];
