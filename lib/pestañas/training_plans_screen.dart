// lib/pestañas/training_plans_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/subscription_service.dart';
import '../services/training_plan_service.dart';
import 'ai_plan_screen.dart';
import 'coin_shop_screen.dart';

// ── Paleta ────────────────────────────────────────────────────────────────────
const _kBg      = Color(0xFF0D0D0E);
const _kSurface = Color(0xFF1C1C1E);
const _kBorder  = Color(0xFF2C2C2E);
const _kDim     = Color(0xFF636366);
const _kSub     = Color(0xFF8E8E93);
const _kWhite   = Color(0xFFEEEEEE);

TextStyle _t(double size, FontWeight w, Color c, {double spacing = 0}) =>
    GoogleFonts.rajdhani(fontSize: size, fontWeight: w, color: c, letterSpacing: spacing);

// ── Pantalla principal ────────────────────────────────────────────────────────
class TrainingPlansScreen extends StatefulWidget {
  const TrainingPlansScreen({super.key});
  @override State<TrainingPlansScreen> createState() => _TrainingPlansScreenState();
}

class _TrainingPlansScreenState extends State<TrainingPlansScreen> {
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kWhite, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('PLANES DE ENTRENAMIENTO',
            style: _t(13, FontWeight.w700, _kWhite, spacing: 2)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: _kBorder),
        ),
      ),
      body: StreamBuilder<UserPlanState?>(
        stream: TrainingPlanService.stream(uid),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(
                color: Color(0xFF636366), strokeWidth: 1.5));
          }
          final state = snap.data;
          if (state == null) return _PlanSelector(uid: uid);
          TrainingPlan? plan = planById(state.planId);
          if (plan == null && state.planId == 'plan_ai' &&
              state.aiPlanData != null) {
            try { plan = buildPlanFromAiData(state.aiPlanData!); } catch (_) {}
          }
          if (plan == null) return _PlanSelector(uid: uid);
          return _ActivePlanView(uid: uid, plan: plan, state: state);
        },
      ),
    );
  }
}

// ── Selector de planes ────────────────────────────────────────────────────────
class _PlanSelector extends StatelessWidget {
  final String uid;
  const _PlanSelector({required this.uid});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        Text('Elige un plan', style: _t(24, FontWeight.w800, _kWhite)),
        const SizedBox(height: 4),
        Text('Comienza hoy y alcanza tu objetivo paso a paso',
            style: _t(13, FontWeight.w400, _kSub)),
        const SizedBox(height: 28),
        ...kAllPlans.map((plan) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _PlanCard(plan: plan, uid: uid),
        )),
        _AiPlanCard(uid: uid),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final TrainingPlan plan;
  final String uid;
  const _PlanCard({required this.plan, required this.uid});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _confirmStart(context),
      child: Container(
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: plan.color.withValues(alpha: 0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header con color
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            decoration: BoxDecoration(
              color: plan.color.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: plan.color.withValues(alpha: 0.15))),
            ),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: plan.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(plan.icon, color: plan.color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(plan.name, style: _t(18, FontWeight.w800, _kWhite)),
                Text(plan.subtitle, style: _t(12, FontWeight.w500, _kSub)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: plan.color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(plan.targetLabel,
                    style: _t(12, FontWeight.w800, Colors.white, spacing: 1)),
              ),
            ]),
          ),
          // Stats
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Row(children: [
              _stat(plan.weeks.toString(), 'semanas'),
              const SizedBox(width: 24),
              _stat(plan.sessionsPerWeek.toString(), 'días/sem'),
              const SizedBox(width: 24),
              _stat(plan.totalSessions.toString(), 'sesiones'),
              const Spacer(),
              Icon(Icons.arrow_forward_ios_rounded, color: plan.color, size: 14),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _stat(String value, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: _t(18, FontWeight.w700, _kWhite)),
      Text(label, style: _t(10, FontWeight.w500, _kDim, spacing: 0.5)),
    ],
  );

  void _confirmStart(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: _kSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: _kDim.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(plan.icon, color: plan.color, size: 36),
            const SizedBox(height: 12),
            Text('Iniciar ${plan.name}', style: _t(20, FontWeight.w800, _kWhite)),
            const SizedBox(height: 6),
            Text('${plan.weeks} semanas · ${plan.totalSessions} sesiones',
                style: _t(13, FontWeight.w400, _kSub)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () async {
                Navigator.pop(ctx);
                await TrainingPlanService.startPlan(uid, plan.id);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: plan.color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(child: Text('EMPEZAR AHORA',
                    style: _t(13, FontWeight.w800, Colors.white, spacing: 2))),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Center(child: Text('Cancelar',
                    style: _t(14, FontWeight.w500, _kSub))),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Tarjeta plan IA ───────────────────────────────────────────────────────────
class _AiPlanCard extends StatelessWidget {
  final String uid;
  const _AiPlanCard({required this.uid});

  static const _kAiColor = Color(0xFF0A84FF);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SubscriptionStatus>(
      stream: SubscriptionService.statusStream,
      initialData: SubscriptionService.currentStatus,
      builder: (ctx, snap) {
        final isPremium = snap.data?.isPremium ?? false;
        return GestureDetector(
          onTap: () {
            if (isPremium) {
              Navigator.push(ctx,
                  MaterialPageRoute(builder: (_) => AIPlanScreen(uid: uid)));
            } else {
              CoinShopScreen.mostrar(ctx);
            }
          },
          child: Container(
            margin: const EdgeInsets.only(top: 0),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isPremium
                    ? _kAiColor.withValues(alpha: 0.3)
                    : _kBorder,
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                decoration: BoxDecoration(
                  color: _kAiColor.withValues(alpha: 0.06),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(15)),
                  border: Border(
                    bottom: BorderSide(
                        color: _kAiColor.withValues(alpha: 0.12))),
                ),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: _kAiColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome_rounded,
                        color: _kAiColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Plan Personalizado IA',
                          style: _t(18, FontWeight.w800, _kWhite)),
                      Text('Diseñado para tus objetivos',
                          style: _t(12, FontWeight.w500, _kSub)),
                    ],
                  )),
                  if (!isPremium)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFCC00).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFFFFCC00)
                                .withValues(alpha: 0.4)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.lock_rounded,
                            color: Color(0xFFFFCC00), size: 11),
                        const SizedBox(width: 4),
                        Text('PREMIUM',
                            style: _t(10, FontWeight.w800,
                                const Color(0xFFFFCC00), spacing: 0.5)),
                      ]),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _kAiColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('IA',
                          style: _t(12, FontWeight.w800, Colors.white,
                              spacing: 1)),
                    ),
                ]),
              ),
              // Descripción
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: Row(children: [
                  _aiStat(Icons.psychology_rounded, 'Personalizado'),
                  const SizedBox(width: 20),
                  _aiStat(Icons.tune_rounded, 'Adaptativo'),
                  const SizedBox(width: 20),
                  _aiStat(Icons.chat_bubble_outline_rounded, 'Chat IA'),
                  const Spacer(),
                  Icon(
                    isPremium
                        ? Icons.arrow_forward_ios_rounded
                        : Icons.lock_outline_rounded,
                    color: isPremium ? _kAiColor : _kDim,
                    size: 14,
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _aiStat(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: _kDim, size: 13),
      const SizedBox(width: 4),
      Text(label, style: _t(11, FontWeight.w500, _kSub)),
    ],
  );
}

