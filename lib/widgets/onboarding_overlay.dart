import 'package:RiskRunner/services/onboarding_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =============================================================================
// PALETA
// =============================================================================
const _kBg      = Color(0xFF060608);
const _kSurface = Color(0xFF0D0D11);
const _kBorder  = Color(0xFF1E1E26);
const _kDim     = Color(0xFF666680);
const _kAccent  = Color(0xFFFF7B1A);

// =============================================================================
// MODELO DE TOOLTIP
// =============================================================================
class OnboardingTooltipData {
  final String id;
  final String tag;
  final String title;
  final String body;
  final String emoji;
  final Color color;
  final TooltipPosition position;

  const OnboardingTooltipData({
    required this.id,
    required this.tag,
    required this.title,
    required this.body,
    required this.emoji,
    required this.color,
    this.position = TooltipPosition.bottom,
  });
}

enum TooltipPosition { top, bottom, center }

// =============================================================================
// CATÁLOGO COMPLETO DE TOOLTIPS
// =============================================================================
class OnboardingTooltips {
  static const Map<String, OnboardingTooltipData> catalogo = {

    // ── RUN 0 (slides) ────────────────────────────────────────────
    'bienvenida': OnboardingTooltipData(
      id: 'bienvenida', tag: 'BIENVENIDO',
      title: 'Tu primera misión', emoji: '',
      body: 'Pulsa INICIAR CARRERA y sal a correr. Tu ruta se convertirá en territorio tuyo en el mapa.',
      color: _kAccent,
    ),

    // ── RUN 1 ─────────────────────────────────────────────────────
    'conquista_territorio': OnboardingTooltipData(
      id: 'conquista_territorio', tag: 'MECÁNICA BÁSICA',
      title: '¡Territorio conquistado!', emoji: '',
      body: 'Cada ruta que completas queda marcada en el mapa con tu color. Cuanto más largo el recorrido, más zona controlas.',
      color: _kAccent,
    ),
    'mapa_live': OnboardingTooltipData(
      id: 'mapa_live', tag: 'MAPA EN VIVO',
      title: 'Tu zona se actualiza', emoji: '',
      body: 'El mapa se actualiza en tiempo real mientras corres. Puedes ver tu territorio formándose kilómetro a kilómetro.',
      color: Color(0xFF3B82F6),
      position: TooltipPosition.top,
    ),
    'color_hint': OnboardingTooltipData(
      id: 'color_hint', tag: 'PERSONALIZACIÓN',
      title: 'Tu color de territorio', emoji: '',
      body: 'En el resumen puedes cambiar el color de todas tus zonas. Elige el que más te represente.',
      color: Color(0xFF8B5CF6),
    ),
    'pausa_retirada': OnboardingTooltipData(
      id: 'pausa_retirada', tag: 'CONTROLES',
      title: 'Pausa y retirada', emoji: '',
      body: 'Pausa cuando necesites descansar. Si te retiras, la ruta hasta ese punto queda guardada igualmente.',
      color: _kDim,
      position: TooltipPosition.top,
    ),

    // ── RUN 2 ─────────────────────────────────────────────────────
    'deterioro_zonas': OnboardingTooltipData(
      id: 'deterioro_zonas', tag: 'DETERIORO',
      title: 'Tus zonas se desvanecen', emoji: '',
      body: 'Si no vuelves a correr por un territorio en 5 días, empieza a perder intensidad. A los 10 días cualquiera puede invadirlo.',
      color: Color(0xFFEAB308),
    ),
    'refuerzo_territorio': OnboardingTooltipData(
      id: 'refuerzo_territorio', tag: 'ESTRATEGIA',
      title: 'Refuerza lo que es tuyo', emoji: '',
      body: 'Volver a correr por una zona tuya la refuerza al 100%. Planifica tus rutas para mantener el control del mapa.',
      color: Color(0xFF22C55E),
      position: TooltipPosition.top,
    ),
    'frecuencia_importa': OnboardingTooltipData(
      id: 'frecuencia_importa', tag: 'CONSEJO',
      title: 'La constancia manda', emoji: '',
      body: 'Correr todos los días, aunque sea poco, es mejor que una carrera larga de vez en cuando. Tu racha también suma puntos.',
      color: _kAccent,
    ),

    // ── RUN 3 ─────────────────────────────────────────────────────
    'otros_jugadores': OnboardingTooltipData(
      id: 'otros_jugadores', tag: 'MULTIJUGADOR',
      title: 'No estás solo', emoji: '',
      body: 'Otros runners compiten por el mismo mapa. Ves sus zonas en otros colores. La ciudad es un campo de batalla.',
      color: Color(0xFFEF4444),
    ),
    'zona_rival': OnboardingTooltipData(
      id: 'zona_rival', tag: 'TERRITORIO RIVAL',
      title: 'Zonas en otros colores', emoji: '',
      body: 'Las zonas de colores distintos al tuyo pertenecen a otros jugadores. Si están deterioradas, puedes invadirlas corriendo por ellas.',
      color: Color(0xFFEF4444),
      position: TooltipPosition.top,
    ),
    'mapa_global': OnboardingTooltipData(
      id: 'mapa_global', tag: 'VISIÓN GLOBAL',
      title: 'El mapa completo', emoji: '',
      body: 'Desde el mapa principal puedes ver toda la ciudad y cómo está repartido el control entre todos los jugadores.',
      color: Color(0xFF06B6D4),
    ),

    // ── RUN 4 ─────────────────────────────────────────────────────
    'invasion_posible': OnboardingTooltipData(
      id: 'invasion_posible', tag: 'INVASIÓN',
      title: '¡Puedes invadir!', emoji: '',
      body: 'Si corres por una zona rival deteriorada, la conquistas. El rival pierde puntos y tú ganas el doble.',
      color: Color(0xFFEF4444),
    ),
    'rival_notificado': OnboardingTooltipData(
      id: 'rival_notificado', tag: 'NOTIFICACIONES',
      title: 'El rival lo sabe', emoji: '',
      body: 'Cuando invades una zona, el dueño recibe una notificación. Puede volver a reclamarla corriendo de nuevo.',
      color: Color(0xFFEC4899),
      position: TooltipPosition.top,
    ),
    'defiende_tu_zona': OnboardingTooltipData(
      id: 'defiende_tu_zona', tag: 'DEFENSA',
      title: 'Defiende tu territorio', emoji: '',
      body: 'Si alguien invade una de tus zonas, recibe una notificación. Vuelve a correr por ella para recuperarla.',
      color: Color(0xFFEAB308),
    ),

    // ── RUN 5 ─────────────────────────────────────────────────────
    'ligas_intro': OnboardingTooltipData(
      id: 'ligas_intro', tag: 'LIGAS',
      title: 'Sistema de ligas', emoji: '',
      body: 'Cada acción suma puntos de liga. Conquistas, invasiones y racha diaria te suben en el ranking.',
      color: Color(0xFFEAB308),
    ),
    'puntos_liga': OnboardingTooltipData(
      id: 'puntos_liga', tag: 'PUNTUACIÓN',
      title: 'Cómo sumar puntos', emoji: '',
      body: '+15 pts por zona nueva · +25 pts por invasión · -10 pts si te invaden · +5 pts por racha diaria.',
      color: _kAccent,
      position: TooltipPosition.top,
    ),
    'ranking_semanal': OnboardingTooltipData(
      id: 'ranking_semanal', tag: 'COMPETICIÓN',
      title: 'El ranking es semanal', emoji: '',
      body: 'Los puntos se resetean cada semana. Todos empiezan desde cero. La batalla se reinicia cada lunes.',
      color: Color(0xFF22C55E),
    ),

    // ── RETOS — nuevos ────────────────────────────────────────────
    //
    // 'retos_intro':      se muestra la primera vez que el usuario
    //                     abre la tab de Retos en home_screen.
    //
    // 'reto_completado':  se muestra en resumen_screen cuando el
    //                     usuario completa un reto por primera vez.
    //
    'retos_intro': OnboardingTooltipData(
      id: 'retos_intro', tag: 'MISIONES',
      title: 'Retos diarios', emoji: '',
      body: 'Cada día tienes misiones nuevas. Confirma un reto, sal a correr y el narrador te guiará en tiempo real hasta completarlo. Los puntos se suman solos al terminar.',
      color: _kAccent,
      position: TooltipPosition.center,
    ),
    'reto_completado': OnboardingTooltipData(
      id: 'reto_completado', tag: '¡PRIMERA MISIÓN!',
      title: 'Reto completado', emoji: '',
      body: 'Los puntos ya están en tu cuenta. Puedes seguir corriendo después de completar un reto — la carrera no para hasta que tú quieras.',
      color: Color(0xFFD4A84C),
      position: TooltipPosition.top,
    ),
  };

