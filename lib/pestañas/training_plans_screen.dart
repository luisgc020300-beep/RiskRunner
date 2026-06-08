// lib/pestañas/training_plans_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/env.dart';
import '../services/subscription_service.dart';
import '../services/training_plan_service.dart';
import 'ai_plan_screen.dart';
import 'coin_shop_screen.dart';

// ── Paleta dinámica (light / dark) ────────────────────────────────────────────
class _Pal {
  final Color bg, surface, border, dim, sub, text;
  const _Pal({
    required this.bg, required this.surface, required this.border,
    required this.dim, required this.sub, required this.text,
  });

  factory _Pal.of(BuildContext ctx) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return dark ? const _Pal(
      bg:      Color(0xFF0D0D0E),
      surface: Color(0xFF1C1C1E),
      border:  Color(0xFF2C2C2E),
      dim:     Color(0xFF636366),
      sub:     Color(0xFF8E8E93),
      text:    Color(0xFFEEEEEE),
    ) : const _Pal(
      bg:      Color(0xFFF2F2F7),
      surface: Color(0xFFFFFFFF),
      border:  Color(0xFFD1D1D6),
      dim:     Color(0xFF8E8E93),
      sub:     Color(0xFF636366),
      text:    Color(0xFF1C1C1E),
    );
  }
}

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
    final pal = _Pal.of(context);
    if (uid == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: pal.text, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('PLANES DE ENTRENAMIENTO',
            style: _t(13, FontWeight.w700, pal.text, spacing: 2)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: pal.border),
        ),
      ),
      body: StreamBuilder<UserPlanState?>(
        stream: TrainingPlanService.stream(uid),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(
                color: pal.dim, strokeWidth: 1.5));
          }
          final state = snap.data;
          if (state == null) return _PlanSelector(uid: uid, pal: pal);
          TrainingPlan? plan = planById(state.planId);
          if (plan == null && state.planId == 'plan_ai' &&
              state.aiPlanData != null) {
            try { plan = buildPlanFromAiData(state.aiPlanData!); } catch (_) {}
          }
          if (plan == null) return _PlanSelector(uid: uid, pal: pal);
          return _ActivePlanView(uid: uid, plan: plan, state: state, pal: pal);
        },
      ),
    );
  }
}