// ── Vista plan activo ─────────────────────────────────────────────────────────
class _ActivePlanView extends StatelessWidget {
  final String uid;
  final TrainingPlan plan;
  final UserPlanState state;
  const _ActivePlanView({required this.uid, required this.plan, required this.state});

  @override
  Widget build(BuildContext context) {
    final week = state.currentWeek.clamp(1, plan.weeks);
    final progress = state.progressIn(plan);
    final sessions = plan.week(week);
    final todaySlot = _todaySession(sessions);
    final completed = state.completedSessions.length;
    final total = plan.totalSessions;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        // ── Header plan activo
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: plan.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: plan.color.withValues(alpha: 0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(plan.icon, color: plan.color, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(plan.name,
                  style: _t(18, FontWeight.w800, _kWhite))),
              _weekBadge(week, plan.weeks, plan.color),
            ]),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: _kBorder,
                valueColor: AlwaysStoppedAnimation(plan.color),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('$completed de $total sesiones completadas',
                  style: _t(11, FontWeight.w500, _kSub)),
              Text('${(progress * 100).round()}%',
                  style: _t(11, FontWeight.w700, plan.color)),
            ]),
          ]),
        ),

        const SizedBox(height: 24),

        // ── Sesión de hoy (si aplica)
        if (todaySlot != null) ...[
          _TodayCard(uid: uid, session: todaySlot, state: state),
          const SizedBox(height: 24),
        ],

        // ── Semanas colapsables
        Text('SEMANA $week DE ${plan.weeks}',
            style: _t(11, FontWeight.w700, _kDim, spacing: 2)),
        const SizedBox(height: 12),
        ...sessions.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SessionTile(uid: uid, session: s, state: state),
        )),

        const SizedBox(height: 24),
        _WeeksGrid(plan: plan, state: state, currentWeek: week),

        const SizedBox(height: 32),

        // ── Abandonar plan
        GestureDetector(
          onTap: () => _confirmAbandon(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text('Abandonar plan',
                style: _t(13, FontWeight.w600, Colors.redAccent.shade200))),
          ),
        ),
      ],
    );
  }

  Widget _weekBadge(int week, int total, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text('SEM $week / $total',
        style: _t(11, FontWeight.w700, color, spacing: 0.5)),
  );

  TrainingSession? _todaySession(List<TrainingSession> sessions) {
    final todayWd = DateTime.now().weekday; // 1=Mon..7=Sun
    for (final s in sessions) {
      if (s.weekday == todayWd && s.type.isRun) return s;
    }
    return null;
  }

  void _confirmAbandon(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Abandonar plan', style: _t(16, FontWeight.w700, _kWhite)),
        content: Text('Perderás tu progreso actual. ¿Seguro?',
            style: _t(13, FontWeight.w400, _kSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: _t(13, FontWeight.w500, _kSub)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await TrainingPlanService.abandonPlan(uid);
            },
            child: Text('Abandonar',
                style: _t(13, FontWeight.w700, Colors.redAccent.shade200)),
          ),
        ],
      ),
    );
  }
}