  static List<OnboardingTooltipData> getPendientes(OnboardingState state) {
    return state.tooltipsPendientes
        .map((id) => catalogo[id])
        .whereType<OnboardingTooltipData>()
        .toList();
  }
}

// =============================================================================
// WIDGET PRINCIPAL
// =============================================================================
class OnboardingOverlayWrapper extends StatefulWidget {
  final Widget child;
  final OnboardingState onboardingState;
  final List<String> tooltipIds;

  const OnboardingOverlayWrapper({
    super.key,
    required this.child,
    required this.onboardingState,
    required this.tooltipIds,
  });

  @override
  State<OnboardingOverlayWrapper> createState() =>
      _OnboardingOverlayWrapperState();
}

class _OnboardingOverlayWrapperState extends State<OnboardingOverlayWrapper>
    with SingleTickerProviderStateMixin {

  late List<OnboardingTooltipData> _pending;
  int _currentIdx = 0;
  bool _visible = false;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();

    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack));

    _pending = widget.tooltipIds
        .where((id) => !widget.onboardingState.tooltipsVistos.contains(id))
        .map((id) => OnboardingTooltips.catalogo[id])
        .whereType<OnboardingTooltipData>()
        .toList();

    if (_pending.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() => _visible = true);
          _animCtrl.forward();
          HapticFeedback.lightImpact();
        }
      });
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _siguiente() async {
    HapticFeedback.selectionClick();
    await OnboardingService.marcarTooltipVisto(_pending[_currentIdx].id);

    if (_currentIdx < _pending.length - 1) {
      await _animCtrl.reverse();
      setState(() => _currentIdx++);
      _animCtrl.forward();
      HapticFeedback.lightImpact();
    } else {
      await _animCtrl.reverse();
      setState(() => _visible = false);
    }
  }

  Future<void> _saltarTodos() async {
    HapticFeedback.lightImpact();
    final ids = _pending.map((t) => t.id).toList();
    await OnboardingService.marcarTooltipsVistos(ids);
    await _animCtrl.reverse();
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      if (_visible && _pending.isNotEmpty)
        _buildOverlay(_pending[_currentIdx]),
    ]);
  }

  Widget _buildOverlay(OnboardingTooltipData tooltip) {
    return GestureDetector(
      onTap: _saltarTodos,
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _animCtrl,
            builder: (_, __) => Opacity(
              opacity: _fadeAnim.value,
              child: Transform.scale(
                scale: _scaleAnim.value,
                child: _posicionado(tooltip),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _posicionado(OnboardingTooltipData tooltip) {
    final card = GestureDetector(
      onTap: () {},
      child: _TooltipCard(
        tooltip: tooltip,
        current: _currentIdx + 1,
        total: _pending.length,
        onNext: _siguiente,
        onSkip: _pending.length > 1 ? _saltarTodos : null,
      ),
    );

    switch (tooltip.position) {
      case TooltipPosition.top:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 0), child: card),
          const Spacer(),
        ]);
      case TooltipPosition.center:
        return Center(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20), child: card));
      case TooltipPosition.bottom:
      default:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Spacer(),
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: card),
        ]);
    }
  }
}