// ── Selector de planes ────────────────────────────────────────────────────────
class _PlanSelector extends StatelessWidget {
  final String uid;
  final _Pal pal;
  const _PlanSelector({required this.uid, required this.pal});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        Text('Elige un plan', style: _t(24, FontWeight.w800, pal.text)),
        const SizedBox(height: 4),
        Text('Comienza hoy y alcanza tu objetivo paso a paso',
            style: _t(13, FontWeight.w400, pal.sub)),
        const SizedBox(height: 28),
        ...kAllPlans.map((plan) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _PlanCard(plan: plan, uid: uid, pal: pal),
        )),
        _AiPlanCard(uid: uid, pal: pal),
        _PlanHistorySection(uid: uid, pal: pal),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final TrainingPlan plan;
  final String uid;
  final _Pal pal;
  const _PlanCard({required this.plan, required this.uid, required this.pal});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _confirmStart(context),
      child: Container(
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: plan.color.withValues(alpha: 0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                Text(plan.name, style: _t(18, FontWeight.w800, pal.text)),
                Text(plan.subtitle, style: _t(12, FontWeight.w500, pal.sub)),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Row(children: [
              _stat('${plan.weeks}', 'semanas'),
              const SizedBox(width: 24),
              _stat('${plan.sessionsPerWeek}', 'días/sem'),
              const SizedBox(width: 24),
              _stat('${plan.totalSessions}', 'sesiones'),
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
      Text(value, style: _t(18, FontWeight.w700, pal.text)),
      Text(label, style: _t(10, FontWeight.w500, pal.dim, spacing: 0.5)),
    ],
  );

  void _confirmStart(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: pal.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        var loading = false;
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: pal.dim.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Icon(plan.icon, color: plan.color, size: 36),
                  const SizedBox(height: 12),
                  Text('Iniciar ${plan.name}', style: _t(20, FontWeight.w800, pal.text)),
                  const SizedBox(height: 6),
                  Text('${plan.weeks} semanas · ${plan.totalSessions} sesiones',
                      style: _t(13, FontWeight.w400, pal.sub)),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: loading ? null : () async {
                      setModal(() => loading = true);
                      try {
                        await TrainingPlanService.startPlan(uid, plan.id);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setModal(() => loading = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text('Error al iniciar el plan: $e'),
                            backgroundColor: Colors.redAccent,
                          ));
                        }
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: loading
                            ? plan.color.withValues(alpha: 0.5)
                            : plan.color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: loading
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : Text('EMPEZAR AHORA',
                                style: _t(13, FontWeight.w800, Colors.white, spacing: 2)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: loading ? null : () => Navigator.pop(ctx),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Center(child: Text('Cancelar',
                          style: _t(14, FontWeight.w500, pal.sub))),
                    ),
                  ),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Tarjeta plan IA ───────────────────────────────────────────────────────────
class _AiPlanCard extends StatelessWidget {
  final String uid;
  final _Pal pal;
  const _AiPlanCard({required this.uid, required this.pal});

  static const _kAiColor = Color(0xFF0A84FF);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SubscriptionStatus>(
      stream: SubscriptionService.statusStream,
      initialData: SubscriptionService.currentStatus,
      builder: (ctx, snap) {
        final isPremium = (snap.data?.isPremium ?? false) || Env.isDebug;
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
            decoration: BoxDecoration(
              color: pal.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isPremium
                    ? _kAiColor.withValues(alpha: 0.3)
                    : pal.border,
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                decoration: BoxDecoration(
                  color: _kAiColor.withValues(alpha: 0.06),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                  border: Border(bottom: BorderSide(
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
                          style: _t(18, FontWeight.w800, pal.text)),
                      Text('Diseñado para tus objetivos',
                          style: _t(12, FontWeight.w500, pal.sub)),
                    ],
                  )),
                  if (!isPremium)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFCC00).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFFFFCC00).withValues(alpha: 0.4)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _kAiColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('IA',
                          style: _t(12, FontWeight.w800, Colors.white, spacing: 1)),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: Row(children: [
                  _aiStat(Icons.psychology_rounded, 'Personalizado', pal),
                  const SizedBox(width: 20),
                  _aiStat(Icons.tune_rounded, 'Adaptativo', pal),
                  const SizedBox(width: 20),
                  _aiStat(Icons.chat_bubble_outline_rounded, 'Chat IA', pal),
                  const Spacer(),
                  Icon(
                    isPremium
                        ? Icons.arrow_forward_ios_rounded
                        : Icons.lock_outline_rounded,
                    color: isPremium ? _kAiColor : pal.dim,
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

  Widget _aiStat(IconData icon, String label, _Pal pal) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: pal.dim, size: 13),
      const SizedBox(width: 4),
      Text(label, style: _t(11, FontWeight.w500, pal.sub)),
    ],
  );
}

// ── Vista plan activo ─────────────────────────────────────────────────────────
class _ActivePlanView extends StatelessWidget {
  final String uid;
  final TrainingPlan plan;
  final UserPlanState state;
  final _Pal pal;
  const _ActivePlanView({
    required this.uid, required this.plan,
    required this.state, required this.pal,
  });

  @override
  Widget build(BuildContext context) {
    final week     = state.currentWeek.clamp(1, plan.weeks);
    final progress = state.progressIn(plan);
    final sessions = plan.week(week);
    final todaySlot = _todaySession(sessions);
    final completed = state.completedSessions.length;
    final total     = plan.totalSessions;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
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
                  style: _t(18, FontWeight.w800, pal.text))),
              _weekBadge(week, plan.weeks, plan.color, pal),
            ]),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: pal.border,
                valueColor: AlwaysStoppedAnimation(plan.color),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('$completed de $total sesiones completadas',
                  style: _t(11, FontWeight.w500, pal.sub)),
              Text('${(progress * 100).round()}%',
                  style: _t(11, FontWeight.w700, plan.color)),
            ]),
          ]),
        ),

        const SizedBox(height: 24),

        if (todaySlot != null) ...[
          _TodayCard(uid: uid, session: todaySlot, state: state, pal: pal),
          const SizedBox(height: 24),
        ],

        Text('SEMANA $week DE ${plan.weeks}',
            style: _t(11, FontWeight.w700, pal.dim, spacing: 2)),
        const SizedBox(height: 12),
        ...sessions.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SessionTile(uid: uid, session: s, state: state, pal: pal),
        )),

        const SizedBox(height: 24),
        _WeeksGrid(plan: plan, state: state, currentWeek: week, pal: pal),

        if (progress >= 1.0) ...[
          const SizedBox(height: 24),
          _buildCompletionCard(context),
        ],

        const SizedBox(height: 32),

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

  Widget _weekBadge(int week, int total, Color color, _Pal pal) => Container(
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
    final todayWd = DateTime.now().weekday;
    for (final s in sessions) {
      if (s.weekday == todayWd && s.type.isRun) return s;
    }
    return null;
  }

  void _confirmAbandon(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: pal.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Abandonar plan', style: _t(16, FontWeight.w700, pal.text)),
        content: Text('Perderás tu progreso actual. ¿Seguro?',
            style: _t(13, FontWeight.w400, pal.sub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: _t(13, FontWeight.w500, pal.sub)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await TrainingPlanService.abandonPlan(
                  uid, state: state, plan: plan);
            },
            child: Text('Abandonar',
                style: _t(13, FontWeight.w700, Colors.redAccent.shade200)),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionCard(BuildContext context) {
    const green = Color(0xFF34C759);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: green.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.emoji_events_rounded, color: green, size: 14),
          const SizedBox(width: 7),
          Text('PLAN COMPLETADO',
              style: _t(10, FontWeight.w700, green, spacing: 2)),
        ]),
        const SizedBox(height: 10),
        Text(
          '¡Has completado todas las sesiones! Guarda tu logro en el historial.',
          style: _t(13, FontWeight.w500, pal.text),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => _finalizarPlan(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: green,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text('FINALIZAR Y GUARDAR',
                  style: _t(12, FontWeight.w800, Colors.white, spacing: 1.5)),
            ),
          ),
        ),
      ]),
    );
  }

  void _finalizarPlan(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: pal.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Finalizar plan', style: _t(16, FontWeight.w700, pal.text)),
        content: Text(
          'Se guardará en tu historial de planes completados.',
          style: _t(13, FontWeight.w400, pal.sub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: _t(13, FontWeight.w500, pal.sub)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await TrainingPlanService.completePlan(uid, state, plan);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Error al finalizar: $e'),
                    backgroundColor: Colors.redAccent,
                  ));
                }
              }
            },
            child: Text('Finalizar',
                style: _t(13, FontWeight.w700, const Color(0xFF34C759))),
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
  final _Pal pal;
  const _TodayCard({
    required this.uid, required this.session,
    required this.state, required this.pal,
  });

  @override
  Widget build(BuildContext context) {
    final done  = state.isCompleted(session.key);
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
            Text(session.type.label, style: _t(16, FontWeight.w700, pal.text)),
            Text('${session.targetKm.toStringAsFixed(1)} km · ${session.note}',
                style: _t(11, FontWeight.w400, pal.sub)),
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
              color: pal.surface,
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
  final _Pal pal;
  const _SessionTile({
    required this.uid, required this.session,
    required this.state, required this.pal,
  });

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
          color: pal.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: done
                ? const Color(0xFF34C759).withValues(alpha: 0.3)
                : pal.border,
          ),
        ),
        child: Row(children: [
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
                style: _t(14, FontWeight.w700, done ? pal.dim : pal.text)),
            Text(session.type.isRun
                ? '${session.targetKm.toStringAsFixed(1)} km · ${session.note}'
                : session.note,
                style: _t(10, FontWeight.w400, pal.dim),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          if (session.type.isRun)
            Icon(
              done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: done ? const Color(0xFF34C759) : pal.dim,
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
  final _Pal pal;
  const _WeeksGrid({
    required this.plan, required this.state,
    required this.currentWeek, required this.pal,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('PROGRESO SEMANAL', style: _t(11, FontWeight.w700, pal.dim, spacing: 2)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: List.generate(plan.weeks, (i) {
        final w        = i + 1;
        final sessions = plan.week(w);
        final total    = sessions.where((s) => s.type.isRun).length;
        final done     = sessions.where((s) => state.isCompleted(s.key)).length;
        final isCurrent = w == currentWeek;
        final isPast    = w < currentWeek;

        Color border, bg, textColor;
        if (isCurrent) {
          border    = plan.color;
          bg        = plan.color.withValues(alpha: 0.1);
          textColor = plan.color;
        } else if (isPast && done == total) {
          border    = const Color(0xFF34C759).withValues(alpha: 0.5);
          bg        = const Color(0xFF34C759).withValues(alpha: 0.08);
          textColor = const Color(0xFF34C759);
        } else {
          border    = pal.border;
          bg        = pal.surface;
          textColor = pal.dim;
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

// ── Historial de planes completados (selector) ────────────────────────────────
class _PlanHistorySection extends StatelessWidget {
  final String uid;
  final _Pal pal;
  const _PlanHistorySection({required this.uid, required this.pal});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CompletedPlanRecord>>(
      future: TrainingPlanService.loadHistory(uid),
      builder: (ctx, snap) {
        final records = snap.data ?? [];
        if (records.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            Row(children: [
              Container(
                width: 3, height: 14,
                decoration: BoxDecoration(
                  color: pal.dim,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text('HISTORIAL DE PLANES',
                  style: _t(11, FontWeight.w700, pal.dim, spacing: 2)),
            ]),
            const SizedBox(height: 12),
            ...records.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CompletedPlanTile(record: r, pal: pal),
            )),
          ],
        );
      },
    );
  }
}

class _CompletedPlanTile extends StatelessWidget {
  final CompletedPlanRecord record;
  final _Pal pal;
  const _CompletedPlanTile({required this.record, required this.pal});

  Color get _color {
    final plan = planById(record.planId);
    return plan?.color ?? const Color(0xFF0A84FF);
  }

  IconData get _icon {
    final plan = planById(record.planId);
    return plan?.icon ?? Icons.auto_awesome_rounded;
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year % 100}';

  @override
  Widget build(BuildContext context) {
    final color       = _color;
    final isCompleted = !record.abandoned;
    final statusColor = isCompleted ? const Color(0xFF34C759) : pal.dim;
    final rate        = (record.completionRate * 100).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted
              ? const Color(0xFF34C759).withValues(alpha: 0.2)
              : pal.border,
        ),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(_icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(record.planName,
                style: _t(14, FontWeight.w700, pal.text)),
            const SizedBox(height: 2),
            Text('${_fmt(record.startDate)} → ${_fmt(record.endDate)}',
                style: _t(10, FontWeight.w400, pal.dim)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: record.completionRate,
                    minHeight: 3,
                    backgroundColor: pal.border,
                    valueColor: AlwaysStoppedAnimation(statusColor),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('$rate%',
                  style: _t(10, FontWeight.w700, statusColor)),
            ]),
          ],
        )),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: statusColor.withValues(alpha: 0.25)),
          ),
          child: Text(
            isCompleted ? 'Completado' : 'Abandonado',
            style: _t(9, FontWeight.w700, statusColor, spacing: 0.3),
          ),
        ),
      ]),
    );
  }
}