// ── Tarjeta sesión de hoy ─────────────────────────────────────────────────────
class _TodayCard extends StatelessWidget {
  final String uid;
  final TrainingSession session;
  final UserPlanState state;
  const _TodayCard({required this.uid, required this.session, required this.state});

  @override
  Widget build(BuildContext context) {
    final done = state.isCompleted(session.key);
    final color = session.type.color;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.wb_sunny_rounded, color: color, size: 14),
          const SizedBox(width: 7),
          Text('SESIÓN DE HOY', style: _t(10, FontWeight.w700, color, spacing: 2)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(session.type.icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(session.type.label, style: _t(16, FontWeight.w700, _kWhite)),
            Text('${session.targetKm.toStringAsFixed(1)} km · ${session.note}',
                style: _t(11, FontWeight.w400, _kSub)),
          ])),
        ]),
        const SizedBox(height: 16),
        if (!done)
          GestureDetector(
            onTap: () async {
              HapticFeedback.mediumImpact();
              await TrainingPlanService.markSession(uid, session.key, true);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Text('MARCAR COMO COMPLETADA',
                  style: _t(12, FontWeight.w800, Colors.white, spacing: 1.5))),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF34C759).withValues(alpha: 0.4)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF34C759), size: 16),
              const SizedBox(width: 8),
              Text('COMPLETADA', style: _t(12, FontWeight.w700,
                  const Color(0xFF34C759), spacing: 1.5)),
            ]),
          ),
      ]),
    );
  }
}

// ── Tile de sesión ────────────────────────────────────────────────────────────
class _SessionTile extends StatelessWidget {
  final String uid;
  final TrainingSession session;
  final UserPlanState state;
  const _SessionTile({required this.uid, required this.session, required this.state});

  @override
  Widget build(BuildContext context) {
    final done  = state.isCompleted(session.key);
    final color = session.type.color;

    return GestureDetector(
      onTap: () async {
        if (!session.type.isRun) return;
        HapticFeedback.selectionClick();
        await TrainingPlanService.markSession(uid, session.key, !done);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: done ? const Color(0xFF34C759).withValues(alpha: 0.3) : _kBorder,
          ),
        ),
        child: Row(children: [
          // Tipo chip
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: done ? 0.06 : 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              done ? Icons.check_rounded : session.type.icon,
              color: done ? const Color(0xFF34C759) : color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(session.type.label,
                style: _t(14, FontWeight.w700,
                    done ? _kDim : _kWhite)),
            Text(session.type.isRun
                ? '${session.targetKm.toStringAsFixed(1)} km · ${session.note}'
                : session.note,
                style: _t(10, FontWeight.w400, _kDim),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          if (session.type.isRun)
            Icon(
              done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: done ? const Color(0xFF34C759) : _kDim,
              size: 20,
            ),
        ]),
      ),
    );
  }
}

// ── Grid resumen de semanas ───────────────────────────────────────────────────
class _WeeksGrid extends StatelessWidget {
  final TrainingPlan plan;
  final UserPlanState state;
  final int currentWeek;
  const _WeeksGrid({required this.plan, required this.state, required this.currentWeek});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('PROGRESO SEMANAL',
          style: _t(11, FontWeight.w700, _kDim, spacing: 2)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: List.generate(plan.weeks, (i) {
        final w = i + 1;
        final sessions = plan.week(w);
        final total = sessions.where((s) => s.type.isRun).length;
        final done = sessions.where((s) => state.isCompleted(s.key)).length;
        final isCurrent = w == currentWeek;
        final isPast = w < currentWeek;

        Color border;
        Color bg;
        Color textColor;

        if (isCurrent) {
          border = plan.color;
          bg = plan.color.withValues(alpha: 0.1);
          textColor = plan.color;
        } else if (isPast && done == total) {
          border = const Color(0xFF34C759).withValues(alpha: 0.5);
          bg = const Color(0xFF34C759).withValues(alpha: 0.08);
          textColor = const Color(0xFF34C759);
        } else {
          border = _kBorder;
          bg = _kSurface;
          textColor = _kDim;
        }

        return Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Column(children: [
            Text('S$w', style: _t(12, FontWeight.w700, textColor)),
            const SizedBox(height: 3),
            Text('$done/$total', style: _t(9, FontWeight.w500, textColor)),
          ]),
        );
      })),
    ]);
  }
}