// =============================================================================
// TARJETA DE TOOLTIP
// =============================================================================
class _TooltipCard extends StatelessWidget {
  final OnboardingTooltipData tooltip;
  final int current;
  final int total;
  final VoidCallback onNext;
  final VoidCallback? onSkip;

  const _TooltipCard({
    required this.tooltip,
    required this.current,
    required this.total,
    required this.onNext,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tooltip.color.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 40),
          BoxShadow(color: tooltip.color.withValues(alpha: 0.12), blurRadius: 30),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, children: [

        Row(children: [
          Container(width: 48, height: 48,
            decoration: BoxDecoration(
              color: tooltip.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tooltip.color.withValues(alpha: 0.2)),
            ),
            child: Center(child: Text(tooltip.emoji,
                style: const TextStyle(fontSize: 22)))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(tooltip.tag, style: TextStyle(
                color: tooltip.color, fontSize: 9,
                fontWeight: FontWeight.w900, letterSpacing: 2.5,
                decoration: TextDecoration.none)),
            const SizedBox(height: 4),
            Text(tooltip.title, style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800,
                decoration: TextDecoration.none)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: tooltip.color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: tooltip.color.withValues(alpha: 0.15)),
            ),
            child: Text('$current/$total', style: TextStyle(
                color: tooltip.color, fontSize: 10, fontWeight: FontWeight.w900,
                decoration: TextDecoration.none)),
          ),
        ]),

        const SizedBox(height: 16),

        ClipRRect(borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: current / total,
            backgroundColor: _kBorder,
            valueColor: AlwaysStoppedAnimation(tooltip.color),
            minHeight: 2,
          )),

        const SizedBox(height: 16),

        Text(tooltip.body, style: const TextStyle(
            color: _kDim, fontSize: 14, height: 1.55,
            decoration: TextDecoration.none)),

        const SizedBox(height: 20),

        Row(children: [
          if (onSkip != null && total > 1) ...[
            GestureDetector(
              onTap: onSkip,
              child: Text('SALTAR TODO', style: TextStyle(
                  color: _kDim, fontSize: 9,
                  fontWeight: FontWeight.w800, letterSpacing: 2,
                  decoration: TextDecoration.none)),
            ),
            const Spacer(),
          ] else const Spacer(),
          GestureDetector(
            onTap: onNext,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              decoration: BoxDecoration(
                color: tooltip.color,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(
                    color: tooltip.color.withValues(alpha: 0.35),
                    blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  current == total ? 'ENTENDIDO' : 'SIGUIENTE',
                  style: const TextStyle(color: Colors.black, fontSize: 11,
                      fontWeight: FontWeight.w900, letterSpacing: 2,
                      decoration: TextDecoration.none),
                ),
                const SizedBox(width: 6),
                Icon(current == total
                    ? Icons.check_rounded : Icons.arrow_forward_rounded,
                    color: Colors.black, size: 14),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }
}

// =============================================================================
// HELPER: mostrar un tooltip suelto sin wrapper
// =============================================================================
Future<void> mostrarTooltipOnboarding({
  required BuildContext context,
  required String tooltipId,
  required OnboardingState state,
}) async {
  if (state.tooltipsVistos.contains(tooltipId)) return;
  final data = OnboardingTooltips.catalogo[tooltipId];
  if (data == null) return;

  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (ctx, anim1, anim2) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim1, anim2, child) {
      return FadeTransition(
        opacity: anim1,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutBack)),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              child: _TooltipCard(
                tooltip: data, current: 1, total: 1,
                onNext: () {
                  OnboardingService.marcarTooltipVisto(tooltipId);
                  Navigator.of(ctx).pop();
                },
              ),
            ),
          ),
        ),
      );
    },
  );
}